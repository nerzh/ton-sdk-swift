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
        let bytes = try Serializer.serialize(root: [b2.cell()])
        let base64 = bytes.toBase64()
        XCTAssertEqual(base64, "te6cckEBAgEACQABAAEABwAAAyL2hlPi")
        
        let b3 = CellBuilder()
        try b3.storeUInt(200, 30)
        try b3.storeCoins(Coins(nanoValue: 1_000_000))
        let b4 = try CellBuilder().storeRef(b3.cell())
        let bytes2 =  try Serializer.serialize(root: [b4.cell()])
        let base64_2 = bytes2.toBase64()
        XCTAssertEqual(base64_2, "te6cckEBAgEADQABAAEADwAAAyDD0JAgExM09w==")
    }
    
    func testDeserializer() async throws {
        let b = CellBuilder()
        try b.storeUInt(200, 30)
        let b2 = try CellBuilder().storeRef(b.cell())
        let bytes =  try Serializer.serialize(root: [b2.cell()])
        let base64 = bytes.toBase64()
        XCTAssertEqual(base64, "te6cckEBAgEACQABAAEABwAAAyL2hlPi")
        XCTAssertEqual(try Serializer.deserialize(data: bytes).first?.hash(), "5e3573edda7aa9074e83eb706aec33f4ed9ccdd708a82ea92b8eafa947f0ee75")
    }
}


