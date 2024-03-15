//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 01.02.2024.
//

import Foundation
import XCTest
import TonSdkSwift
import BigInt
import SwiftExtensionsPack
import Crypto

final class AddressTests: XCTestCase {
    
    func testAddresses() async throws {
        var addressRaw: String = "0:93c5a151850b16de3cb2d87782674bc5efe23e6793d343aa096384aafd70812c"
        
        var address: Address = try .init(address: addressRaw)
        XCTAssertEqual(address.workchain, 0)
        XCTAssertEqual(address.bounceable, false)
        XCTAssertEqual(address.testOnly, false)
        XCTAssertEqual(address.hash, try String(addressRaw.split(separator: ":")[1]).hexToBytes())
        
        address = try .init(address: "EQCTxaFRhQsW3jyy2HeCZ0vF7-I-Z5PTQ6oJY4Sq_XCBLPPw")
        XCTAssertEqual(address.workchain, 0)
        XCTAssertEqual(address.bounceable, true)
        XCTAssertEqual(address.testOnly, false)
        XCTAssertEqual(address.hash, try String(addressRaw.split(separator: ":")[1]).hexToBytes())
        
        address = try .init(address: "UQCTxaFRhQsW3jyy2HeCZ0vF7-I-Z5PTQ6oJY4Sq_XCBLK41")
        XCTAssertEqual(address.workchain, 0)
        XCTAssertEqual(address.bounceable, false)
        XCTAssertEqual(address.testOnly, false)
        XCTAssertEqual(address.hash, try String(addressRaw.split(separator: ":")[1]).hexToBytes())
        
        address = try .init(address: "kQCTxaFRhQsW3jyy2HeCZ0vF7-I-Z5PTQ6oJY4Sq_XCBLEh6")
        XCTAssertEqual(address.workchain, 0)
        XCTAssertEqual(address.bounceable, true)
        XCTAssertEqual(address.testOnly, true)
        XCTAssertEqual(address.hash, try String(addressRaw.split(separator: ":")[1]).hexToBytes())
        
        address = try .init(address: "0QCTxaFRhQsW3jyy2HeCZ0vF7-I-Z5PTQ6oJY4Sq_XCBLBW_")
        XCTAssertEqual(address.workchain, 0)
        XCTAssertEqual(address.bounceable, false)
        XCTAssertEqual(address.testOnly, true)
        XCTAssertEqual(address.hash, try String(addressRaw.split(separator: ":")[1]).hexToBytes())
        
        let addrBase64 = "Ef8w0Zxb55PR2HtfD793UTXggGNNZJcTKh3bh4u4X-nMWGK-"
        addressRaw = "-1:30d19c5be793d1d87b5f0fbf775135e080634d6497132a1ddb878bb85fe9cc58"
        address = try .init(address: addrBase64)
        XCTAssertEqual(address.workchain, -1)
        XCTAssertEqual(address.bounceable, true)
        XCTAssertEqual(address.testOnly, false)
        XCTAssertEqual(address.hash, try String(addressRaw.split(separator: ":")[1]).hexToBytes())
    }
}

