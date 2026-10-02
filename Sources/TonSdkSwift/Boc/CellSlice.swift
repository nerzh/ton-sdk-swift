//
//  File.swift
//
//
//  Created by Oleh Hudeichuk on 03.02.2024.
//

import Foundation
import BigInt

open class CellSlice: Equatable {
    open var bits: [Bit]
    open var refs: [Cell]
    public let sourceCell: Cell?
    public let initialBitCount: Int
    public let initialRefCount: Int
    open var consumedRefs: Int { initialRefCount - refs.count }
    open var consumedBits: Int { initialBitCount - bits.count }

    public init(bits: [Bit], refs: [Cell], sourceCell: Cell? = nil) {
        self.bits = bits
        self.refs = refs
        self.sourceCell = sourceCell
        self.initialBitCount = bits.count
        self.initialRefCount = refs.count
    }
    
    public static func == (lhs: CellSlice, rhs: CellSlice) -> Bool {
        lhs.bits == rhs.bits &&
        lhs.refs == rhs.refs
    }
    
    @discardableResult
    public func skipBits(size: Int) throws -> Self {
        if size < 0 || bits.count < size {
            throw ErrorTonSdkSwift("Slice: bits underflow.")
        }
        
        bits.removeFirst(size)
        return self
    }
    
    public func skipRefs(size: Int) throws -> Self {
        if size < 0 || refs.count < size {
            throw ErrorTonSdkSwift("Slice: refs underflow.")
        }
        
        refs.removeFirst(size)
        return self
    }
    
    public func skipDict() throws -> Self {
        let present = try preloadBit() == .b1
        if present { _ = try preloadRef() }
        try skipBits(size: 1)
        return present ? try skipRefs(size: 1) : self
    }
    
    @discardableResult
    public func skip(size: Int) throws -> Self {
        try skipBits(size: size)
    }
    
    open func loadRef() throws -> Cell {
        if refs.isEmpty {
            throw ErrorTonSdkSwift("Slice: refs underflow.")
        }
        
        return refs.removeFirst()
    }
    
    open func preloadRef() throws -> Cell {
        if refs.isEmpty {
            throw ErrorTonSdkSwift("Slice: refs underflow.")
        }
        
        return refs[0]
    }
    
    public func loadMaybeRef() throws -> Cell? {
        try loadBit().rawValue == 1 ? try loadRef() : nil
    }
    
    public func preloadMaybeRef() throws -> Cell? {
        try preloadBit().rawValue == 1 ? try preloadRef() : nil
    }
    
    public func loadBit() throws -> Bit {
        if bits.isEmpty {
            throw ErrorTonSdkSwift("Slice: bits underflow.")
        }
        
        return bits.removeFirst()
    }
    
    public func preloadBit() throws -> Bit {
        if bits.isEmpty {
            throw ErrorTonSdkSwift("Slice: bits underflow.")
        }
        
        return bits[0]
    }
    
    public func loadBits(size: Int) throws -> [Bit] {
        if size < 0 || bits.count < size {
            throw ErrorTonSdkSwift("Slice: bits underflow.")
        }
        
        return bits.shift(size)
    }
    
    public func preloadBits(size: Int) throws -> [Bit] {
        if size < 0 || bits.count < size {
            throw ErrorTonSdkSwift("Slice: bits underflow.")
        }
        var copyBits = bits
        return copyBits.shift(size)
    }
    
    public func loadBigInt(size: Int) throws -> BigInt {
        let bits = try loadBits(size: size)
        return bits.toBigInt()
    }
    
    public func preloadBigInt(size: Int) throws -> BigInt {
        let bits = try preloadBits(size: size)
        return bits.toBigInt()
    }
    
    public func loadBigUInt(size: Int) throws -> BigUInt {
        let bits = try loadBits(size: size)
        return bits.toBigUInt()
    }
    
    public func preloadBigUInt(size: Int) throws -> BigUInt {
        let bits = try preloadBits(size: size)
        return bits.toBigUInt()
    }
    
    public func loadVarBigInt(length: Int) throws -> BigInt {
        let size = Int(ceil(log2(Double(length))))
        let sizeBytes = try preloadBigUInt(size: size)
        let sizeBits = sizeBytes * 8
        
        if bits.count < sizeBits + BigUInt(size) {
            throw ErrorTonSdkSwift("Slice: can't perform loadVarBigInt – not enough bits")
        }
        
        let bits = try loadBits(size: Int(sizeBits))
        return bits.toBigInt()
    }
    
    public func preloadVarBigInt(length: Int) throws -> BigInt {
        let size = Int(ceil(log2(Double(length))))
        let sizeBytes = try preloadBigUInt(size: size)
        let sizeBits = sizeBytes * 8
        let bits = try preloadBits(size: size + Int(sizeBits))[size...]
        
        return [Bit](bits).toBigInt()
    }
    
    public func loadVarBigUInt(length: Int) throws -> BigUInt {
        let size = Int(ceil(log2(Double(length))))
        let sizeBytes = try preloadBigUInt(size: size)
        let sizeBits = sizeBytes * 8
        
        if bits.count < sizeBits + BigUInt(size) {
            throw ErrorTonSdkSwift("Slice: can't perform loadVarBigUint – not enough bits")
        }
        
        try skip(size: Int(size))
        let bits = try loadBits(size: Int(sizeBits))
        
        
        return bits.toBigUInt()
    }
    
    public func preloadVarBigUint(length: Int) throws -> BigUInt {
        let size = Int(ceil(log2(Double(length))))
        let sizeBytes = try preloadBigUInt(size: size)
        let sizeBits = sizeBytes * 8
        let bits = try preloadBits(size: size + Int(sizeBits))[size...]
        
        return [Bit](bits).toBigUInt()
    }
    
    public func loadBytes(size: Int) throws -> Data {
        guard size >= 0, size <= bits.count / 8 else { throw ErrorTonSdkSwift("Slice: bytes underflow.") }
        let bits = try loadBits(size: size * 8)
        return try bits.toBytes()
    }
    
    public func preloadBytes(size: Int) throws -> Data {
        guard size >= 0, size <= bits.count / 8 else { throw ErrorTonSdkSwift("Slice: bytes underflow.") }
        let bits = try preloadBits(size: size * 8)
        return try bits.toBytes()
    }
    
    public func loadString(size: Int? = nil) throws -> String {
        let bytes = size == nil ? try loadBytes(size: bits.count / 8) : try loadBytes(size: size!)
        guard let result = String(data: bytes, encoding: .utf8) else {
            throw ErrorTonSdkSwift("Slice: can't convert loadString")
        }
        return result
    }
    
    public func preloadString(size: Int? = nil) throws -> String {
        let bytes = size == nil ? try preloadBytes(size: bits.count / 8) : try preloadBytes(size: size!)
        guard let result = String(data: bytes, encoding: .utf8) else {
            throw ErrorTonSdkSwift("Slice: can't convert preloadString")
        }
        return result
    }
    
    public func loadSlice(size: Int = 0) throws -> CellSlice {
        let bits = try loadBits(size: size)
        return CellSlice(bits: bits, refs: [])
    }
    
    public func preloadSlice(size: Int = 0) throws -> CellSlice {
        let bits = try preloadBits(size: size)
        return CellSlice(bits: bits, refs: [])
    }
    
    public func loadAddress() throws -> Address? {
        let flagAddressNo: [Bit] = .init([0, 0])
        let flagAddress: [Bit] = .init([1, 0])
        let flag = try preloadBits(size: 2)
        
        if flag == flagAddressNo {
            try skipBits(size: 2)
            return nil
        } else if flag == flagAddress {
            // 2 bits flag, 1 bit anycast, 8 bits workchain, 256 bits address hash
            let size = 2 + 1 + 8 + 256
            // Slice 2 because we don't need flag bits
            var bits = try loadBits(size: size)[2...]
            // Anycast is currently unused
            _ = bits.popFirst()
            
            let workchain = [Bit](bits[3..<3+8]).toBigInt()
            let hash = try [Bit](bits[3+8..<3+8+256]).toHex()
            let raw = "\(workchain):\(hash)"
            
            return try Address(address: raw)
        } else {
            throw ErrorTonSdkSwift("Slice: bad address flag bits.")
        }
    }
    
    public func preloadAddress() throws -> Address? {
        let flagAddressNo: [Bit] = .init([0, 0])
        let flagAddress: [Bit] = .init([1, 0])
        let flag = try preloadBits(size: 2)
        
        if flag == flagAddressNo {
            return nil
        } else if flag == flagAddress {
            // 2 bits flag, 1 bit anycast, 8 bits workchain, 256 bits address hash
            let size = 2 + 1 + 8 + 256
            var bits = try preloadBits(size: size)[2...]
            // Splice 2 because we don't need flag bits
            
            // Anycast is currently unused
            _ = bits.popFirst()
            
            let workchain = [Bit](bits[..<8]).toBigInt()
            let hash = try [Bit](bits[8..<264]).toHex()
            let raw = "\(workchain):\(hash)"
            
            return try Address(address: raw)
        } else {
            throw ErrorTonSdkSwift("Slice: bad address flag bits.")
        }
    }
    
    public func loadCoins(decimals: Int = 9) throws -> Coins {
        let coins = try loadVarBigUInt(length: 16)
        return .init(nanoValue: coins, decimals: decimals)
    }
    
    public func preloadCoins(decimals: Int = 9) throws -> Coins {
        let coins = try preloadVarBigUint(length: 16)
        return .init(nanoValue: coins, decimals: decimals)
    }
    
    public func loadDict<K,V>(keySize: Int, options: HashmapOptions<K,V>? = nil) throws -> HashmapE<K,V> {
        try HashmapE.parse(keySize: keySize, slice: self, options: options)
    }
    
    public func preloadDict<K,V>(keySize: Int, options: HashmapOptions<K,V>? = nil) throws -> HashmapE<K,V> {
        let cursor = CellSlice(bits: bits, refs: refs, sourceCell: sourceCell)
        return try HashmapE.parse(keySize: keySize, slice: cursor, options: options)
    }
    
    public func loadUnaryLength() throws -> Int {
        var res: Int = 0
        while try self.loadBit() == .b1 {
            res += 1
        }
        return res
    }
    
    public func preloadUnaryLength() throws -> Int {
        guard let terminator = bits.firstIndex(of: .b0) else {
            throw ErrorTonSdkSwift("Slice: unterminated unary length.")
        }
        return terminator
    }
    
    public static func parse(cell: Cell) -> CellSlice {
        cell.parse()
    }
}
