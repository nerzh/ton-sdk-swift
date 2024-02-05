//
//  File.swift
//
//
//  Created by Oleh Hudeichuk on 03.02.2024.
//

import Foundation
import BigInt

public struct CellSlice {
    public var bits: Bits
    public var refs: [Cell]
    
    public init(bits: Bits, refs: [Cell]) {
        self.bits = bits
        self.refs = refs
    }
    
    @discardableResult
    public mutating func skipBits(size: Int) throws -> Self {
        if bits.count < size {
            throw ErrorTonSdkSwift("Slice: bits overflow.")
        }
        
        bits.removeFirst(size)
        return self
    }
    
    public mutating func skipRefs(size: Int) throws -> Self {
        if refs.count < size {
            throw ErrorTonSdkSwift("Slice: refs overflow.")
        }
        
        refs.removeFirst(size)
        return self
    }
    
    public mutating func skipDict() throws -> Self {
        let isEmpty = try loadBit().rawValue == 0
        return isEmpty ? try skipRefs(size: 1) : self
    }
    
    public mutating func loadRef() throws -> Cell {
        if refs.isEmpty {
            throw ErrorTonSdkSwift("Slice: refs overflow.")
        }
        
        return refs.removeFirst()
    }
    
    public func preloadRef() throws -> Cell {
        if refs.isEmpty {
            throw ErrorTonSdkSwift("Slice: refs overflow.")
        }
        
        return refs[0]
    }
    
    public mutating func loadMaybeRef() throws -> Cell? {
        try loadBit().rawValue == 1 ? try loadRef() : nil
    }
    
    public func preloadMaybeRef() throws -> Cell? {
        try preloadBit().rawValue == 1 ? try preloadRef() : nil
    }
    
    public mutating func loadBit() throws -> Bits.Bit {
        if bits.isEmpty {
            throw ErrorTonSdkSwift("Slice: bits overflow.")
        }
        
        return bits.removeFirst()
    }
    
    public func preloadBit() throws -> Bits.Bit {
        if bits.isEmpty {
            throw ErrorTonSdkSwift("Slice: bits overflow.")
        }
        
        return bits[0]
    }
    
    public mutating func loadBits(size: Int) throws -> Bits {
        if size < 0 || bits.count < size {
            throw ErrorTonSdkSwift("Slice: bits overflow.")
        }
        
        return bits.shift(size)
    }
    
    public func preloadBits(size: Int) throws -> Bits {
        if size < 0 || bits.count < size {
            throw ErrorTonSdkSwift("Slice: bits overflow.")
        }
        var copyBits = bits
        return copyBits.shift(size)
    }
    
    public mutating func loadBigInt(size: Int) throws -> BigInt {
        let bits = try loadBits(size: size)
        return bits.toBigInt()
    }
    
    public func preloadBigInt(size: Int) throws -> BigInt {
        let bits = try preloadBits(size: size)
        return bits.toBigInt()
    }
    
    public mutating func loadBigUInt(size: Int) throws -> BigUInt {
        let bits = try loadBits(size: size)
        return bits.toBigUInt()
    }
    
    public func preloadBigUInt(size: Int) throws -> BigUInt {
        let bits = try preloadBits(size: size)
        return bits.toBigUInt()
    }
    
    public mutating func loadVarBigInt(length: Int) throws -> BigInt {
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
        
        return Bits(bits).toBigInt()
    }
    
    public mutating func loadVarBigUInt(length: Int) throws -> BigUInt {
        let size = Int(ceil(log2(Double(length))))
        let sizeBytes = try preloadBigUInt(size: size)
        let sizeBits = sizeBytes * 8
        
        if bits.count < sizeBits + BigUInt(size) {
            throw ErrorTonSdkSwift("Slice: can't perform loadVarBigUint – not enough bits")
        }
        
        let bits = try loadBits(size: Int(sizeBits))
        return bits.toBigUInt()
    }
    
    public func preloadVarBigUint(length: Int) throws -> BigUInt {
        let size = Int(ceil(log2(Double(length))))
        let sizeBytes = try preloadBigUInt(size: size)
        let sizeBits = sizeBytes * 8
        let bits = try preloadBits(size: size + Int(sizeBits))[size...]
        
        return Bits(bits).toBigUInt()
    }
    
    public mutating func loadBytes(size: Int) throws -> Data {
        let bits = try loadBits(size: size * 8)
        return try bits.toBytes()
    }
    
    public func preloadBytes(size: Int) throws -> Data {
        let bits = try preloadBits(size: size * 8)
        return try bits.toBytes()
    }
    
    public mutating func loadString(size: Int? = nil) throws -> String {
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
    
    public mutating func loadAddress() throws -> Address? {
        let flagAddressNo: Bits = .init([0, 0])
        let flagAddress: Bits = .init([1, 0])
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
            
            let workchain = Bits(bits[..<8]).toBigInt()
            let hash = try Bits(bits[8..<264]).toHex()
            let raw = "\(workchain):\(hash)"
            
            return try Address(address: raw)
        } else {
            throw ErrorTonSdkSwift("Slice: bad address flag bits.")
        }
    }
    
    public func preloadAddress() throws -> Address? {
        let flagAddressNo: Bits = .init([0, 0])
        let flagAddress: Bits = .init([1, 0])
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
            
            let workchain = Bits(bits[..<8]).toBigInt()
            let hash = try Bits(bits[8..<264]).toHex()
            let raw = "\(workchain):\(hash)"
            
            return try Address(address: raw)
        } else {
            throw ErrorTonSdkSwift("Slice: bad address flag bits.")
        }
    }
    
    public mutating func loadCoins(decimals: Int = 9) throws -> Coins {
        let coins = try loadVarBigUInt(length: 16)
        return .init(nanoValue: coins, decimals: decimals)
    }
    
    public func preloadCoins(decimals: Int = 9) throws -> Coins {
        let coins = try preloadVarBigUint(length: 16)
        return .init(nanoValue: coins, decimals: decimals)
    }
    #warning("AFTER HASHMAP_E")
//    func loadDict(keySize: Int, options: [String: Any] = [:]) -> HashmapE {
//        let dictConstructor = loadBit()
//        let isEmpty = dictConstructor == 0
//        
//        if !isEmpty {
//            return HashmapE.parse(
//                keySize: keySize,
//                slice: Slice(bits: [dictConstructor], refs: [loadRef()]),
//                options: options
//            )
//        } else {
//            return HashmapE(keySize: keySize, options: options)
//        }
//    }
//    
//    func preloadDict(keySize: Int, options: [String: Any] = [:]) -> HashmapE {
//        let dictConstructor = preloadBit()
//        let isEmpty = dictConstructor == 0
//        
//        if !isEmpty {
//            return HashmapE.parse(
//                keySize: keySize,
//                slice: Slice(bits: [dictConstructor], refs: [preloadRef()]),
//                options: options
//            )
//        } else {
//            return HashmapE(keySize: keySize, options: options)
//        }
//    }
    
    public static func parse(cell: Cell) -> Self {
        .init(bits: cell.bits, refs: cell.refs)
    }
}
