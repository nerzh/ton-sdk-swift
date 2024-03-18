//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 04.02.2024.
//

import Foundation
import XCTest
import TonSdkSwift
import BigInt

final class CellSliceTests: XCTestCase {
    
    func testCellSlice() async throws {
        let string: String = "/^Hello world[\\s\\S]+\n$"
        let addressRaw: String = "0:93c5a151850b16de3cb2d87782674bc5efe23e6793d343aa096384aafd70812c"
        
        let options: HashmapOptions<BigUInt, BigUInt> = .init(serializers: (
            key: { k in
                return try CellBuilder().storeUInt(k, 16).bits
            },
            value: { v in
                return try CellBuilder().storeUInt(v, 16).cell()
            }
        ))
        let dict = try HashmapE(keySize: 16, options: options)
        try dict.set(17, 289)
        try dict.set(239, 57121)
        try dict.set(32781, 169)
        
        let b = CellBuilder()
        try b.storeUInt(10, 8)
        try b.storeInt(127, 8)
        try b.storeInt(-128, 8)
        try b.storeCoins(Coins(13))
        try b.storeAddress(Address(address: addressRaw))
        try b.storeString(string)
        try b.storeBytes(.init([0, 255, 13]))
        try b.storeMaybeRef(CellBuilder().cell())
        try b.storeMaybeRef(nil)
        try b.storeRef(CellBuilder().storeInt(13, 8).cell())
        try b.storeBit(.b1)
        try b.storeBit(.b0)
        try b.storeBits(.init([0, 1, 0, 1]))
        try b.storeSlice(CellBuilder().cell().parse())
        try b.storeSlice(CellBuilder().storeUInt(1, 9).cell().parse())
        try b.storeDict(dict)
        
        let slice = try b.cell().parse()
        XCTAssertEqual(try slice.loadBigUInt(size: 8), 10)
        XCTAssertEqual(try slice.loadBigInt(size: 8), 127)
        XCTAssertEqual(try slice.loadBigInt(size: 8), -128)
        XCTAssertEqual(try slice.loadCoins(), Coins(13))
        XCTAssertEqual(try slice.loadAddress(), try Address(address: addressRaw))
        XCTAssertEqual(try slice.loadString(size: string.count), string)
        XCTAssertEqual(try slice.loadBytes(size: 3), Data([0, 255, 13]))
        XCTAssertEqual(try slice.loadMaybeRef()?.hash(), try CellBuilder().cell().hash())
        XCTAssertNil(try slice.loadMaybeRef())
        XCTAssertEqual(try slice.loadRef().hash(), try CellBuilder().storeInt(13, 8).cell().hash())
        XCTAssertEqual(try slice.loadBit(), .b1)
        XCTAssertEqual(try slice.loadBit(), .b0)
        XCTAssertEqual(try slice.loadBits(size: 4), .init([0, 1, 0, 1]))
        XCTAssertEqual(try slice.loadSlice(), try CellBuilder().cell().parse())
        XCTAssertEqual(try slice.loadSlice(size: 9), try CellBuilder().storeUInt(1, 9).cell().parse())
        let hashmap: HashmapE<BigUInt, BigUInt> = try slice.loadDict(keySize: 16)
        XCTAssertEqual(try hashmap.cell().hash(), try dict.cell().hash())
    }
}
