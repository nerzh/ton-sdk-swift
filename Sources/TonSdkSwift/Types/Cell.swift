//
//  File.swift
//
//
//  Created by Oleh Hudeichuk on 02.02.2024.
//

import Foundation
import BigInt
import SwiftExtensionsPack

public enum CellType: Int8, Cases {
    case ordinary = -1
    case prunedBranch = 1
    case libraryReference = 2
    case merkleProof = 3
    case merkleUpdate = 4
    case big = 5
}

/// Selects consensus-sensitive rules. TON remains the default.
public enum CellCompatibility: Sendable {
    case ton
    /// Compatibility with the audited ever_block 1.11.22 snapshot, not all Everscale versions.
    case everscale

    public var maximumDepth: UInt32 { self == .ton ? 1024 : 65534 }
}

open class Cell: Equatable {
    public static let HASH_BITS: UInt32 = 256
    public static let DEPTH_BITS: UInt32 = 16
    
    public let compatibility: CellCompatibility
    internal private(set) var hasTONSpecificHashes = false
    private var wrappedCell: Cell?
    open var isVirtualized: Bool { wrappedCell?.isVirtualized ?? false }

    private var _bits: [Bit]
    private var _bigData: Data?
    open var bigData: Data? {
        if let wrappedCell { return wrappedCell.bigData }
        return _bigData
    }
    public var bitLength: Int { wrappedCell?.bitLength ?? (_bigData.map { $0.count * 8 } ?? _bits.count) }
    open var bits: [Bit] { wrappedCell?.bits ?? (_bigData?.toBits() ?? _bits) }
    private var _refs: [Cell]
    open var refs: [Cell] { wrappedCell?.refs ?? _refs }
    private var _type: CellType
    open var type: CellType { wrappedCell?.type ?? _type }
    private var _mask: Mask
    open var mask: Mask { wrappedCell?.mask ?? _mask }
    private var _hashes: [String]
    open var hashes: [String] { wrappedCell?.hashes ?? _hashes }
    private var _depths: [BigUInt]
    open var depths: [BigUInt] { wrappedCell?.depths ?? _depths }
    public var isExotic: Bool {
        type != .ordinary
    }

    /// Delegates to an existing cell without rebuilding its storage or losing view semantics.
    public init(wrapping cell: Cell) {
        wrappedCell = cell
        compatibility = cell.compatibility
        hasTONSpecificHashes = cell.hasTONSpecificHashes
        _bits = cell._bits
        _bigData = cell._bigData
        _refs = cell._refs
        _type = cell._type
        _mask = cell._mask
        _hashes = cell._hashes
        _depths = cell._depths
    }

    /// EverBlock big cells are byte aligned leaves hashed directly from their payload.
    public init(bigData: Data) throws {
        compatibility = .everscale
        guard bigData.count <= 0xff_ffff else { throw ErrorTonSdkSwift("Big cell data exceeds 16777215 bytes") }
        _bits = []
        _bigData = bigData
        _refs = []
        _type = .big
        _mask = Mask(maskValue: 0)
        _hashes = [try bigData.sha256()]
        _depths = [0]
    }

    public init(bits: [Bit] = .init(), refs: [Cell] = .init(), type: CellType = .ordinary,
                checkMerkleMetadata: Bool = true, compatibility: CellCompatibility = .ton) throws {
        self.compatibility = compatibility
        guard type != .big || compatibility == .everscale else { throw ErrorTonSdkSwift("Big cells require Everscale compatibility") }
        guard compatibility != .ton || refs.allSatisfy({ $0.compatibility == .ton }) else { throw ErrorTonSdkSwift("TON cells cannot contain Everscale cells") }
        guard compatibility != .everscale || !refs.contains(where: { $0.hasTONSpecificHashes }) else { throw ErrorTonSdkSwift("Everscale cells cannot contain TON-specific gapped hashes") }
        let mapper = Self.getMapper(type: type, compatibility: compatibility)
        let validate = mapper.validate
        let mask = mapper.mask
        
        if !checkMerkleMetadata && type == .merkleProof {
            try Self.validateMerkleProof(bits: bits, refs: refs, checkMetadata: false)
        } else if !checkMerkleMetadata && type == .merkleUpdate {
            try Self.validateMerkleUpdate(bits: bits, refs: refs, checkMetadata: false)
        } else {
            try validate(bits, refs)
        }
        self._mask = mask(bits, refs)
        self.hasTONSpecificHashes = refs.contains(where: { $0.hasTONSpecificHashes })
            || (compatibility == .ton && type != .prunedBranch && [UInt32(2), 4, 5, 6].contains(self._mask.value))
        self._bits = bits
        self._bigData = type == .big ? try bits.toBytes() : nil
        self._refs = refs
        self._type = type
        self._depths = []
        self._hashes = []
        
        if type == .big {
            _hashes = [try _bigData!.sha256()]
            _depths = [0]
        } else { try initialize() }
    }
    
    private func initialize() throws {
        let hasRefs = refs.count > 0
        let isMerkle = [CellType.merkleProof, CellType.merkleUpdate].contains(type)
        let isPrunedBranch = type == CellType.prunedBranch
        let hashIndexOffset = isPrunedBranch ? mask.hashCount - 1 : 0

        var hashIndex: UInt32 = 0
        
        for levelIndex in 0...mask.level {
            if !mask.isSignificant(level: levelIndex) { continue }
            if hashIndex < hashIndexOffset { hashIndex += 1; continue }

            if (hashIndex == hashIndexOffset && levelIndex != 0 && !isPrunedBranch) ||
               (hashIndex != hashIndexOffset && levelIndex == 0 && isPrunedBranch)
            {
                throw ErrorTonSdkSwift("Can't deserialize cell")
            }
            
            let refLevel = levelIndex + (isMerkle ? 1 : 0)
            // TON uses the applied mask; the audited Everscale snapshot fills gaps.
            let descriptorMask = compatibility == .everscale && !isPrunedBranch
                ? Mask(maskValue: (1 << levelIndex) - 1) : mask.apply(level: levelIndex)
            let refsDescriptor = getRefsDescriptor(descriptorMask)
            let bitsDescriptor = getBitsDescriptor()
            let data: [Bit]

            if hashIndex != hashIndexOffset {
                data = hashes[Int(hashIndex) - Int(hashIndexOffset) - 1].hexToBits()
            } else {
                data = getAugmentedBits()
            }

            var depthRepresentation: [Bit] = .init()
            var hashRepresentation: [Bit] = .init()
            var depth: BigUInt = 0

            for ref in refs {
                let refDepth = ref.depth(refLevel)
                guard refDepth < compatibility.maximumDepth else { throw ErrorTonSdkSwift("Referenced cell exceeds construction depth") }
                let refHash = try ref.hash(refLevel)
                depthRepresentation += Cell.getDepthDescriptor(UInt32(refDepth))
                hashRepresentation += refHash.hexToBits()
                depth = max(depth, refDepth)
            }
            
            let representation: [Bit] = refsDescriptor + bitsDescriptor + data + depthRepresentation + hashRepresentation
            
            if refs.count > 0 && depth >= compatibility.maximumDepth {
                throw ErrorTonSdkSwift("Cell exceeds maximum construction depth \(compatibility.maximumDepth)")
            }

            let dest = Int(hashIndex - hashIndexOffset)
            let newDepth = depth + (hasRefs ? 1 : 0)
            
            let newHash: String = try representation.toBytes().sha256()
            
            if _depths.count == dest {
                _depths.append(newDepth)
                _hashes.append(newHash)
            } else {
                if _depths.count > dest {
                    _depths[dest] = newDepth
                    _hashes[dest] = newHash
                } else {
                    let diff = dest - _depths.count
                    for _ in 0..<diff {
                        _depths.append(0)
                        _hashes.append("*")
                    }
                    _depths.append(newDepth)
                    _hashes.append(newHash)
                }
            }
            
            hashIndex += 1
        }
        
        if _hashes.contains("*") { 
            throw ErrorTonSdkSwift("Code has problem with \"dest\" variable. Please write to support this library.")
        }
    }
    
    public static func == (lhs: Cell, rhs: Cell) -> Bool {
        guard let left = try? lhs.hash(), let right = try? rhs.hash() else { return false }
        return left.lowercased() == right.lowercased()
    }
    
    public static func validateOrdinary(bits: [Bit], refs: [Cell]) throws {
        let maxBitsCount: Int = 1023
        let maxRefsCount: Int = 4
        
        if bits.count > maxBitsCount {
            throw ErrorTonSdkSwift("Ordinary cell can't have more than \(maxBitsCount) bits, got \(bits.count)")
        }
        
        if refs.count > maxRefsCount {
            throw ErrorTonSdkSwift("Ordinary cell can't have more than \(maxRefsCount) refs, got \(refs.count)")
        }
    }
    
    public static func validatePrunedBranch(bits: [Bit], refs: [Cell], compatibility: CellCompatibility = .ton) throws {
        let minSize = 8 + 8 + (1 * (HASH_BITS + DEPTH_BITS))

        if bits.count < minSize {
            throw ErrorTonSdkSwift("Pruned Branch cell can't have less than (8 + 8 + 256 + 16) bits, got \(bits.count)")
        }

        if !refs.isEmpty {
            throw ErrorTonSdkSwift("Pruned Branch cell can't have refs, got \(refs.count)")
        }

        let type = Int8([Bit](bits[0..<8]).toBigInt())
        
        if type != CellType.prunedBranch.rawValue {
            throw ErrorTonSdkSwift("Pruned Branch cell type must be exactly \(CellType.prunedBranch), got \(type)")
        }

        let mask = Mask(maskValue: UInt32([Bit](bits[8..<16]).toBigUInt()))

        if mask.level < 1 || mask.level > 3 {
            throw ErrorTonSdkSwift("Pruned Branch cell level must be >= 1 and <= 3, got \(mask.level)")
        }

        let hashCount = mask.apply(level: mask.level - 1).hashCount
        let size = 8 + 8 + (hashCount * (HASH_BITS + DEPTH_BITS))
        
        if bits.count != size {
            throw ErrorTonSdkSwift("Pruned Branch cell with level \(mask.level) must have exactly \(size) bits, got \(bits.count)")
        }
        for index in 0..<Int(hashCount) {
            let start = 16 + Int(hashCount) * 256 + index * 16
            guard Array(bits[start..<start + 16]).toBigUInt() <= compatibility.maximumDepth else {
                throw ErrorTonSdkSwift("Pruned Branch exceeds maximum depth \(compatibility.maximumDepth)")
            }
        }
    }
    
    public static func validateLibraryReference(bits: [Bit], refs: [Cell]) throws {
        // Type + hash
        let size = 8 + HASH_BITS

        if bits.count != size {
            throw ErrorTonSdkSwift("Library Reference cell must have exactly \(size) bits, got \(bits.count)")
        }

        if !refs.isEmpty {
            throw ErrorTonSdkSwift("Library Reference cell can't have refs, got \(refs.count)")
        }
        
        let type = Int8([Bit](bits[0..<8]).toBigInt())

        if type != CellType.libraryReference.rawValue {
            throw ErrorTonSdkSwift("Library Reference cell type must be exactly \(CellType.libraryReference), got \(type)")
        }
    }
    
    public static func validateMerkleProof(bits: [Bit], refs: [Cell], checkMetadata: Bool = true) throws {
        // Type + hash + depth
        let size = 8 + HASH_BITS + DEPTH_BITS

        if bits.count != size {
            throw ErrorTonSdkSwift("Merkle Proof cell must have exactly \(size) bits, got \(bits.count)")
        }

        guard refs.count == 1 else {
            throw ErrorTonSdkSwift("Merkle Proof cell must have exactly 1 ref, got \(refs.count)")
        }

        let type = Int8([Bit](bits[0..<8]).toBigInt())

        if type != CellType.merkleProof.rawValue {
            throw ErrorTonSdkSwift("Merkle Proof cell type must be exactly \(CellType.merkleProof), got \(type)")
        }

        guard checkMetadata else { return }
        let data = [Bit](bits[8...])
        let proofHash = try [Bit](Array(data[0..<Int(HASH_BITS)])).toHex()
        let proofDepth = [Bit](Array(data[Int(HASH_BITS)..<Int(HASH_BITS + DEPTH_BITS)])).toBigUInt()
        let refHash = try refs[0].hash(0)
        let refDepth = refs[0].depth(0)

        if proofHash.lowercased() != refHash.lowercased() {
            throw ErrorTonSdkSwift("Merkle Proof cell ref hash must be exactly \"\(proofHash)\", got \"\(refHash)\"")
        }

        if proofDepth != refDepth {
            throw ErrorTonSdkSwift("Merkle Proof cell ref depth must be exactly \"\(proofDepth)\", got \"\(refDepth)\"")
        }
    }
    
    public static func validateMerkleUpdate(bits: [Bit], refs: [Cell], checkMetadata: Bool = true) throws {
        let size = 8 + (2 * (256 + 16))
        
        if bits.count != size {
            throw ErrorTonSdkSwift("Merkle Update cell must have exactly \(size) bits, got \(bits.count)")
        }
        
        if refs.count != 2 {
            throw ErrorTonSdkSwift("Merkle Update cell must have exactly 2 refs, got \(refs.count)")
        }
        
        let type = [Bit](bits[0..<8]).toBigInt()
        
        if type != CellType.merkleUpdate.rawValue {
            throw ErrorTonSdkSwift("Merkle Update cell type must be exactly \(CellType.merkleUpdate), got \(type)")
        }
        
        guard checkMetadata else { return }
        let data = Array(bits[8...])
        let hashes = [
            try [Bit](data[0..<256]).toHex(),
            try [Bit](data[256..<512]).toHex()
        ]
        let depths = [
            [Bit](data[512..<528]).toBigUInt(),
            [Bit](data[528..<544]).toBigUInt()
        ]
        
        for (index, ref) in refs.enumerated() {
            let proofHash = hashes[index]
            let proofDepth = depths[index]
            let refHash = try ref.hash(0)
            let refDepth = ref.depth(0)

            if proofHash.lowercased() != refHash.lowercased() {
                throw ErrorTonSdkSwift("Merkle Update cell ref #\(index) hash must be exactly '\(proofHash)', got '\(refHash)'")
            }

            if proofDepth != refDepth {
                throw ErrorTonSdkSwift("Merkle Update cell ref #\(index) depth must be exactly '\(proofDepth)', got '\(refDepth)'")
            }
        }
    }
    
    public static func getMapper(type: CellType, compatibility: CellCompatibility = .ton) -> (validate: ([Bit], [Cell]) throws -> Void, mask: ([Bit], [Cell]) -> Mask) {
        return switch type {
        case .ordinary:
            (
                validate: Self.validateOrdinary,
                mask: { (bits: [Bit], refs: [Cell]) in
                    Mask(maskValue: refs.reduce(0) { acc, el in
                        acc | el.mask.value
                    })
                }
            )
        case .prunedBranch:
            (
                validate: { try Self.validatePrunedBranch(bits: $0, refs: $1, compatibility: compatibility) },
                mask: { (bits: [Bit], refs: [Cell]) in
                    Mask(maskValue: UInt32([Bit](bits[8..<16]).toBigUInt()))
                }
            )
        case .libraryReference:
            (
                validate: Self.validateLibraryReference,
                mask: { (bits: [Bit], refs: [Cell]) in
                    Mask(maskValue: 0)
                }
            )
        case .merkleProof:
            (
                validate: { try Self.validateMerkleProof(bits: $0, refs: $1) },
                mask: { (bits: [Bit], refs: [Cell]) in
                    Mask(maskValue: refs[0].mask.value >> 1)
                }
            )
        case .merkleUpdate:
            (
                validate: { try Self.validateMerkleUpdate(bits: $0, refs: $1) },
                mask: { (bits: [Bit], refs: [Cell]) in
                    Mask(maskValue: (refs[0].mask.value | refs[1].mask.value) >> 1)
                }
            )
        case .big:
            (
                validate: { bits, refs in
                    guard refs.isEmpty, bits.count % 8 == 0, bits.count / 8 <= 0xff_ffff else {
                        throw ErrorTonSdkSwift("Invalid big cell payload or references")
                    }
                },
                mask: { _, _ in Mask(maskValue: 0) }
            )
        }
    }

    public static func getDepthDescriptor(_ depth: UInt32) -> [Bit] {
        let descriptor = Data([UInt8(depth / 256), UInt8(depth % 256)])
        return descriptor.toBits()
    }
    
    public func toMerkleProof() throws -> Cell {
        try CellBuilder()
            .storeInt(BigInt(CellType.merkleProof.rawValue), 8)
            .storeBytes(self.hash(0).hexToBytes())
            .storeUInt(self.depth(0), 16)
            .storeRef(self)
            .cell(.merkleProof, compatibility: compatibility)
    }
    
    public func toPrunedBranch() throws -> Cell {
        try CellBuilder()
            .storeInt(BigInt(CellType.prunedBranch.rawValue), 8)
            .storeUInt(1, 8)
            .storeBytes(self.hash(0).hexToBytes())
            .storeUInt(self.depth(0), 16)
            .cell(.prunedBranch, compatibility: compatibility)
    }
    
    public static func toMerkleUpdate(c1: Cell, c2: Cell) throws -> Cell {
        try CellBuilder()
            .storeInt(BigInt(CellType.merkleUpdate.rawValue), 8)
            .storeBytes(c1.hash(0).hexToBytes())
            .storeBytes(c2.hash(0).hexToBytes())
            .storeUInt(c1.depth(0), 16)
            .storeUInt(c2.depth(0), 16)
            .storeRef(c1)
            .storeRef(c2)
            .cell(.merkleUpdate, compatibility: c1.compatibility)
    }

    public func getRefsDescriptor(_ mask: Mask? = nil) -> [Bit] {
        if type == .big { return Data([13]).toBits() }
        let value = UInt32(refs.count) +
            (isExotic ? 8 : 0) +
            ((mask != nil ? mask!.value : self.mask.value) * 32)
        
        let descriptor = Data([UInt8(value)])
        return descriptor.toBits()
    }

    public func getBitsDescriptor() -> [Bit] {
        if let data = bigData { return Data([UInt8(data.count >> 16), UInt8((data.count >> 8) & 255), UInt8(data.count & 255)]).toBits() }
        let value = Int(ceil(Double(bits.count) / 8.0)) + Int(floor(Double(bits.count) / 8.0))
        let descriptor = Data([UInt8(value)])
        return descriptor.toBits()
    }

    public func getAugmentedBits() -> [Bit] {
        type == .big ? bits : bits.augment()
    }

    open func hash(_ level: UInt32 = 3) throws -> String {
        if Swift.type(of: self) == Cell.self, let wrappedCell { return try wrappedCell.hash(level) }
        let level = min(level, 3)
        guard type != CellType.prunedBranch else {
            let hashIndex = mask.apply(level: level).hashIndex
            let thisHashIndex = mask.hashIndex
            let skip = 16 + hashIndex * Cell.HASH_BITS

            if hashIndex != thisHashIndex {
                return try [Bit](bits[Int(skip)..<Int(skip + Cell.HASH_BITS)]).toHex().lowercased()
            } else {
                return hashes[0]
            }
        }
        return hashes[Int(mask.apply(level: level).hashIndex)]
    }

    // Get cell's depth (max level by default)
    open func depth(_ level: UInt32 = 3) -> BigUInt {
        if Swift.type(of: self) == Cell.self, let wrappedCell { return wrappedCell.depth(level) }
        let level = min(level, 3)
        guard type != CellType.prunedBranch else {
            let hashIndex = mask.apply(level: level).hashIndex
            let thisHashIndex = mask.hashIndex
            let skip = 16 + thisHashIndex * Cell.HASH_BITS + hashIndex * Cell.DEPTH_BITS

            if hashIndex != thisHashIndex {
                return [Bit](bits[Int(skip)..<Int(skip + Cell.DEPTH_BITS)]).toBigUInt()
            } else {
                return depths[0]
            }
        }
        return depths[Int(mask.apply(level: level).hashIndex)]
    }

    // Get Slice from current instance
    open func parse() -> CellSlice {
        // A transparent base wrapper delegates the cursor, preserving tracking.
        // Subclasses may override bits/refs without overriding parse; honor those
        // dynamic views instead of silently reading their backing cell.
        if Swift.type(of: self) == Cell.self, let wrappedCell { return wrappedCell.parse() }
        return CellSlice(bits: bits, refs: refs, sourceCell: self)
    }

    open func reference(at index: Int) throws -> Cell {
        if Swift.type(of: self) == Cell.self, let wrappedCell { return try wrappedCell.reference(at: index) }
        guard refs.indices.contains(index) else { throw ErrorTonSdkSwift("Cell: refs underflow.") }
        return refs[index]
    }
    
    public func slice() -> CellSlice {
        parse()
    }

    // Print cell as fift-hex
    public func printCell(indent: Int = 1, size: Int = 0) throws -> String {
        #warning("TODO: fix this logic")
        let bitsCopy = bits
        let areDivisible = bitsCopy.count % 4 == 0
        let augmented = areDivisible ? bitsCopy : bitsCopy.augment(divider: 4)
        let fiftHex = "\(try augmented.toHex().uppercased())\(areDivisible ? "" : "_")}"
        var output = "\(String(repeating: " ", count: indent * size))x{\(fiftHex)\n"

        for ref in refs {
            output += try ref.printCell(indent: indent, size: size + 1)
        }

        return output
    }

    // Checks Cell equality by comparing cell hashes
    public func isEqual(_ cell: Cell) throws -> Bool {
        (try hash().lowercased()) == (try cell.hash().lowercased())
    }
    
    public func sign(secretKey32byte: Data) throws -> Data {
        let keys = SEPCrypto.Ed25519.createKeyPair(seed32Byte: secretKey32byte)
        let message = try self.hash().hexToBytes()
        let signature = SEPCrypto.Ed25519.sign(message: message, publicKey32byte: keys.public, secretKey64byte: keys.secret)
        return signature
    }
    
    public func toBoc(bocOptions: Boc.BOCOptions = .init()) throws -> Data {
        try Boc.serialize(root: [self], options: bocOptions)
    }
}
