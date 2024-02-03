//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 30.01.2024.
//

import XCTest
@testable import TonSdkSwift
import BigInt
import SwiftExtensionsPack
import Crypto

final class CryptoTests: XCTestCase {
    
    func testChecksumCRC16() async throws {
        let bits: Data = .init([1,0,1,1,1])
        XCTAssertEqual(bits.crc16(), 48753)
    }
    
    func testChecksumCRC32C() async throws {
        let bits: Data = .init([1,0,1,1,1])
        XCTAssertEqual(bits.crc32c(), 971739283)
    }
    
    func testChecksumCrc16BytesBE() async throws {
        let bits: Data = .init([1,0,1,1,1])
        XCTAssertEqual(bits.crc16BytesBE(), Data([190, 113]))
    }
    
    func testChecksumCrc32cBytesLE() async throws {
        let bits: Data = .init([1,0,1,1,1])
        XCTAssertEqual(bits.crc32cBytesLE(), Data([147, 144, 235, 57]))
    }
    
    func testChecksumSHA256() async throws {
        let bits: Data = .init([1,0,1,1,1])
        XCTAssertEqual(bits.sha256(), "4bd22da7d13bbe6f159914f6b38fd1c4530e84b50112eeabd69b999b7218e4c3")
    }
    
    func testChecksumSHA512() async throws {
        let bits: Data = .init([1,0,1,1,1])
        XCTAssertEqual(bits.sha512(), "493580872d46567d51ed2f1be8c88fb62aca3f8c4050a3fd04400abc4dd95cc67006b070e71d2a26fc1a538448d74ee2a3b8224a7b6b1b1ab0499b356da89f3b")
    }
}

