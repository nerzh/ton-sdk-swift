//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 06.03.2024.
//

import XCTest
import TonSdkSwift
import BigInt
import SwiftExtensionsPack
import Crypto

final class DeSerializerTests: XCTestCase {
    
    func testSerializer() async throws {
        let b = CellBuilder()
        try b.storeUInt(200, 30)
        let b2 = try CellBuilder().storeRef(b.cell())
        let bytes = try Boc.serialize(root: [b2.cell()])
        let base64 = bytes.toBase64()
        XCTAssertEqual(base64, "te6cckEBAgEACQABAAEABwAAAyL2hlPi")
        
        let b3 = CellBuilder()
        try b3.storeUInt(200, 30)
        try b3.storeCoins(Coins(nanoValue: 1_000_000))
        let b4 = try CellBuilder().storeRef(b3.cell())
        let bytes2 =  try Boc.serialize(root: [b4.cell()])
        let base64_2 = bytes2.toBase64()
        XCTAssertEqual(base64_2, "te6cckEBAgEADQABAAEADwAAAyDD0JAgExM09w==")
    }
    
    func testDeserializer() async throws {
        let b = CellBuilder()
        try b.storeUInt(200, 30)
        let b2 = try CellBuilder().storeRef(b.cell())
        let bytes =  try Boc.serialize(root: [b2.cell()])
        let base64 = bytes.toBase64()
        XCTAssertEqual(base64, "te6cckEBAgEACQABAAEABwAAAyL2hlPi")
        XCTAssertEqual(try Boc.deserialize(data: bytes).first?.hash(), "5e3573edda7aa9074e83eb706aec33f4ed9ccdd708a82ea92b8eafa947f0ee75")
    }
    
    func testDeserializeCell() async throws {
        let bytes =  try Boc.deserializeCell(remainder: Data([1, 20, 255, 0, 244, 164, 19, 244, 188, 242, 200, 11, 1, 2, 1, 32, 2, 3, 2, 1, 72, 4, 5, 1, 234, 242, 131, 8, 215, 24, 32, 211, 31, 211, 63, 248, 35, 170, 31, 83, 32, 185, 242, 99, 237, 68, 208, 211, 31, 211, 63, 211, 255, 244, 4, 209, 83, 96, 128, 64, 244, 14, 111, 161, 49, 242, 96, 81, 115, 186, 242, 162, 7, 249, 1, 84, 16, 135, 249, 16, 242, 163, 2, 244, 4, 209, 248, 0, 127, 142, 22, 33, 128, 16, 244, 120, 111, 165, 32, 152, 2, 211, 7, 212, 48, 1, 251, 0, 145, 50, 226, 1, 179, 230, 91, 131, 37, 161, 200, 64, 52, 128, 64, 244, 67, 138, 230, 49, 1, 200, 203, 31, 19, 203, 63, 203, 255, 244, 0, 201, 237, 84, 8, 0, 4, 208, 48, 2, 1, 32, 6, 7, 0, 23, 189, 156, 231, 106, 38, 134, 154, 249, 142, 184, 95, 252, 0, 65, 190, 95, 151, 106, 38, 134, 152, 249, 142, 153, 254, 159, 249, 143, 160, 38, 138, 145, 4, 2, 7, 160, 115, 125, 9, 140, 146, 219, 252, 149, 221, 31, 20, 0, 52, 32, 128, 64, 244, 150, 111, 165, 108, 18, 32, 148, 48, 83, 3, 185, 222, 32, 147, 51, 54, 1, 146, 108, 33, 226, 179]), refIndexSize: 1)
        XCTAssertEqual(bytes.remainder, Data([2, 1, 32, 2, 3, 2, 1, 72, 4, 5, 1, 234, 242, 131, 8, 215, 24, 32, 211, 31, 211, 63, 248, 35, 170, 31, 83, 32, 185, 242, 99, 237, 68, 208, 211, 31, 211, 63, 211, 255, 244, 4, 209, 83, 96, 128, 64, 244, 14, 111, 161, 49, 242, 96, 81, 115, 186, 242, 162, 7, 249, 1, 84, 16, 135, 249, 16, 242, 163, 2, 244, 4, 209, 248, 0, 127, 142, 22, 33, 128, 16, 244, 120, 111, 165, 32, 152, 2, 211, 7, 212, 48, 1, 251, 0, 145, 50, 226, 1, 179, 230, 91, 131, 37, 161, 200, 64, 52, 128, 64, 244, 67, 138, 230, 49, 1, 200, 203, 31, 19, 203, 63, 203, 255, 244, 0, 201, 237, 84, 8, 0, 4, 208, 48, 2, 1, 32, 6, 7, 0, 23, 189, 156, 231, 106, 38, 134, 154, 249, 142, 184, 95, 252, 0, 65, 190, 95, 151, 106, 38, 134, 152, 249, 142, 153, 254, 159, 249, 143, 160, 38, 138, 145, 4, 2, 7, 160, 115, 125, 9, 140, 146, 219, 252, 149, 221, 31, 20, 0, 52, 32, 128, 64, 244, 150, 111, 165, 108, 18, 32, 148, 48, 83, 3, 185, 222, 32, 147, 51, 54, 1, 146, 108, 33, 226, 179]))
    }
}


