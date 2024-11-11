//
//  File.swift
//  
//
//  Created by O. Hudeichuk on 04.07.2024.
//

import Foundation
import XCTest
import TonSdkSwift
import BigInt
import SwiftExtensionsPack
import Crypto

final class MerkleProofTests: XCTestCase {
    func testMerkleProof() async throws {
        let options: HashmapOptions<BigUInt, Address> = .init(
            serializers: (
                key: { k in
                    try CellBuilder().storeUInt(k, 32).bits
                },
                value: { v in
                    try CellBuilder().storeRef(CellBuilder().storeAddress(v).cell()).cell()
                }
            ),
            deserializers: (
                key: { k in
                    try CellBuilder().storeBits(k).cell().parse().preloadBigUInt(size: 32)
                },
                value: { v in
                    try v.parse().loadRef().parse().loadAddress()!
                }
            )
        )
        
        let dict = try Hashmap(keySize: 32, options: options)
        let arr = [
            "0:0000000000000000000000000000000000000000000000000000000000000000",
            "0:0000000000000000000000000000000000000000000000000000000000000001",
            "0:0000000000000000000000000000000000000000000000000000000000000002",
            "0:0000000000000000000000000000000000000000000000000000000000000003",
            "0:0000000000000000000000000000000000000000000000000000000000000004",
            "0:0000000000000000000000000000000000000000000000000000000000000005",
            "0:0000000000000000000000000000000000000000000000000000000000000006",
            "0:0000000000000000000000000000000000000000000000000000000000000007",
            "0:0000000000000000000000000000000000000000000000000000000000000008",
            "0:0000000000000000000000000000000000000000000000000000000000000009"
        ]
        for (i, a) in arr.enumerated() {
            let address: Address = try .init(address: a)
            try dict.set(.init(i), address)
        }
        XCTAssertEqual(try dict.get(9)?.toString(type: .raw), "0:0000000000000000000000000000000000000000000000000000000000000009")
        XCTAssertEqual(try dict.get(2)?.toString(type: .raw), "0:0000000000000000000000000000000000000000000000000000000000000002")
        XCTAssertEqual(try dict.get(5)?.toString(type: .raw), "0:0000000000000000000000000000000000000000000000000000000000000005")
        XCTAssertEqual(try dict.get(8)?.toString(type: .raw), "0:0000000000000000000000000000000000000000000000000000000000000008")
        XCTAssertEqual(try dict.get(4)?.toString(type: .raw), "0:0000000000000000000000000000000000000000000000000000000000000004")
        
        let proof: Cell = try dict.buildMerkleProof(keys: [9,2,5,8,4])
        let boc = try Boc.serialize(root: [proof])
        let result = try Boc.deserialize(data: boc, checkMerkleProofs: true)
        XCTAssertEqual(try result.first?.hash(), "23cdc9a02d51e83c3273cf39ca99b0b4cf4f1445b6cdc59b8ccf4c20bcceed0e")
    }
    
    func testMustBeNilResult() async throws {
        let options: HashmapOptions<BigUInt, Address> = .init(
            serializers: (
                key: { k in
                    try CellBuilder().storeUInt(k, 32).bits
                },
                value: { v in
                    try CellBuilder().storeRef(CellBuilder().storeAddress(v).cell()).cell()
                }
            ),
            deserializers: (
                key: { k in
                    try CellBuilder().storeBits(k).cell().parse().preloadBigUInt(size: 32)
                },
                value: { v in
                    try v.parse().loadRef().parse().loadAddress()!
                }
            )
        )
        
        // empty hasmap
        let dict = try Hashmap(keySize: 32, options: options)
        XCTAssertEqual(try dict.get(44), nil) // expect nil value
    }
    
    func testFakeMerkleHashProof() async throws {
        let options: HashmapOptions<BigUInt, Address> = .init(
            serializers: (
                key: { k in
                    try CellBuilder().storeUInt(k, 32).bits
                },
                value: { v in
                    try CellBuilder().storeRef(CellBuilder().storeAddress(v).cell()).cell()
                }
            ),
            deserializers: (
                key: { k in
                    try CellBuilder().storeBits(k).cell().parse().preloadBigUInt(size: 32)
                },
                value: { v in
                    try v.parse().loadRef().parse().loadAddress()!
                }
            )
        )
        
        let dict = try Hashmap(keySize: 32, options: options)
        
        let arr = [
            "0:0000000000000000000000000000000000000000000000000000000000000000",
            "0:0000000000000000000000000000000000000000000000000000000000000001",
            "0:0000000000000000000000000000000000000000000000000000000000000002",
            "0:0000000000000000000000000000000000000000000000000000000000000003",
            "0:0000000000000000000000000000000000000000000000000000000000000004",
            "0:0000000000000000000000000000000000000000000000000000000000000005",
            "0:0000000000000000000000000000000000000000000000000000000000000006",
            "0:0000000000000000000000000000000000000000000000000000000000000007",
            "0:0000000000000000000000000000000000000000000000000000000000000008",
            "0:0000000000000000000000000000000000000000000000000000000000000009"
        ]
        
        for (i, a) in arr.enumerated() {
            let address: Address = try .init(address: a)
            try dict.set(.init(i), address)
        }
        
        let proof: Cell = try dict.buildMerkleProof(keys: [9,2,5,8,4])

        let emptyb: CellBuilder = .init()
            
        let fakeb: CellBuilder = try .init()
            .storeInt(BigInt(CellType.merkleProof.rawValue), 8)
            .storeBytes(emptyb.cell().hash(0).hexToBytes()) // fake hash
            .storeUInt(proof.depth() - 1, 16)
            .storeRef(proof.refs[0])

        XCTAssertThrowsError(try fakeb.cell(.merkleProof))
    }
}


