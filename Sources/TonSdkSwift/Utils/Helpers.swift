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
}

public extension BigUInt {
    
    func toHex() -> String {
        let hex = String(self, radix: 16)
        return String(hex.suffix(2 * (hex.count / 2)))
    }
}

public extension String {
    
    func hexToBits() -> Bits {
        let hexDigits = "0123456789ABCDEF"
        let binaryDigits = [
            "0000", "0001", "0010", "0011",
            "0100", "0101", "0110", "0111",
            "1000", "1001", "1010", "1011",
            "1100", "1101", "1110", "1111"
        ]

        var result: [UInt8] = []
        for char in self {
            guard let index = hexDigits.firstIndex(of: char) else {
                continue
            }
            let binaryChar = binaryDigits[hexDigits.distance(from: hexDigits.startIndex, to: index)]
            result.append(contentsOf: binaryChar.compactMap { UInt8(String($0)) })
        }
        return .init(result)
    }
    
    func hexToBytes() throws -> Data {
        var hex = self
        hex = hex.replacingOccurrences(of: " ", with: "")
        hex = hex.replacingOccurrences(of: "\n", with: "")
        
        guard hex.count % 2 == 0 else {
            throw ErrorTonSdkSwift("Length not ODD")
        }
        
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                bytes.append(byte)
            } else {
                throw ErrorTonSdkSwift("Failed convert hex to UInt8 radix 16")
            }
            index = nextIndex
        }
        return .init(bytes)
    }
    
    func hexToDataString() throws -> String {
        try hexToBytes().toString()
    }
    
    func toBytes() throws -> Data {
        guard let bytes = data(using: .utf8) else {
            throw ErrorTonSdkSwift("Convert to data utf8 failed")
        }
        return bytes
    }
    
    func base64ToBytes() throws -> Data {
        guard let data = Data(base64Encoded: self) else {
            throw ErrorTonSdkSwift("Convert base64 to data failed")
        }
        return data
    }
}


public extension Data {
    
    func toBigUInt() -> BigUInt {
        BigUInt(self)
    }
    
    func toBits() -> Bits {
        var bitsArray: [UInt8] = []
        
        for byte in self {
            var byteValue = UInt8(byte)
            for _ in 0..<8 {
                bitsArray.insert(byteValue & 1, at: 0)
                byteValue >>= 1
            }
        }
        
        return .init(bitsArray)
    }
    
    func toHex() -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
    
    func toString() throws -> String {
        guard let str = String(data: self, encoding: .utf8) else {
            throw ErrorTonSdkSwift("Convert data to string failed")
        }
        return str
    }
    
    func toBase64(options: Base64EncodingOptions = []) -> String {
        base64EncodedString(options: options)
    }
}
