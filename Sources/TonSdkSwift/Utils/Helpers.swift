//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 30.01.2024.
//

import Foundation
import BigInt
import SwiftExtensionsPack

public extension Array {
    func chunked(size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
    
    mutating func shift(_ amount: Int) -> Self {
        var result: [Element] = .init()
        for _ in 0..<amount {
            result.append(self[0])
            self.remove(at: 0)
        }
        return result
    }
}

public extension BigUInt {
    
    func toHex() -> String {
        let hex = String(self, radix: 16)
        return String(hex.suffix(2 * (hex.count / 2)))
    }
}

public extension String {
    
    func hexToBits() -> [Bit] {
        var result: [Bit] = .init()
        
        for val in self {
            if let chunk = Int(String(val), radix: 16) {
                let binaryString = String(chunk, radix: 2)
                let paddedBinaryString = String(repeating: "0", count: 4 - binaryString.count) + binaryString
                for bit in paddedBinaryString {
                    if let bitValue = Int(String(bit)) {
                        result.append(bitValue > 0 ? .b1 : .b0)
                    }
                }
            }
        }
        
        return result
    }
    
    func hexToBytes() throws -> Data {
        var hex = self
        hex = hex.replacingOccurrences(of: " ", with: "")
        hex = hex.replacingOccurrences(of: "\n", with: "")
        
        guard hex.count % 2 == 0 else {
            throw ErrorTonSdkSwift("Length not ODD for: \(hex)")
        }
        
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                bytes.append(byte)
            } else {
                throw ErrorTonSdkSwift("Failed convert hex to UInt8 radix 16 for: \(self)")
            }
            index = nextIndex
        }
        return .init(bytes)
    }
    
    func hexToBytesUnsafe() -> Data {
        try! hexToBytes()
    }
    
    func hexToDataString() throws -> String {
        try hexToBytes().toString()
    }
    
    func toBytes() throws -> Data {
        guard let bytes = data(using: .utf8) else {
            throw ErrorTonSdkSwift("Convert to data utf8 failed for: \(self)")
        }
        return bytes
    }
    
    func base64ToBytes() throws -> Data {
        guard let data = Data(base64Encoded: self) else {
            throw ErrorTonSdkSwift("Convert base64 to data failed for: \(self)")
        }
        return data
    }
    
    func base64BocToCells(checkMerkleProofs: Bool = false) throws -> [Cell] {
        try Boc.deserialize(data: base64ToBytes(), checkMerkleProofs: checkMerkleProofs)
    }
    
    func hexBocToCells(checkMerkleProofs: Bool = false) throws -> [Cell] {
        try Boc.deserialize(data: hexToBytes(), checkMerkleProofs: checkMerkleProofs)
    }
}


public extension Data {
    
    func toBigUInt() -> BigUInt {
        BigUInt(self)
    }
    
    func toBits() -> [Bit] {
        var result: [UInt8] = []
        
        result = self.bytes.reduce(into: []) { acc, uint in
            let chunk = String(uint, radix: 2)
            let paddedBinaryString = String(repeating: "0", count: 8 - chunk.count) + chunk
            acc.append(contentsOf: paddedBinaryString.compactMap { UInt8(String($0)) })
        }
        
        return .init(result)
    }

    
    func toHex() -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
    
    func toString() throws -> String {
        guard let str = String(data: self, encoding: .utf8) else {
            throw ErrorTonSdkSwift("Convert data to string failed for \(self.bytes.join(", "))")
        }
        return str
    }
    
    func toBase64(options: Base64EncodingOptions = []) -> String {
        base64EncodedString(options: options)
    }
    
    func bocToCells(checkMerkleProofs: Bool = false) throws -> [Cell] {
        try Boc.deserialize(data: self, checkMerkleProofs: checkMerkleProofs)
    }
}
