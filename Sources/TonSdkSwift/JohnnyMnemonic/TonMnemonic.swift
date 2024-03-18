//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 07.03.2024.
//

import Foundation
import SwiftExtensionsPack
import enum CryptoSwift.PKCS5

public final class TonMnemonic {
    public static let TON_PBKDF_ITERATIONS = 100_000
    public static let TON_KEYS_SALT = "TON default seed"
    public static let TON_SEED_SALT = "TON seed version"
    public static let TON_PASSWORD_SALT = "TON fast seed version"
    
    public var seed: String
    public var mnemonicArray: [String]
    public var keys: Keys
    public var password: Data?
    public var wordsCount: TonMnemonic.WordsBitsOfEntropy
    
    public typealias Keys = (public: Data, secret: Data)
    
    public init(wordsCount: TonMnemonic.WordsBitsOfEntropy = .w24, password: Data? = nil) throws {
        self.wordsCount = wordsCount
        self.password = password
        self.mnemonicArray = try Self.generateSeed(wordsCount: wordsCount, password: password)
        self.seed = mnemonicArray.joined(separator: " ")
        self.keys = try Self.mnemonicToPrivateKey(mnemonicArray: mnemonicArray, password: password)
    }
    
    public init(seed: String, mnemonicArray: [String], keys: TonMnemonic.Keys, password: Data? = nil, wordsCount: TonMnemonic.WordsBitsOfEntropy) {
        self.seed = seed
        self.mnemonicArray = mnemonicArray
        self.keys = keys
        self.password = password
        self.wordsCount = wordsCount
    }
    
    public init(mnemonicString: String, password: Data? = nil) throws {
        self.mnemonicArray = mnemonicString.components(separatedBy: .whitespaces)
        self.wordsCount = try .get(by: UInt(mnemonicArray.count))
        self.keys = try Self.mnemonicToPrivateKey(mnemonicArray: mnemonicArray, password: password)
        self.seed = mnemonicString
        self.password = password
    }
    
    public class func generateWordsTon(words: TonMnemonic.WordsBitsOfEntropy) throws -> [String] {
        /// bits for 0-2047 number of words array
        let numberBits: UInt = 11
        /// bip39 CS = ENT / 32
        let checkSummLength = words.rawValue / 32
        let bytes = randomBytes(count: words.rawValue / 8)
        var bits = bytes.map {
            var bitString = $0.toBits()
            if bitString.count < 8 {
                bitString = String(repeating: "0", count: 8 - bitString.count) + bitString
            }
            return bitString
        }.joined()
        bits += Data(SEPCrypto.SHA.sha256.digest(data: Data(bytes))).toBits()[0..<Int(checkSummLength)].map { String($0.rawValue) }.joined()
        let bitChunks = bits.chunks(Int(numberBits))
        var result: [String] = .init()
        
        for chunk in bitChunks {
            guard let number = Int(chunk, radix: 2) else {
                throw ErrorTonSdkSwift("Convert bits \(chunk) to Int failed")
            }
            result.append(TonMnemonic.ENGLISH_WORDS[number])
        }
        
        return result
    }
    
    public class func mnemonicToEntropy(mnemonicArray: [String], password: Data? = nil) -> Data {
        let mnemonicData: Data = .init(mnemonicArray.joined(separator: " ").utf8)
        let password: Data = password ?? .init()
        return SEPCrypto.HMAC.sha512.digest(data: password, key: mnemonicData)
    }
    
    public class func isBasicSeed(entropy: Data) throws -> Bool {
        let iter = max(1, TON_PBKDF_ITERATIONS / 256)
        guard let salt = TON_SEED_SALT.data(using: .utf8) else {
            throw ErrorTonSdkSwift("Bad salt \(TON_SEED_SALT)")
        }
        let digest: PKCS5.PBKDF2 = try .init(password: entropy.bytes, salt: salt.bytes, iterations: iter, keyLength: 64, variant: .sha2(.sha512))
        return try digest.calculate().first == 0
    }
    
    public class func isPasswordSeed(entropy: Data) throws -> Bool {
        let iter = 1
        guard let salt = TON_PASSWORD_SALT.data(using: .utf8) else {
            throw ErrorTonSdkSwift("Bad ton_password_salt \(TON_PASSWORD_SALT)")
        }
        let digest: PKCS5.PBKDF2 = try .init(password: entropy.bytes, salt: salt.bytes, iterations: iter, keyLength: 64, variant: .sha2(.sha512))
        
        return try digest.calculate().first == 1
    }
    
    public class func isPasswordNeeded(mnemonicArray: [String]) throws -> Bool {
        let passlessEntropy = mnemonicToEntropy(mnemonicArray: mnemonicArray)
        return try isPasswordSeed(entropy: passlessEntropy) && !(try isBasicSeed(entropy: passlessEntropy))
    }
    
    public class func generateSeed(wordsCount: TonMnemonic.WordsBitsOfEntropy, password: Data? = nil) throws -> [String] {
        var mnemonicArray: [String] = []
        while true {
            mnemonicArray = try generateWordsTon(words: wordsCount)
            if let password, !password.isEmpty {
                if !(try isPasswordNeeded(mnemonicArray: mnemonicArray)) {
                    continue
                }
            }
            if !(try isBasicSeed(entropy: mnemonicToEntropy(mnemonicArray: mnemonicArray, password: password))) {
                continue
            }
            break
        }
        return mnemonicArray
    }
    
    public class func mnemonicToKeyPairs(mnemonicArray: [String], password: Data? = nil) throws -> Keys {
        let mnemonicArray = normalizeMnemonic(words: mnemonicArray)
        guard let salt = TON_KEYS_SALT.data(using: .utf8) else {
            throw ErrorTonSdkSwift("Bad TON_KEYS_SALT \(TON_KEYS_SALT)")
        }
        let seed = try mnemonicToSeed(mnemonicArray: mnemonicArray, salt: salt, password: password)
        return try seedToKeyPairs(seed32Byte: seed[0..<32])
    }
    
    public class func seedToKeyPairs(seed32Byte: Data) throws -> Keys {
        let keyPair = SEPCrypto.Ed25519.createKeyPair(seed32Byte: seed32Byte)
        return (public: keyPair.public, secret: seed32Byte)
    }
    
    public class func mnemonicToPrivateKey(mnemonicArray: [String], password: Data? = nil) throws -> Keys {
        let mnemonicArray = normalizeMnemonic(words: mnemonicArray)
        guard let salt = TON_KEYS_SALT.data(using: .utf8) else {
            throw ErrorTonSdkSwift("Bad TON_KEYS_SALT \(TON_KEYS_SALT)")
        }
        let seed = try mnemonicToSeed(mnemonicArray: mnemonicArray, salt: salt, password: password)
        let keyPair = SEPCrypto.Ed25519.createKeyPair(seed32Byte: seed[0..<32])
        return (public: keyPair.public, secret: seed[0..<32])
    }
    
    public class func mnemonicToSeed(mnemonicArray: [String], salt: Data, password: Data?) throws -> Data {
        let entropy = Self.mnemonicToEntropy(mnemonicArray: mnemonicArray, password: password)
        let digest: PKCS5.PBKDF2 = try .init(password: entropy.bytes, salt: salt.bytes, iterations: Self.TON_PBKDF_ITERATIONS, keyLength: 64, variant: .sha2(.sha512))
        return try Data(digest.calculate())
    }
    
    private class func normalizeMnemonic(words: [String]) -> [String] {
        return words.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
    }
}
