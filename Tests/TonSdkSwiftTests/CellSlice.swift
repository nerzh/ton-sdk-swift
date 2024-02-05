//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 04.02.2024.
//

import Foundation
import XCTest
@testable import TonSdkSwift
import BigInt

final class CellSliceTests: XCTestCase {
    func testCellSlice() async throws {
        let string: String = "/^Hello world[\\s\\S]+\n$"
        let addressRaw: String = "0:93c5a151850b16de3cb2d87782674bc5efe23e6793d343aa096384aafd70812c"
        print("OK")
        
        let b = CellBuilder()
        try b.storeUInt(10, 8)
        try b.storeInt(127, 8)
        try b.storeCoins(Coins(13))
        print("OK111")
        try b.storeAddress(Address(address: addressRaw))
        print("OK222")
        try b.storeString(string)
        try b.storeBytes(.init([0, 255, 13]))
        print("OK2")
        try b.storeMaybeRef(CellBuilder().cell())
        print("NOT OK")
        try b.storeMaybeRef(nil)
        try b.storeRef(CellBuilder().storeInt(13, 8).cell())
        try b.storeBit(.b1)
        try b.storeBit(.b0)
        try b.storeBits(.init([0, 1, 0, 1]))
//        try b.storeDict(@dict)
        print("OK4")
        var slice = try b.cell()
//            .parse()
        print("OK5")
//        XCTAssertEqual(try slice.loadBigUInt(size: 8), 10)
    }
}
