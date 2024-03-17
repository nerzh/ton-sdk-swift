//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 16.03.2024.
//

import XCTest
import TonSdkSwift
import SwiftExtensionsPack

final class ExampleTests: XCTestCase {
    
    func testExample() async throws {
        /// Init address from string
        let addr = try Address(address: "EQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2N")
        /// Init and fill the builder
        let b = CellBuilder()
        try b.storeUInt(200, 30)
        try b.storeAddress(addr)
        try b.storeCoins(Coins(0.0001))
        
        /// End builder and serialize to boc
        let bytes = try Serializer.serialize(root: [b.cell()])
        let base64 = bytes.toBase64()
        
        print("boc in base64 format:", base64)
        
        /// Deserialize base64 boc
        let cell = try Serializer.deserialize(data: base64.base64ToBytes()).first
        
        /// Parse cell into slice
        let cs = cell?.parse()
        
        /// Load and print values
        XCTAssertEqual(try cs?.loadBigUInt(size: 30), 200)
        XCTAssertEqual(try cs?.loadAddress()?.toString(), "UQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqEBI")
        XCTAssertEqual(try cs?.loadCoins(), Coins(0.0001))
    }
}
