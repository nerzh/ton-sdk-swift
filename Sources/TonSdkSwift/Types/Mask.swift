//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 03.02.2024.
//

import Foundation

public struct Mask {
    public var hashIndex: UInt32
    public var hashCount: UInt32
    public var value: UInt32

    public init(mask: Mask) {
        value = mask.value
        hashIndex = Self.countSetBits(value)
        hashCount = hashIndex + 1
    }

    public init(maskValue: UInt32) {
        value = maskValue
        hashIndex = Self.countSetBits(value)
        hashCount = hashIndex + 1
    }

    public var level: UInt32 {
        UInt32(UInt32.bitWidth - value.leadingZeroBitCount)
    }

    public func isSignificant(level: UInt32) -> Bool {
        level == 0 || (level <= UInt32.bitWidth && (value >> (level - 1)) & 1 != 0)
    }
    
    /// Keeps the lowest `level` bits. Widths at or above 32 preserve the full mask.
    public func apply(level: UInt32) -> Mask {
        guard level < UInt32.bitWidth else { return Mask(maskValue: value) }
        return Mask(maskValue: value & ((UInt32(1) << level) - 1))
    }

    private static func countSetBits(_ n: UInt32) -> UInt32 {
        UInt32(n.nonzeroBitCount)
    }
}
