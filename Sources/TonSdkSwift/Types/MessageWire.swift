import Foundation
import BigInt

/// TON TL-B Anycast. The depth is encoded in five bits and must be 1...30.
public struct Anycast: Equatable {
    public let rewritePrefix: [Bit]

    public init(rewritePrefix: [Bit]) throws {
        guard (1...30).contains(rewritePrefix.count) else {
            throw ErrorTonSdkSwift("Anycast depth must be between 1 and 30")
        }
        self.rewritePrefix = rewritePrefix
    }
}

/// Raw TL-B addresses, independent of friendly address formatting.
/// See ton-blockchain/ton, crypto/block/block.tlb (addr_none/extern/std/var).
public enum MessageAddress: Equatable {
    case none
    case external([Bit])
    case standard(workchain: Int8, address: Data, anycast: Anycast? = nil)
    case variable(workchain: Int32, address: [Bit], anycast: Anycast? = nil)

    public init(_ address: Address?) {
        self = address.map { .standard(workchain: $0.workchain, address: $0.hash) } ?? .none
    }

    public var isInternal: Bool {
        switch self { case .standard, .variable: return true; default: return false }
    }

    public var isExternal: Bool { !isInternal }

    /// Only standard addresses without anycast have a lossless friendly representation.
    public func asAddress() throws -> Address? {
        switch self {
        case .none: return nil
        case let .standard(workchain, address, anycast) where anycast == nil:
            guard address.count == 32 else { throw ErrorTonSdkSwift("Standard address requires 256 bits") }
            let hex = address.map { String(format: "%02x", $0) }.joined()
            return try Address(address: "0:" + hex, workchain: workchain)
        default: throw ErrorTonSdkSwift("Raw address cannot be represented as a friendly Address")
        }
    }

    public func cell() throws -> Cell {
        let builder = CellBuilder()
        func storeAnycast(_ value: Anycast?) throws {
            try builder.storeBit(value == nil ? .b0 : .b1)
            if let value {
                try builder.storeUInt(BigUInt(value.rewritePrefix.count), 5).storeBits(value.rewritePrefix)
            }
        }
        switch self {
        case .none:
            try builder.storeUInt(0, 2)
        case let .external(bits):
            guard bits.count <= 511 else { throw ErrorTonSdkSwift("External address exceeds 511 bits") }
            try builder.storeUInt(1, 2).storeUInt(BigUInt(bits.count), 9).storeBits(bits)
        case let .standard(workchain, address, anycast):
            guard address.count == 32 else { throw ErrorTonSdkSwift("Standard address requires 256 bits") }
            try builder.storeUInt(2, 2)
            try storeAnycast(anycast)
            try builder.storeInt(BigInt(workchain), 8).storeBytes(address)
        case let .variable(workchain, address, anycast):
            guard address.count <= 511 else { throw ErrorTonSdkSwift("Variable address exceeds 511 bits") }
            try builder.storeUInt(3, 2)
            try storeAnycast(anycast)
            try builder.storeUInt(BigUInt(address.count), 9).storeInt(BigInt(workchain), 32).storeBits(address)
        }
        return try builder.cell()
    }

    @discardableResult
    public func store(to builder: CellBuilder) throws -> CellBuilder {
        try builder.storeSlice(cell().parse())
    }

    public static func parse(cs: CellSlice) throws -> Self {
        func loadAnycast() throws -> Anycast? {
            guard try cs.loadBit() == .b1 else { return nil }
            let depth = Int(try cs.loadBigUInt(size: 5))
            guard (1...30).contains(depth) else { throw ErrorTonSdkSwift("Invalid anycast depth") }
            return try Anycast(rewritePrefix: cs.loadBits(size: depth))
        }
        switch try cs.loadBigUInt(size: 2) {
        case 0: return .none
        case 1:
            let length = Int(try cs.loadBigUInt(size: 9))
            return try .external(cs.loadBits(size: length))
        case 2:
            let anycast = try loadAnycast()
            let workchain = Int8(try cs.loadBigInt(size: 8))
            return try .standard(workchain: workchain, address: cs.loadBytes(size: 32), anycast: anycast)
        default:
            let anycast = try loadAnycast()
            let length = Int(try cs.loadBigUInt(size: 9))
            let workchain = Int32(try cs.loadBigInt(size: 32))
            return try .variable(workchain: workchain, address: cs.loadBits(size: length), anycast: anycast)
        }
    }
}

/// Raw TON amounts: grams are VarUInteger 16; extra currencies use uint32 keys
/// and VarUInteger 32 values. This model performs no currency conversion.
public struct CurrencyCollection {
    public var grams: BigUInt
    public private(set) var other: RawHashmap

    public init(grams: BigUInt = 0, otherRoot: Cell? = nil) throws {
        guard grams.bitWidth <= 120 else { throw ErrorTonSdkSwift("Grams exceed 120 bits") }
        self.grams = grams
        self.other = try RawHashmap(keySize: 32, root: otherRoot)
    }

    public func amount(for currency: UInt32) throws -> BigUInt? {
        let key = try CellBuilder().storeUInt(BigUInt(currency), 32).bits
        guard let value = try other.get(key) else { return nil }
        let amount = try value.loadVarBigUInt(length: 32)
        guard value.bits.isEmpty && value.refs.isEmpty else { throw ErrorTonSdkSwift("Extra currency contains trailing data") }
        return amount
    }

    public mutating func setAmount(_ amount: BigUInt, for currency: UInt32) throws {
        guard amount.bitWidth <= 248 else { throw ErrorTonSdkSwift("Extra currency exceeds 248 bits") }
        let key = try CellBuilder().storeUInt(BigUInt(currency), 32).bits
        let value = try CellBuilder().storeVarUInt(amount, 32).cell().parse()
        _ = try other.set(key, value: value)
    }

    @discardableResult
    public mutating func removeAmount(for currency: UInt32) throws -> Bool {
        let key = try CellBuilder().storeUInt(BigUInt(currency), 32).bits
        return try other.remove(key) != nil
    }

    /// Visits currency identifiers in unsigned ascending order; false stops early.
    @discardableResult
    public func forEachAmount(_ visit: (UInt32, BigUInt) throws -> Bool) throws -> Bool {
        try other.iterate { key, value in
            let amount = try value.loadVarBigUInt(length: 32)
            guard value.bits.isEmpty && value.refs.isEmpty else {
                throw ErrorTonSdkSwift("Extra currency contains trailing data")
            }
            return try visit(UInt32(key.toBigUInt()), amount)
        }
    }

    public func cell() throws -> Cell {
        guard grams.bitWidth <= 120 else { throw ErrorTonSdkSwift("Grams exceed 120 bits") }
        let builder = try CellBuilder().storeVarUInt(grams, 16)
        try other.write(to: builder)
        return try builder.cell()
    }

    public static func parse(cs: CellSlice) throws -> Self {
        let grams = try cs.loadVarBigUInt(length: 16)
        let other = try RawHashmap.read(from: cs, keySize: 32)
        return try Self(grams: grams, otherRoot: other.root)
    }
}

public struct RawInternalMessageInfo {
    public var ihrDisabled: Bool
    public var bounce: Bool
    public var bounced: Bool
    public var src: MessageAddress
    public var dest: MessageAddress
    public var value: CurrencyCollection
    /// Legacy ihr_fee field; current TON schemas call the same wire field extra_flags.
    public var ihrFee: BigUInt
    public var fwdFee: BigUInt
    public var createdLt: UInt64
    public var createdAt: UInt32

    public init(ihrDisabled: Bool = true, bounce: Bool = false, bounced: Bool = false,
                src: MessageAddress = .none, dest: MessageAddress, value: CurrencyCollection,
                ihrFee: BigUInt = 0, fwdFee: BigUInt = 0, createdLt: UInt64 = 0, createdAt: UInt32 = 0) {
        self.ihrDisabled = ihrDisabled; self.bounce = bounce; self.bounced = bounced
        self.src = src; self.dest = dest; self.value = value; self.ihrFee = ihrFee
        self.fwdFee = fwdFee; self.createdLt = createdLt; self.createdAt = createdAt
    }
}

public struct RawExternalInboundMessageInfo {
    public var src: MessageAddress
    public var dest: MessageAddress
    public var importFee: BigUInt

    public init(src: MessageAddress = .none, dest: MessageAddress, importFee: BigUInt = 0) {
        self.src = src; self.dest = dest; self.importFee = importFee
    }
}

public struct RawExternalOutboundMessageInfo {
    public var src: MessageAddress
    public var dest: MessageAddress
    public var createdLt: UInt64
    public var createdAt: UInt32

    public init(src: MessageAddress, dest: MessageAddress = .none, createdLt: UInt64 = 0, createdAt: UInt32 = 0) {
        self.src = src; self.dest = dest; self.createdLt = createdLt; self.createdAt = createdAt
    }
}

/// Full wire header. Explicitly select relaxed source validation for outgoing
/// messages with any MsgAddress, including addr_none and addr_extern, as allowed
/// by CommonMsgInfoRelaxed. Inbound headers always retain their strict categories.
public enum RawCommonMsgInfo {
    case internalMessage(RawInternalMessageInfo)
    case externalInbound(RawExternalInboundMessageInfo)
    case externalOutbound(RawExternalOutboundMessageInfo)

    public func cell(relaxed: Bool = false) throws -> Cell {
        let b = CellBuilder()
        func internalSource(_ address: MessageAddress) throws {
            guard address.isInternal || relaxed else {
                throw ErrorTonSdkSwift("Internal source address is required")
            }
            try address.store(to: b)
        }
        func grams(_ value: BigUInt) throws {
            guard value.bitWidth <= 120 else { throw ErrorTonSdkSwift("Grams exceed 120 bits") }
            try b.storeVarUInt(value, 16)
        }
        switch self {
        case let .internalMessage(v):
            guard v.dest.isInternal else { throw ErrorTonSdkSwift("Internal destination address is required") }
            try b.storeBit(.b0).storeBit(v.ihrDisabled ? .b1 : .b0)
                .storeBit(v.bounce ? .b1 : .b0).storeBit(v.bounced ? .b1 : .b0)
            try internalSource(v.src)
            try v.dest.store(to: b)
            try b.storeSlice(v.value.cell().parse())
            try grams(v.ihrFee); try grams(v.fwdFee)
            try b.storeUInt(BigUInt(v.createdLt), 64).storeUInt(BigUInt(v.createdAt), 32)
        case let .externalInbound(v):
            guard v.src.isExternal && v.dest.isInternal else { throw ErrorTonSdkSwift("Invalid inbound address types") }
            try b.storeUInt(2, 2)
            try v.src.store(to: b); try v.dest.store(to: b); try grams(v.importFee)
        case let .externalOutbound(v):
            guard v.dest.isExternal else { throw ErrorTonSdkSwift("External destination address is required") }
            try b.storeUInt(3, 2)
            try internalSource(v.src); try v.dest.store(to: b)
            try b.storeUInt(BigUInt(v.createdLt), 64).storeUInt(BigUInt(v.createdAt), 32)
        }
        return try b.cell()
    }

    public static func parse(cs: CellSlice, relaxed: Bool = false) throws -> Self {
        let result: Self
        if try cs.loadBit() == .b0 {
            let ihrDisabled = try cs.loadBit() == .b1
            let bounce = try cs.loadBit() == .b1
            let bounced = try cs.loadBit() == .b1
            let src = try MessageAddress.parse(cs: cs), dest = try MessageAddress.parse(cs: cs)
            let value = try CurrencyCollection.parse(cs: cs)
            let ihrFee = try cs.loadVarBigUInt(length: 16), fwdFee = try cs.loadVarBigUInt(length: 16)
            let lt = UInt64(try cs.loadBigUInt(size: 64)), at = UInt32(try cs.loadBigUInt(size: 32))
            result = .internalMessage(.init(ihrDisabled: ihrDisabled, bounce: bounce, bounced: bounced,
                src: src, dest: dest, value: value, ihrFee: ihrFee, fwdFee: fwdFee, createdLt: lt, createdAt: at))
        } else if try cs.loadBit() == .b0 {
            result = try .externalInbound(.init(src: MessageAddress.parse(cs: cs), dest: MessageAddress.parse(cs: cs),
                                                importFee: cs.loadVarBigUInt(length: 16)))
        } else {
            result = try .externalOutbound(.init(src: MessageAddress.parse(cs: cs), dest: MessageAddress.parse(cs: cs),
                createdLt: UInt64(cs.loadBigUInt(size: 64)), createdAt: UInt32(cs.loadBigUInt(size: 32))))
        }
        // Reuse the writer's schema validation; no field is dropped or coerced.
        _ = try result.cell(relaxed: relaxed)
        return result
    }
}
