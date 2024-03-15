//
//  File.swift
//
//
//  Created by Oleh Hudeichuk on 02.02.2024.
//

import Foundation
import BigInt


open class Cell: Equatable {
    public static let HASH_BITS: UInt32 = 256
    public static let DEPTH_BITS: UInt32 = 16
    
    public static func == (lhs: Cell, rhs: Cell) -> Bool {
        (try? lhs.hash()) == (try? rhs.hash())
    }
    
    public enum CellType: Int8 {
        case ordinary = -1
        case prunedBranch = 1
        case libraryReference = 2
        case merkleProof = 3
        case merkleUpdate = 4
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

    public static func validatePrunedBranch(bits: [Bit], refs: [Cell]) throws {
        let minSize = 8 + 8 + (1 * (HASH_BITS + DEPTH_BITS))

        if bits.count < minSize {
            throw ErrorTonSdkSwift("Pruned Branch cell can't have less than (8 + 8 + 256 + 16) bits, got \(bits.count)")
        }

        if !refs.isEmpty {
            throw ErrorTonSdkSwift("Pruned Branch cell can't have refs, got \(refs.count)")
        }

        let type = Int8([Bit](bits[0...8]).toBigInt())
        
        if type != CellType.prunedBranch.rawValue {
            throw ErrorTonSdkSwift("Pruned Branch cell type must be exactly \(CellType.prunedBranch), got \(type)")
        }

        let mask = Mask(maskValue: UInt32([Bit](bits[8...16]).toBigUInt()))

        if mask.level < 1 || mask.level > 3 {
            throw ErrorTonSdkSwift("Pruned Branch cell level must be >= 1 and <= 3, got \(mask.level)")
        }

        let hashCount = mask.apply(level: mask.level - 1).hashCount
        let size = 8 + 8 + (hashCount * (HASH_BITS + DEPTH_BITS))

        if bits.count != size {
            throw ErrorTonSdkSwift("Pruned Branch cell with level \(mask.level) must have exactly \(size) bits, got \(bits.count)")
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
    
    public static func validateMerkleProof(bits: [Bit], refs: [Cell]) throws {
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

        let data = [Bit](bits[8...])
        let proofHash = try [Bit](Array(data[0..<Int(HASH_BITS / 4)])).toHex()
        let proofDepth = [Bit](Array(data[Int(HASH_BITS / 4)..<Int(HASH_BITS / 4 + DEPTH_BITS)])).toBigUInt()
        let refHash = try refs[0].hash(0)
        let refDepth = refs[0].depth(0)

        if proofHash != refHash {
            throw ErrorTonSdkSwift("Merkle Proof cell ref hash must be exactly \"\(proofHash)\", got \"\(refHash)\"")
        }

        if proofDepth != refDepth {
            throw ErrorTonSdkSwift("Merkle Proof cell ref depth must be exactly \"\(proofDepth)\", got \"\(refDepth)\"")
        }
    }
    
    public static func validateMerkleUpdate(bits: [Bit], refs: [Cell]) throws {
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
        
        let data = bits[8...]
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

            if proofHash != refHash {
                throw ErrorTonSdkSwift("Merkle Update cell ref #\(index) hash must be exactly '\(proofHash)', got '\(refHash)'")
            }

            if proofDepth != refDepth {
                throw ErrorTonSdkSwift("Merkle Update cell ref #\(index) depth must be exactly '\(proofDepth)', got '\(refDepth)'")
            }
        }
    }
    
    public static func getMapper(type: Cell.CellType) -> (validate: ([Bit], [Cell]) throws -> Void, mask: ([Bit], [Cell]) -> Mask) {
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
                validate: Self.validatePrunedBranch,
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
                validate: Self.validateMerkleProof,
                mask: { (bits: [Bit], refs: [Cell]) in
                    Mask(maskValue: refs[0].mask.value >> 1)
                }
            )
        case .merkleUpdate:
            (
                validate: Self.validateMerkleUpdate,
                mask: { (bits: [Bit], refs: [Cell]) in
                    Mask(maskValue: (refs[0].mask.value | refs[1].mask.value) >> 1)
                }
            )
        }
    }
    
    private var _bits: [Bit]
    public var bits: [Bit] { _bits }
    private var _refs: [Cell]
    public var refs: [Cell] { _refs }
    private var _type: CellType
    public var type: CellType { _type }
    private var _mask: Mask
    public var mask: Mask { _mask }
    private var _hashes: [String]
    public var hashes: [String] { _hashes }
    private var _depths: [BigUInt]
    public var depths: [BigUInt] { _depths }

    public init(bits: [Bit] = .init(), refs: [Cell] = .init(), type: CellType = .ordinary) throws {
        let mapper = Self.getMapper(type: type)
        let validate = mapper.validate
        let mask = mapper.mask
        
        try validate(bits, refs)
        self._mask = mask(bits, refs)
        self._bits = bits
        self._refs = refs
        self._type = type
        self._depths = []
        self._hashes = []
        
        try initialize()
    }

    private func initialize() throws {
        let hasRefs = refs.count > 0
        let isMerkle = [CellType.merkleProof, CellType.merkleUpdate].contains(type)
        let isPrunedBranch = type == CellType.prunedBranch
        let hashIndexOffset = isPrunedBranch ? mask.hashCount - 1 : 0

        var hashIndex: UInt32 = 0

        for levelIndex in 0...mask.level {
            if !mask.isSignificant(level: levelIndex) { continue }
            if hashIndex < hashIndexOffset { continue }

            if (hashIndex == hashIndexOffset && levelIndex != 0 && !isPrunedBranch) ||
               (hashIndex != hashIndexOffset && levelIndex == 0 && isPrunedBranch) 
            {
                throw ErrorTonSdkSwift("Can't deserialize cell")
            }
            
            let refLevel = levelIndex + (isMerkle ? 1 : 0)
            let refsDescriptor = getRefsDescriptor(mask.apply(level: levelIndex))
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
                let refHash = try ref.hash(refLevel)
                depthRepresentation += Cell.getDepthDescriptor(UInt32(refDepth))
                hashRepresentation += refHash.hexToBits()
                depth = max(depth, refDepth)
            }

            let representation: [Bit] = refsDescriptor + bitsDescriptor + data + depthRepresentation + hashRepresentation
            
            if refs.count > 0 && depth >= 1024 {
                throw ErrorTonSdkSwift("Cell depth can't be more than 1024")
            }

            let dest = Int(hashIndex - hashIndexOffset)
            let newDepth = depth + (hasRefs ? 1 : 0)
            
            let newHash: String = try representation.toBytes().sha256()
            
            if dest == 0 {
                _depths.append(newDepth)
                _hashes.append(newHash)
            } else {
                _depths[dest] = newDepth
                _hashes[dest] = newHash
            }
            
            hashIndex += 1
        }
        
        
    }
    
    public var isExotic: Bool {
        type != .ordinary
    }

    public static func getDepthDescriptor(_ depth: UInt32) -> [Bit] {
        let descriptor = Data([UInt8(depth / 256), UInt8(depth % 256)])
        return descriptor.toBits()
    }

    public func getRefsDescriptor(_ mask: Mask? = nil) -> [Bit] {
        let value = UInt32(refs.count) +
            (isExotic ? 8 : 0) +
            ((mask != nil ? mask!.value : self.mask.value) * 32)
        
        let descriptor = Data([UInt8(value)])
        return descriptor.toBits()
    }

    public func getBitsDescriptor() -> [Bit] {
        let value = Int(ceil(Double(bits.count) / 8.0)) + Int(floor(Double(bits.count) / 8.0))
        let descriptor = Data([UInt8(value)])
        return descriptor.toBits()
    }

    public func getAugmentedBits() -> [Bit] {
        bits.augment()
    }

    public func hash(_ level: UInt32 = 3) throws -> String {
        guard type != CellType.prunedBranch else {
            let hashIndex = mask.apply(level: level).hashIndex
            let thisHashIndex = mask.hashIndex
            let skip = 16 + hashIndex * Cell.HASH_BITS

            if hashIndex != thisHashIndex {
                return try [Bit](bits[Int(skip)..<Int(skip + Cell.HASH_BITS)]).toHex().uppercased()
            } else {
                return hashes[0]
            }
        }
        return hashes[Int(mask.apply(level: level).hashIndex)]
    }

    // Get cell's depth (max level by default)
    public func depth(_ level: UInt32 = 3) -> BigUInt {
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
    public func parse() -> CellSlice {
        return CellSlice.parse(cell: self)
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
        (try hash()) == (try cell.hash())
    }
}
