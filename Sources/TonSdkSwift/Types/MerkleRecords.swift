import BigInt
import Foundation

/// A checked Merkle proof record. The embedded hash authenticates the level-zero
/// root only; callers must compare it with a trusted external hash.
public struct MerkleProof: Equatable {
    public let hash: String
    public let depth: UInt16
    public let proof: Cell

    public init(proof: Cell) throws {
        hash = try proof.hash(0).lowercased()
        depth = try merkleDepth(proof, level: 0)
        self.proof = proof
    }

    /// Checks the cell type, exact shape, and both embedded hash and depth.
    public init(cell: Cell) throws {
        guard cell.type == .merkleProof else { throw ErrorTonSdkSwift("Expected a Merkle proof cell") }
        try Cell.validateMerkleProof(bits: cell.bits, refs: cell.refs)
        try self.init(proof: cell.reference(at: 0))
    }

    /// Requires a complete cursor with retained source metadata and an unconsumed origin.
    /// Arrays alone cannot establish the exotic cell type or original cursor position.
    public static func read(from slice: CellSlice) throws -> MerkleProof {
        guard let source = slice.sourceCell, source.type == .merkleProof,
              slice.consumedBits == 0, slice.consumedRefs == 0,
              slice.bits == source.bits, slice.refs == source.refs else {
            throw ErrorTonSdkSwift("Merkle proof requires its original complete cell slice")
        }
        let record = try MerkleProof(cell: source)
        try slice.skipBits(size: 280)
        try slice.skipRefs(size: 1)
        return record
    }

    public func cell() throws -> Cell {
        let builder = try CellBuilder().storeUInt(3, 8)
            .storeBytes(proof.hash(0).hexToBytes()).storeUInt(BigUInt(depth), 16).storeRef(proof)
        return try Cell(bits: builder.bits, refs: builder.refs, type: .merkleProof,
                        compatibility: proof.compatibility)
    }

    public func virtualRoot() -> Cell { proof.virtualized(at: 0) }

    public func check(expectedHash: String) throws {
        guard hash == expectedHash.lowercased() else { throw ErrorTonSdkSwift("Merkle proof root hash mismatch") }
    }
}

/// A checked TON Merkle update record. `check()` additionally validates that each
/// replacement branch is justified by the old partial tree. `apply(to:)` checks a
/// concrete old root and verifies the reconstructed level-zero hash and depth.
/// Higher hashes describe the supplied proof representation, not the committed state.
public struct MerkleUpdate: Equatable {
    public let oldHash: String
    public let newHash: String
    public let oldDepth: UInt16
    public let newDepth: UInt16
    public let old: Cell
    public let new: Cell

    public init(old: Cell, new: Cell) throws {
        oldHash = try old.hash(0).lowercased()
        newHash = try new.hash(0).lowercased()
        oldDepth = try merkleDepth(old, level: 0)
        newDepth = try merkleDepth(new, level: 0)
        self.old = old
        self.new = new
    }

    public init(cell: Cell) throws {
        guard cell.type == .merkleUpdate else { throw ErrorTonSdkSwift("Expected a Merkle update cell") }
        try Cell.validateMerkleUpdate(bits: cell.bits, refs: cell.refs)
        try self.init(old: cell.reference(at: 0), new: cell.reference(at: 1))
    }

    public static func read(from slice: CellSlice) throws -> MerkleUpdate {
        guard let source = slice.sourceCell, source.type == .merkleUpdate,
              slice.consumedBits == 0, slice.consumedRefs == 0,
              slice.bits == source.bits, slice.refs == source.refs else {
            throw ErrorTonSdkSwift("Merkle update requires its original complete cell slice")
        }
        let record = try MerkleUpdate(cell: source)
        try slice.skipBits(size: 552)
        try slice.skipRefs(size: 2)
        return record
    }

    public func cell() throws -> Cell {
        let builder = try CellBuilder().storeUInt(4, 8)
            .storeBytes(old.hash(0).hexToBytes()).storeBytes(new.hash(0).hexToBytes())
            .storeUInt(BigUInt(oldDepth), 16).storeUInt(BigUInt(newDepth), 16)
            .storeRefs([old, new])
        return try Cell(bits: builder.bits, refs: builder.refs, type: .merkleUpdate,
                        compatibility: old.compatibility)
    }
}

internal func merkleDepth(_ cell: Cell, level: UInt32) throws -> UInt16 {
    guard let depth = UInt16(exactly: cell.depth(level)) else {
        throw ErrorTonSdkSwift("Merkle depth exceeds its 16-bit field")
    }
    return depth
}
