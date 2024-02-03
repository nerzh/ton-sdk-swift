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
        32 - countLeadingZeroes32(number: value)
    }

    public func isSignificant(level: UInt32) -> Bool {
        level == 0 || (value >> (level - 1)) % 2 != 0
    }

    public func apply(level: UInt32) -> Mask {
        Mask(maskValue: value & ((1 << level) - 1))
    }

    private func countLeadingZeroes32(number: UInt32, size: UInt32 = 32) -> UInt32 {
        let bitsString = String(number, radix: 2)
        let sliceStartIndex = max(0, bitsString.count - Int(size))
        let truncatedBitsString = String(bitsString.suffix(from: bitsString.index(bitsString.startIndex, offsetBy: sliceStartIndex)))
        return size - UInt32(truncatedBitsString.count)
    }

    private static func countSetBits(_ n: UInt32) -> UInt32 {
        var count = n - ((n >> 1) & 0x55555555)
        count = (count & 0x33333333) + ((count >> 2) & 0x33333333)
        return ((count + (count >> 4) & 0xF0F0F0F) * 0x1010101) >> 24
    }
}
