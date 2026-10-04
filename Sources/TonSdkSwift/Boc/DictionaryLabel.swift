// Original SDK implementation of the TON TL-B dictionary schemas.
// Schema: https://github.com/ton-blockchain/ton/blob/master/crypto/block/block.tlb
import BigInt

/// Shared bounded label codec. All valid encodings are accepted; new labels use
/// the shortest encoding, breaking ties in short/long/same constructor order.
enum DictionaryLabel {
    static func validateWidth(_ width: Int) throws {
        guard (0...1023).contains(width) else {
            throw ErrorTonSdkSwift("Dictionary key width must be in 0...1023")
        }
    }

    static func validateKey(_ key: [Bit], width: Int, prefix: Bool = false) throws {
        try validateWidth(width)
        guard prefix ? key.count <= width : key.count == width else {
            throw ErrorTonSdkSwift("Dictionary key width \(key.count) does not match \(width)")
        }
    }

    static func lengthWidth(_ maximum: Int) -> Int {
        maximum == 0 ? 0 : Int.bitWidth - maximum.leadingZeroBitCount
    }

    static func commonPrefix(_ lhs: [Bit], _ rhs: [Bit]) -> Int {
        var count = 0
        while count < min(lhs.count, rhs.count), lhs[count] == rhs[count] { count += 1 }
        return count
    }

    static func write(_ label: [Bit], maximum: Int, to builder: CellBuilder) throws {
        try validateWidth(maximum)
        guard label.count <= maximum else { throw ErrorTonSdkSwift("Oversized dictionary label") }
        let width = lengthWidth(maximum)
        let shortCost = 2 * label.count + 2
        let longCost = 2 + width + label.count
        let sameCost = 3 + width
        let repeated = label.first.map { bit in label.allSatisfy { $0 == bit } } ?? false
        if shortCost <= longCost && (!repeated || shortCost <= sameCost) {
            try builder.storeBit(.b0).storeBits(Array(repeating: .b1, count: label.count))
                .storeBit(.b0).storeBits(label)
        } else if !repeated || longCost <= sameCost {
            try builder.storeBits([.b1, .b0]).storeUInt(BigUInt(label.count), width).storeBits(label)
        } else {
            try builder.storeBits([.b1, .b1, label[0]]).storeUInt(BigUInt(label.count), width)
        }
    }

    static func read(from slice: CellSlice, maximum: Int) throws -> [Bit] {
        try validateWidth(maximum)
        let length: Int
        if try slice.loadBit() == .b0 {
            var unary = 0
            while try slice.loadBit() == .b1 {
                unary += 1
                guard unary <= maximum else { throw ErrorTonSdkSwift("Oversized short dictionary label") }
            }
            return try slice.loadBits(size: unary)
        }
        let same = try slice.loadBit() == .b1
        let repeated = same ? try slice.loadBit() : .b0
        length = Int(try slice.loadBigUInt(size: lengthWidth(maximum)))
        guard length <= maximum else { throw ErrorTonSdkSwift("Oversized dictionary label") }
        return same ? Array(repeating: repeated, count: length) : try slice.loadBits(size: length)
    }
}

