//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 18.03.2024.
//

import Foundation
import XCTest
import TonSdkSwift
import BigInt
import SwiftExtensionsPack

final class CellTests: XCTestCase {
    func testSign() async throws {
        let seed = try "367f30796d66c3119c7674dd30e362aca729c46d809102d4dd135b9451e6169f".hexToBytes()
        let keys = try TonMnemonic.seedToKeyPairs(seed32Byte: seed)
        let cell = try CellBuilder().storeString("test sign").cell()
        let signature = try cell.sign(secretKey32byte: keys.secret)
        XCTAssertEqual(signature.toHexadecimal, "34f16f4074c4cb10b10bf909f9d8444c37bf683ae6f92f07a220fab5544034ecf871d5be7b51c0ef80849aa3e8198eb372967352017a6e6d763406da82d83c08")
    }
}
