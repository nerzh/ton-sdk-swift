//
//  File.swift
//
//
//  Created by Oleh Hudeichuk on 02.02.2024.
//

import Foundation
import BigInt

public struct Cell {
    public static let HASH_BITS: UInt32 = 256
    public static let DEPTH_BITS: UInt32 = 16
    
    public enum CellType: Int8 {
        case ordinary = -1
        case prunedBranch = 1
        case libraryReference = 2
        case merkleProof = 3
        case merkleUpdate = 4
    }
    
    public static func validateOrdinary(bits: Bits, refs: [Cell]) throws {
        let maxBitsCount: Int = 1023
        let maxRefsCount: Int = 4
        
        if bits.count > maxBitsCount {
            throw ErrorTonSdkSwift("Ordinary cell can't have more than \(maxBitsCount) bits, got \(bits.count)")
        }
        
        if refs.count > maxRefsCount {
            throw ErrorTonSdkSwift("Ordinary cell can't have more than \(maxRefsCount) refs, got \(refs.count)")
        }
    }

    public static func validatePrunedBranch(bits: Bits, refs: [Cell]) throws {
        let minSize = 8 + 8 + (1 * (HASH_BITS + DEPTH_BITS))

        if bits.count < minSize {
            throw ErrorTonSdkSwift("Pruned Branch cell can't have less than (8 + 8 + 256 + 16) bits, got \(bits.count)")
        }

        if !refs.isEmpty {
            throw ErrorTonSdkSwift("Pruned Branch cell can't have refs, got \(refs.count)")
        }

        let type = Int8(Bits(bits[0...8]).toBigInt())
        
        if type != CellType.prunedBranch.rawValue {
            throw ErrorTonSdkSwift("Pruned Branch cell type must be exactly \(CellType.prunedBranch), got \(type)")
        }

        let mask = Mask(maskValue: UInt32(Bits(bits[8...16]).toBigUInt()))

        if mask.level < 1 || mask.level > 3 {
            throw ErrorTonSdkSwift("Pruned Branch cell level must be >= 1 and <= 3, got \(mask.level)")
        }

        let hashCount = mask.apply(level: mask.level - 1).hashCount
        let size = 8 + 8 + (hashCount * (HASH_BITS + DEPTH_BITS))

        if bits.count != size {
            throw ErrorTonSdkSwift("Pruned Branch cell with level \(mask.level) must have exactly \(size) bits, got \(bits.count)")
        }
    }
    
    public static func validateLibraryReference(bits: Bits, refs: [Cell]) throws {
        // Type + hash
        let size = 8 + HASH_BITS

        if bits.count != size {
            throw ErrorTonSdkSwift("Library Reference cell must have exactly \(size) bits, got \(bits.count)")
        }

        if !refs.isEmpty {
            throw ErrorTonSdkSwift("Library Reference cell can't have refs, got \(refs.count)")
        }
        
        let type = Int8(Bits(bits[0..<8]).toBigInt())

        if type != CellType.libraryReference.rawValue {
            throw ErrorTonSdkSwift("Library Reference cell type must be exactly \(CellType.libraryReference), got \(type)")
        }
    }
    
    public static func validateMerkleProof(bits: Bits, refs: [Cell]) throws {
        // Type + hash + depth
        let size = 8 + HASH_BITS + DEPTH_BITS

        if bits.count != size {
            throw ErrorTonSdkSwift("Merkle Proof cell must have exactly \(size) bits, got \(bits.count)")
        }

        guard refs.count == 1 else {
            throw ErrorTonSdkSwift("Merkle Proof cell must have exactly 1 ref, got \(refs.count)")
        }

        let type = Int8(Bits(bits[0..<8]).toBigInt())

        if type != CellType.merkleProof.rawValue {
            throw ErrorTonSdkSwift("Merkle Proof cell type must be exactly \(CellType.merkleProof), got \(type)")
        }

        let data = Bits(bits[8...])
        let proofHash = try Bits(Array(data[0..<Int(HASH_BITS / 4)])).toHex()
        let proofDepth = Bits(Array(data[Int(HASH_BITS / 4)..<Int(HASH_BITS / 4 + DEPTH_BITS)])).toBigUInt()
        #warning("AFTER CELL")
//        let refHash = refs[0].hash(0)
//        let refDepth = refs[0].depth(0)
//
//        guard proofHash == refHash else {
//            throw ErrorTonSdkSwift.merkleProofCellRefHashMismatch("Merkle Proof cell ref hash must be exactly \"\(proofHash)\", got \"\(refHash)\"")
//        }
//
//        guard proofDepth == refDepth else {
//            throw ErrorTonSdkSwift.merkleProofCellRefDepthMismatch("Merkle Proof cell ref depth must be exactly \"\(proofDepth)\", got \"\(refDepth)\"")
//        }
    }
    
    public static func validateMerkleUpdate(bits: Bits, refs: [Cell]) throws {
        let size = 8 + (2 * (256 + 16))
        
        if bits.count != size {
            throw ErrorTonSdkSwift("Merkle Update cell must have exactly \(size) bits, got \(bits.count)")
        }
        
        if refs.count != 2 {
            throw ErrorTonSdkSwift("Merkle Update cell must have exactly 2 refs, got \(refs.count)")
        }
        
        let type = Bits(bits[0..<8]).toBigInt()
        
        if type != CellType.merkleUpdate.rawValue {
            throw ErrorTonSdkSwift("Merkle Update cell type must be exactly \(CellType.merkleUpdate), got \(type)")
        }
        
        let data = bits[8...]
        let hashes = [
            try Bits(data[0..<256]).toHex(),
            try Bits(data[256..<512]).toHex()
        ]
        let depths = [
            Bits(data[512..<528]).toBigUInt(),
            Bits(data[528..<544]).toBigUInt()
        ]

        #warning("AFTER CELL 2")
//        for (index, ref) in refs.enumerated() {
//            let proofHash = hashes[index]
//            let proofDepth = depths[index]
//            let refHash = ref.hash(0)
//            let refDepth = ref.depth(0)
//
//            guard proofHash == refHash else {
//                throw ErrorTonSdkSwift.merkleUpdateCellRefHashMismatch("Merkle Update cell ref #\(index) hash must be exactly '\(proofHash)', got '\(refHash)'")
//            }
//
//            guard proofDepth == refDepth else {
//                throw ErrorTonSdkSwift.merkleUpdateCellRefDepthMismatch("Merkle Update cell ref #\(index) depth must be exactly '\(proofDepth)', got '\(refDepth)'")
//            }
//        }
    }
    
    public static func getMapper(type: Cell.CellType) -> (validate: (Bits, [Cell]) throws -> Void, mask: (Bits, [Cell]) -> Mask) {
        return switch type {
        case .ordinary:
            (
                validate: Self.validateOrdinary,
                mask: { (bits: Bits, refs: [Cell]) in
                    Mask(maskValue: refs.reduce(0) { acc, el in
                        acc | el.mask.value
                    })
                }
            )
        case .prunedBranch:
            (
                validate: Self.validatePrunedBranch,
                mask: { (bits: Bits, refs: [Cell]) in
                    Mask(maskValue: UInt32(Bits(bits[8..<16]).toBigUInt()))
                }
            )
        case .libraryReference:
            (
                validate: Self.validateLibraryReference,
                mask: { (bits: Bits, refs: [Cell]) in
                    Mask(maskValue: 0)
                }
            )
        case .merkleProof:
            (
                validate: Self.validateMerkleProof,
                mask: { (bits: Bits, refs: [Cell]) in
                    Mask(maskValue: refs[0].mask.value >> 1)
                }
            )
        case .merkleUpdate:
            (
                validate: Self.validateMerkleUpdate,
                mask: { (bits: Bits, refs: [Cell]) in
                    Mask(maskValue: (refs[0].mask.value | refs[1].mask.value) >> 1)
                }
            )
        }
    }
    
    private var _bits: Bits
    public var bits: Bits { _bits }
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

    init(bits: Bits = .init(), refs: [Cell] = .init(), type: CellType = .ordinary) throws {
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

        var hashIndex = 0

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
            let data: [Int]

            if hashIndex != hashIndexOffset {
                data = hexToBits(hashes[hashIndex - hashIndexOffset - 1])
            } else {
                data = getAugmentedBits()
            }

            var depthRepresentation: [Int] = []
            var hashRepresentation: [Int] = []
            var depth = 0

            for ref in refs {
                let refDepth = ref.depth(refLevel)
                let refHash = ref.hash(refLevel)

                depthRepresentation.append(contentsOf: Cell.getDepthDescriptor(refDepth))
                hashRepresentation.append(contentsOf: hexToBits(refHash))
                depth = max(depth, refDepth)
            }

            let representation = refsDescriptor + bitsDescriptor + data + depthRepresentation + hashRepresentation

            if refs.count > 0 && depth >= 1024 {
                throw ErrorTonSdkSwift.cellDepthError("Cell depth can't be more than 1024")
            }

            let dest = hashIndex - hashIndexOffset
            depths[dest] = depth + (hasRefs ? 1 : 0)
            hashes[dest] = sha256(bitsToBytes(representation))
            hashIndex += 1
        }
    }
    
    public var isExotic: Bool {
        type != .ordinary
    }

    // Calculate depth descriptor
    public static func getDepthDescriptor(_ depth: UInt8) -> Bits {
        let descriptor = [depth / 256, depth % 256]
        return Bits.init(descriptor)
    }

    // Get current Cell instance refs descriptor
    public func getRefsDescriptor(_ mask: Mask? = nil) -> Bits {
        let value = UInt32(refs.count) +
            (isExotic ? 8 : 0) +
            ((mask != nil ? mask!.value : self.mask.value) * 32)

        let descriptor = [UInt8(value)]
        return .init(descriptor)
    }

    // Get current Cell instance bits descriptor
    public func getBitsDescriptor() -> Bits {
        let value = Int(ceil(Double(bits.count) / 8.0)) + Int(floor(Double(bits.count) / 8.0))
        let descriptor = [UInt8(value)]
        return .init(descriptor)
    }

    // Get current Cell instance augmented bits
    public func getAugmentedBits() -> Bits {
        bits.augment()
    }

    // Get cell's hash in hex (max level by default)
    public func hash(_ level: UInt32 = 3) throws -> String {
        guard type != CellType.prunedBranch else {
            let hashIndex = mask.apply(level: level).hashIndex
            let thisHashIndex = mask.hashIndex
            let skip = 16 + hashIndex * Cell.HASH_BITS

            if hashIndex != thisHashIndex {
                return try Bits(bits[Int(skip)..<Int(skip + Cell.HASH_BITS)]).toHex().uppercased()
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
                return Bits(bits[Int(skip)..<Int(skip + Cell.DEPTH_BITS)]).toBigUInt()
            } else {
                return depths[0]
            }
        }
        return depths[Int(mask.apply(level: level).hashIndex)]
    }

    // Get Slice from current instance
//    func parse() -> Slice {
//        return Slice.parse(self)
//    }

    // Print cell as fift-hex
    func printCell(indent: Int = 1, size: Int = 0) throws -> String {
        let bitsCopy = bits
        let areDivisible = bitsCopy.count % 4 == 0
        let augmented = areDivisible ? bitsCopy : bitsCopy.augment(divider: 4)
        let fiftHex = "\(try augmented.toHex().uppercased())\(areDivisible ? "" : "_")"
        var output = "\(String(repeating: " ", count: indent * size))x{\(fiftHex)\n"

        for ref in refs {
            output += try ref.printCell(indent: indent, size: size + 1)
        }

        return output
    }

    // Checks Cell equality by comparing cell hashes
    func isEqual(_ cell: Cell) throws -> Bool {
        (try hash()) == (try cell.hash())
    }
}
