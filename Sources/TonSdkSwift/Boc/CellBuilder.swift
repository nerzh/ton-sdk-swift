//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 02.02.2024.
//

import Foundation
import BigInt


open class CellBuilder {
    public var size: Int
    public var refs: [Cell]
    public var bits: [Bit]

    public func bytes() throws -> Data {
        try bits.toBytes()
    }

    public var remainder: Int {
        size - bits.count
    }

    public init(size: Int = 1023) {
        self.size = size
        self.refs = []
        self.bits = .init()
    }

    @discardableResult
    public func storeSlice(_ slice: CellSlice) throws -> Self {
        let bits = slice.bits
        let refs = slice.refs

        try checkBitsOverflow(bits.count)
        try checkRefsOverflow(refs.count)
        try storeBits(bits)

        try refs.forEach { ref in
            try storeRef(ref)
        }

        return self
    }

    @discardableResult
    public func storeRef(_ ref: Cell) throws -> Self {
        try checkRefsOverflow(1)
        refs.append(ref)

        return self
    }

    @discardableResult
    public func storeMaybeRef(_ ref: Cell? = nil) throws -> Self {
        guard let ref = ref else {
            try storeBit(.b0)
            return self
        }
        try storeBit(.b1)
        return try storeRef(ref)
    }

    @discardableResult
    public func storeRefs(_ refs: [Cell]) throws -> Self {
        try checkRefsOverflow(refs.count)
        self.refs.append(contentsOf: refs)

        return self
    }

    @discardableResult
    public func storeBit(_ bit: Bit) throws -> Self {
        try checkBitsOverflow(1)
        bits.append(bit)

        return self
    }

    @discardableResult
    public func storeBits(_ bits: [Bit]) throws -> Self {
        try checkBitsOverflow(bits.count)
        self.bits.append(contentsOf: bits)

        return self
    }

    @discardableResult
    public func storeInt(_ value: BigInt, _ size: Int) throws -> Self {
        let intBits = BigInt(1) << (size - 1)

        guard value >= -intBits && value < intBits else {
            throw ErrorTonSdkSwift("Builder: can't store an Int, because its value allocates more space than provided.")
        }
        return try storeNumber(value, size)
    }

    @discardableResult
    public func storeUInt(_ value: BigUInt, _ size: Int) throws -> Self {
        if value >= (BigUInt(1) << size) {
            throw ErrorTonSdkSwift("Builder: can't store an UInt, because its value allocates more space than provided.")
        }
        return try storeNumber(value, size)
    }

    @discardableResult
    public func storeVarInt(_ value: BigInt, _ length: Int) throws -> Self {
        let size = Int(ceil(log2(Double(length))))
        let sizeBytes = Int(ceil(Double(String(value, radix: 2).count) / 8))
        let sizeBits = sizeBytes * 8
        let intBits = 1 << (sizeBits - 1)

        guard value >= -intBits && value < intBits else {
            throw ErrorTonSdkSwift("Builder: can't store an VarInt, because its value allocates more space than provided.")
        }

        try checkBitsOverflow(size + sizeBits)

        if value == 0 {
            try storeUInt(0, size)
        } else {
            try storeUInt(BigUInt(sizeBytes), size).storeInt(value, sizeBits)
        }

        return self
    }

    @discardableResult
    public func storeVarUInt(_ value: BigUInt, _ length: Int) throws -> Self {
        let size = Int(ceil(log2(Double(length))))
        let sizeBytes = Int(ceil(Double(String(value, radix: 2).count) / 8))
        let sizeBits = sizeBytes * 8
        
        guard value < (1 << sizeBits) else {
            throw ErrorTonSdkSwift("Builder: can't store an VarUInt, because its value allocates more space than provided.")
        }

        try checkBitsOverflow(size + sizeBits)

        if value == 0 {
            try storeUInt(0, size)
        } else {
            try storeUInt(BigUInt(sizeBytes), size).storeUInt(value, sizeBits)
        }

        return self
    }

    @discardableResult
    public func storeBytes(_ value: Data) throws -> Self {
        try checkBitsOverflow(value.count * 8)
        try value.forEach { byte in
            try storeUInt(BigUInt(Int(byte)), 8)
        }

        return self
    }

    @discardableResult
    public func storeString(_ value: String) throws -> Self {
        guard let data = value.data(using: .utf8) else {
            throw ErrorTonSdkSwift("Convert string \(value) to data failed")
        }
        return try storeBytes(data)
    }

    @discardableResult
    public func storeAddress(_ address: Address? = nil) throws -> Self {
        guard let address else {
            try storeBits(.init([0, 0]))
            return self
        }
        
        let anycast = 0
        let addressBitsSize = 2 + 1 + 8 + 256
        
        try checkBitsOverflow(addressBitsSize)
        try storeBits(.init([1, 0]))
        try storeUInt(BigUInt(anycast), 1)
        try storeInt(BigInt(address.workchain), 8)
        try storeBytes(address.hash)

        return self
    }

    @discardableResult
    public func storeCoins(_ coins: Coins) throws -> Self {
        if coins.nanoValue < 0 {
            throw ErrorTonSdkSwift("Builder: coins value can't be negative.")
        }
        
        try storeVarUInt(BigUInt(coins.nanoValue), 16)

        return self
    }

    @discardableResult
    public func storeDict(_ hashmap: Cell? = nil) throws -> Self {
        guard let hashmap = hashmap else {
            try storeBit(.b0)
            return self
        }

        let slice = hashmap.parse()
        try storeSlice(slice)

        return self
    }
    
    public func clone() throws -> CellBuilder {
        let data = CellBuilder(size: size)
        try data.storeBits(bits)
        try refs.forEach { ref in
            try data.storeRef(ref)
        }

        return data
    }

    public func cell(_ type: Cell.CellType = .ordinary) throws -> Cell {
        try Cell(bits: bits, refs: refs, type: type)
    }

    private func checkBitsOverflow(_ size: Int) throws {
        if size > remainder {
            throw ErrorTonSdkSwift("Builder: bits overflow. Can't add \(size) bits. Only \(remainder) bits left.")
        }
    }

    private func checkRefsOverflow(_ size: Int) throws {
        guard size <= (4 - refs.count) else {
            throw ErrorTonSdkSwift("Builder: refs overflow. Can't add \(size) refs. Only \(4 - refs.count) refs left.")
        }
    }
    
    @discardableResult
    private func storeNumber(_ value: BigUInt, _ size: Int) throws -> Self {
        let bits = (0..<size).map { i in
            ((value >> i) & 1) == 1 ? 1 : 0
        }.reversed()
        
        try storeBits([Bit](bits.map { UInt8($0) }))
        
        return self
    }
    
    @discardableResult
    private func storeNumber(_ value: BigInt, _ size: Int) throws -> Self {
        let bits = (0..<size).map { i in
            ((value >> i) & 1) == 1 ? 1 : 0
        }.reversed()
        try storeBits([Bit](bits.map { UInt8($0) }))
        
        return self
    }
}
