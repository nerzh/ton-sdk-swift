//
//  Bits.swift
//
//
//  Created by Oleh Hudeichuk on 29.01.2024.
//

import Foundation
import BigInt
import SwiftExtensionsPack

public enum Bit: UInt8, Comparable {
    case b0 = 0
    case b1 = 1
    
    public static func < (lhs: Bit, rhs: Bit) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Bits: Equatable {
    public var bits: [Bit]
    public var bitsUInt8: [UInt8] {
        bits.map { $0.rawValue }
    }

    public init(_ bits: [Bit]) {
        self.bits = bits
    }
    
    public init(_ bits: [UInt8]) {
        self.bits = bits.map { $0 < 1 ? .b0 : .b1 }
    }
    
    public func augment(divider: Int = 8) -> Self {
        var bitsCopy = self
        let amount = divider - (count % divider)
        var overage = Bits(repeating: .b0, count: amount)
        overage[0] = .b1

        if overage.count != 0 && overage.count != divider {
            bitsCopy.append(contentsOf: overage)
        }

        return bitsCopy
    }
    
    public func rollback() throws -> Self {
        guard let index = suffix(7).reversed().firstIndex(of: .b1) else {
            throw ErrorTonSdkSwift("Incorrectly augmented bits.")
        }
        
        return Bits(prefix(count - (index + 1)))
    }
    
    public mutating func selfRollback() throws {
        guard let index = suffix(7).reversed().firstIndex(of: .b1) else {
            throw ErrorTonSdkSwift("Incorrectly augmented bits.")
        }
        
        let collection: Slice<Bits> = prefix(count - (index + 1))
        self.bits = collection.map { $0 }
    }
    
    public func toBigUInt() -> BigUInt {
        var result = BigUInt(0)
        for bit in bits {
            result <<= 1
            result |= BigUInt(bit.rawValue)
        }
        return result
    }
    
    public func toBigInt() -> BigInt {
        if isEmpty { return 0 }
        
        let uint = BigInt(toBigUInt())
        let size = BigInt(count)
        let int = BigInt(1) << (size - 1)
        let value = uint >= int ? (uint - (int * 2)) : uint

        return value
    }
    
    public func toHex() throws -> String {
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
    
    public func toBytes() throws -> Data {
        try toHex().hexToBytes()
    }
}

extension Bits: MutableCollection {
    
    public typealias Index = Int
    public typealias Element = Bit
    
    public var startIndex: Int { bits.startIndex }
    public var endIndex: Int { bits.endIndex }

    public subscript(position: Int) -> Bit {
        get {
            bits[position]
        }
        set(newValue) {
            bits[position] = newValue
        }
    }

    public func index(after i: Int) -> Int {
        return bits.index(after: i)
    }
}

extension Bits: RangeReplaceableCollection {
    public init() {
        self.bits = []
    }
    
    public mutating func replaceSubrange<C>(_ subrange: Range<Int>, with newElements: C) where C : Collection, Bit == C.Element {
        bits.replaceSubrange(subrange, with: newElements)
    }
}
