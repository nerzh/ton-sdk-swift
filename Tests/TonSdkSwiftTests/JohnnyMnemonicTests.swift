//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 08.03.2024.
//

import XCTest
import TonSdkSwift
import SwiftExtensionsPack
//@testable import TonSdkSwift

final class JohnnyMnemonicTests: XCTestCase {
    
    func testMnemonicToEntropy() async throws {
        let mnemonicArray = ["fruit", "fog", "amused", "illness", "abstract", "valid", "keep", "play", "wash", "polar", "that", "appear"]
        let hash = TonMnemonic.mnemonicToEntropy(mnemonicArray: mnemonicArray).toHexadecimal
        XCTAssertEqual(hash, "9e9ba97d5b6f703b6f71fc7288998673fa8a339c700663020553ddfa39af33062ee51c331301aaf18b79bb107c42a4b550d74469af0498f75a382712866bfa94")
    }

    func testMnemonicToSeedKnownAnswers() throws {
        let mnemonicArray = ["fruit", "fog", "amused", "illness", "abstract", "valid", "keep", "play", "wash", "polar", "that", "appear"]
        // Independent HMAC-SHA512 and PBKDF2-SHA512 vectors generated with Python hashlib.
        let vectors: [(password: Data?, expected: String)] = [
            (nil, "c9275fe6b510fe898f868342173519f54b59b59895b7ab16f5fb308aa2c80bfff8aaa80a9b1aa0f6848818ceba4379850657486b3ab0022e2b8b41f604a11153"),
            (Data([0, 255, 128, 1]), "5f8754f35a06af83380b9f0a2cd3f4f86871ba62b470bc1c6701ed4a39cd2d89e46989c85e83f491c884646c8e09c079107e54577b747f411d23a0aef403b906")
        ]
        for vector in vectors {
            let seed = try TonMnemonic.mnemonicToSeed(
                mnemonicArray: mnemonicArray,
                salt: Data("TON default seed".utf8),
                password: vector.password
            )
            XCTAssertEqual(seed.count, 64)
            XCTAssertEqual(seed.toHexadecimal, vector.expected)
        }
    }
    
    func testGenerateWords() async throws {
        let words = try TonMnemonic.generateSeed(wordsCount: .w24)
        print(words.joined(separator: " "))
//        XCTAssertEqual(words.count, 12)
    }
    
    func testBasicSeed() async throws {
        let isBasicSeed = try TonMnemonic.isBasicSeed(entropy: "5f97f8ee98d10b5d3d077fbded838b9c949915e062f89cf38606c65cdbc9fcb13f210264a9f1b7e8b5a54faecb325cac790423bfe389c14fe36751588b8a934a".hexToBytes())
        XCTAssertEqual(isBasicSeed, false)
        
        let isBasicSeed2 = try TonMnemonic.isBasicSeed(entropy: "9e9ba97d5b6f703b6f71fc7288998673fa8a339c700663020553ddfa39af33062ee51c331301aaf18b79bb107c42a4b550d74469af0498f75a382712866bfa94".hexToBytes())
        XCTAssertEqual(isBasicSeed2, true)
    }
    
    func testIsPasswordSeed() async throws {
        let words = try TonMnemonic.isPasswordSeed(entropy: "f299791cddd3d6664f6670842812ef6053eb6501bd6282a476bbbf3ee91e750c".hexToBytes())
        XCTAssertEqual(words, true)
        
        let words2 = try TonMnemonic.isPasswordSeed(entropy: "4a64a107f0cb32536e5bce6c98c393db21cca7f4ea187ba8c4dca8b51d4ea80a".hexToBytes())
        XCTAssertEqual(words2, false)
    }
    
    func testIsPasswordNeeded() async throws {
        let mnemonicArray = ["fruit", "fog", "amused", "illness", "abstract", "valid", "keep", "play", "wash", "polar", "that", "appear"]
        let isPasswordNeeded = try TonMnemonic.isPasswordNeeded(mnemonicArray: mnemonicArray)
        XCTAssertEqual(isPasswordNeeded, false)
    }
    
    func testGenerateSeed() async throws {
        let words = try TonMnemonic.generateSeed(wordsCount: .w12)
        XCTAssertEqual(words.count, 12)
        
        let words2 = try TonMnemonic.generateSeed(wordsCount: .w18)
        XCTAssertEqual(words2.count, 18)
        
        let words3 = try TonMnemonic.generateSeed(wordsCount: .w24)
        XCTAssertEqual(words3.count, 24)
    }
}


