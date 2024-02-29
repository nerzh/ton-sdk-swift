//
//  Bits.swift
//
//
//  Created by Oleh Hudeichuk on 29.01.2024.
//

import Foundation
import BigInt
import SwiftExtensionsPack

public enum Bit: UInt8, Comparable, LosslessStringConvertible {
    case b0 = 0
    case b1 = 1
    
    public var description: String { String(rawValue) }
    
    public init?(_ description: String) {
        guard
            let intValue = UInt8(description),
            let value = Self.init(rawValue: intValue)
        else {
            return nil
        }
        self = value
    }
    
    public init(_ bit: any SignedInteger) throws {
        let intValue = Int(bit)
        if !(intValue == 0 || intValue == 1) {
            throw ErrorTonSdkSwift("Incorrectly bit")
        }
        let unsignedValue: UInt8 = .init(bit)
        guard let value = Self(rawValue: unsignedValue) else {
            throw ErrorTonSdkSwift("Unknown bit")
        }
        self = value
    }
    
    public static func < (lhs: Bit, rhs: Bit) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public extension Array where Element == Bit {
    
    var bitsUInt8: [UInt8] {
        map { $0.rawValue }
    }
    
    init(_ bits: [UInt8]) {
        self = bits.map { $0 < 1 ? .b0 : .b1 }
    }
    
    func augment(divider: Int = 8) -> Self {
        var bitsCopy = self
        let amount = divider - (count % divider)
        var overage: [Bit] = .init(repeating: .b0, count: amount)
        overage[0] = .b1

        if overage.count != 0 && overage.count != divider {
            bitsCopy.append(contentsOf: overage)
        }

        return bitsCopy
    }
    
    func rollback() throws -> Self {
        var oneBitExist: Bool = false
        var index = count - 1
        var result: [Bit] = .init()
        while index >= 0 {
            let element: Bit = self[index]
            if !oneBitExist, element == .b1 {
                oneBitExist = true
                index -= 1
                continue
            }
            if oneBitExist {
                result.append(element)
            }
            index -= 1
        }
        
        if !oneBitExist { throw ErrorTonSdkSwift("Incorrectly augmented bits.") }
        
        return result.reversed()
    }
    
    mutating func selfRollback() throws {
        self = try rollback()
    }
    
    func toBigUInt() -> BigUInt {
        var result = BigUInt(0)
        for bit in self {
            result <<= 1
            result |= BigUInt(bit.rawValue)
        }
        return result
    }
    
    func toBigInt() -> BigInt {
        if isEmpty { return 0 }
        
        let uint = BigInt(toBigUInt())
        let size = BigInt(count)
        let int = BigInt(1) << (size - 1)
        let value = uint >= int ? (uint - (int * 2)) : uint

        return value
    }
    
    func toHex() throws -> String {
        
        guard count % 4 == 0 else {
            throw ErrorTonSdkSwift("Bits amount must be multiple of 4")
        }
        
        var hexString = ""
        for chunk in bitsUInt8.chunked(size: 4) {
            let nibble = chunk.reduce(0) { result, bit in
                (result << 1) + bit
            }
            hexString += String(format: "%X", nibble)
        }
        return hexString
    }
    
    func toBytes() throws -> Data {
        try toHex().hexToBytes()
    }
}


