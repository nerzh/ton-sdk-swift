import BigInt
import Foundation

private struct MerkleNodeKey: Hashable {
    let hash: String
    let level: UInt32
    init(_ cell: Cell, _ level: UInt32) throws {
        hash = try cell.hash().lowercased()
        self.level = level
    }
    init(hash: String, level: UInt32) {
        self.hash = hash
        self.level = level
    }
}

private func merkleChildLevel(_ cell: Cell, _ level: UInt32) -> UInt32 {
    min(3, level + (cell.isMerkle ? 1 : 0))
}

/// Rebuilding is shape-only because nested records may commit to a deeper view.
/// Typed record readers remain strict at their public boundaries.
private func merkleRebuild(_ cell: Cell, _ refs: [Cell]) throws -> Cell {
    if zip(cell.refs, refs).allSatisfy({ $0 === $1 }) && cell.refs.count == refs.count { return cell }
    return try Cell(bits: cell.bits, refs: refs, type: cell.type,
                    checkMerkleMetadata: false, compatibility: cell.compatibility)
}

extension Cell {
    /// Replaces this subtree with a branch that preserves hashes through `merkleDepth`.
    /// Only levels 0...2 can be pruned; level 3 is already the maximum cell level.
    public func prunedBranch(merkleDepth: UInt32 = 0) throws -> Cell {
        guard merkleDepth < 3, !isVirtualized else {
            throw ErrorTonSdkSwift("Cannot prune this virtual cell or Merkle level")
        }
        let lowerMask = mask.apply(level: merkleDepth)
        let branchMask = lowerMask.value | (1 << merkleDepth)
        let levels = (0...merkleDepth).filter { lowerMask.isSignificant(level: $0) }
        let builder = try CellBuilder().storeUInt(1, 8).storeUInt(BigUInt(branchMask), 8)
        for level in levels { try builder.storeBytes(hash(level).hexToBytes()) }
        for level in levels { try builder.storeUInt(BigUInt(merkleDepthValue(level)), 16) }
        return try Cell(bits: builder.bits, type: .prunedBranch, compatibility: compatibility)
    }

    private func merkleDepthValue(_ level: UInt32) throws -> UInt16 { try merkleDepth(self, level: level) }
}

extension MerkleProof {
    /// Includes selected cells and prunes unselected descendants. The root must be
    /// selected; predicates receive lowercase representation hashes.
    public static func create(root: Cell, isInclude: (String) -> Bool) throws -> MerkleProof {
        try create(root: root, isInclude: isInclude, isIncludeSubtree: { _ in false })
    }

    public static func create(root: Cell, isInclude: (String) -> Bool,
                              isIncludeSubtree: (String) -> Bool) throws -> MerkleProof {
        let rootHash = try root.hash().lowercased()
        guard !root.isVirtualized, isInclude(rootHash) || isIncludeSubtree(rootHash) else {
            throw ErrorTonSdkSwift("Merkle proof requires a selected, nonvirtual root")
        }
        return try MerkleProof(proof: pruneMerkleTree(root, isInclude: { hash, _ in isInclude(hash) },
                                                     isIncludeSubtree: { hash, _ in isIncludeSubtree(hash) }))
    }

    public static func create(root: Cell, usageTree: UsageTree) throws -> MerkleProof {
        let visited = usageTree.buildVisitedSet()
        return try create(root: root, isInclude: visited.contains)
    }
}

/// Iterative traversal also caches the Merkle level: the same DAG node can appear
/// inside and outside a Merkle record and requires different pruned branches.
private func pruneMerkleTree(_ root: Cell, isInclude: (String, UInt32) -> Bool,
                             isIncludeSubtree: (String, UInt32) -> Bool) throws -> Cell {
    var stack: [(Cell, UInt32, Bool)] = [(root, 0, false)]
    var result: [MerkleNodeKey: Cell] = [:]
    while let (cell, level, expanded) = stack.popLast() {
        let key = try MerkleNodeKey(cell, level)
        if result[key] != nil { continue }
        if isIncludeSubtree(key.hash, level) {
            result[key] = cell
        } else if !isInclude(key.hash, level) {
            result[key] = try cell.prunedBranch(merkleDepth: level)
        } else if expanded {
            let childLevel = merkleChildLevel(cell, level)
            let children = try cell.refs.map { child -> Cell in
                guard let found = result[try MerkleNodeKey(child, childLevel)] else {
                    throw ErrorTonSdkSwift("Incomplete Merkle traversal")
                }
                return found
            }
            result[key] = try merkleRebuild(cell, children)
        } else {
            stack.append((cell, level, true))
            stack.append(contentsOf: cell.refs.map { ($0, merkleChildLevel(cell, level), false) })
        }
    }
    return result[try MerkleNodeKey(root, 0)]!
}

public struct MerkleUpdateApplyMetrics: Equatable {
    public internal(set) var loadedOldCells: Int = 0
    public internal(set) var createdCells: Int = 0
    public internal(set) var loadedOldCellsTime: TimeInterval = 0
    public init() {}
}

/// A factory may intern rebuilt cells. It must preserve the template's bits, type,
/// compatibility policy, and supplied references. Returned hashes are verified.
public protocol MerkleCellFactory {
    func rebuild(_ template: Cell, references: [Cell]) throws -> Cell
}

public struct DefaultMerkleCellFactory: MerkleCellFactory {
    public init() {}
    public func rebuild(_ template: Cell, references: [Cell]) throws -> Cell {
        try merkleRebuild(template, references)
    }
}

extension MerkleUpdate {
    /// Builds an update using old cells shared by the new DAG. The old tree is kept
    /// complete, allowing checks without trusting an external availability predicate.
    /// This favors a simple, verifiable update over minimum proof size.
    public static func create(old: Cell, new: Cell) throws -> MerkleUpdate {
        try create(old: old, new: new, isReusableOld: { _ in true })
    }

    /// Restricts reuse to explicitly available old subtrees, for example a UsageTree
    /// snapshot. Unlike a proof predicate, this never permits absent old cells.
    public static func create(old: Cell, new: Cell,
                              isReusableOld: (String) -> Bool) throws -> MerkleUpdate {
        guard !old.isVirtualized, !new.isVirtualized else {
            throw ErrorTonSdkSwift("Merkle updates require nonvirtual roots")
        }
        var reusable = Set<MerkleNodeKey>()
        var stack: [(Cell, UInt32)] = [(old, 0)]
        while let (cell, level) = stack.popLast() {
            guard reusable.insert(try MerkleNodeKey(cell, level)).inserted else { continue }
            stack.append(contentsOf: cell.refs.map { ($0, merkleChildLevel(cell, level)) })
        }
        let newTree = try pruneMerkleTree(new, isInclude: { hash, level in
            level == 3 || !reusable.contains(MerkleNodeKey(hash: hash, level: level)) || !isReusableOld(hash)
        }, isIncludeSubtree: { _, _ in false })
        return try MerkleUpdate(old: old, new: newTree)
    }

    /// Validates replacement availability and every committed hash/depth through
    /// each branch's Merkle level, including its applied level mask.
    public func check() throws {
        let available = try oldMerkleCells(old)
        var stack: [(Cell, UInt32)] = [(new, 0)]
        var visited = Set<MerkleNodeKey>()
        while let (cell, level) = stack.popLast() {
            guard visited.insert(try MerkleNodeKey(cell, level)).inserted else { continue }
            if isReplacementBranch(cell, level) {
                guard let found = available[try merkleLookupKey(cell, level)] else {
                    throw ErrorTonSdkSwift("Merkle update references a subtree absent from its old proof")
                }
                try compareMerkleCommitments(found, cell, through: level)
            } else {
                stack.append(contentsOf: cell.refs.map { ($0, merkleChildLevel(cell, level)) })
            }
        }
    }

    public func apply(to oldRoot: Cell) throws -> Cell {
        try apply(to: oldRoot, factory: DefaultMerkleCellFactory()).cell
    }

    public func apply(to oldRoot: Cell, factory: any MerkleCellFactory) throws ->
        (cell: Cell, metrics: MerkleUpdateApplyMetrics) {
        guard !oldRoot.isVirtualized, try oldRoot.hash(0).lowercased() == oldHash,
              oldRoot.depth(0) == BigUInt(oldDepth) else {
            throw ErrorTonSdkSwift("Merkle update old root mismatch")
        }
        try check()
        let start = ProcessInfo.processInfo.systemUptime
        let available = try oldMerkleCells(oldRoot, matching: old)
        var metrics = MerkleUpdateApplyMetrics()
        metrics.loadedOldCells = available.count
        metrics.loadedOldCellsTime = ProcessInfo.processInfo.systemUptime - start
        var result: [MerkleNodeKey: Cell] = [:]
        var stack: [(Cell, UInt32, Bool)] = [(new, 0, false)]
        while let (cell, level, expanded) = stack.popLast() {
            let key = try MerkleNodeKey(cell, level)
            if result[key] != nil { continue }
            if isReplacementBranch(cell, level) {
                guard let found = available[try merkleLookupKey(cell, level)] else {
                    throw ErrorTonSdkSwift("Merkle update cannot load its replacement subtree")
                }
                try compareMerkleCommitments(found, cell, through: level)
                result[key] = found
            } else if expanded {
                let children = try cell.refs.map { child -> Cell in
                    guard let found = result[try MerkleNodeKey(child, merkleChildLevel(cell, level))] else {
                        throw ErrorTonSdkSwift("Incomplete Merkle update traversal")
                    }
                    return found
                }
                let rebuilt = try factory.rebuild(cell, references: children)
                let sameData = cell.type == .big ? rebuilt.bigData == cell.bigData : rebuilt.bits == cell.bits
                guard !rebuilt.isVirtualized, rebuilt.type == cell.type, sameData,
                      rebuilt.compatibility == cell.compatibility, rebuilt.refs == children else {
                    throw ErrorTonSdkSwift("Merkle cell factory changed the committed subtree")
                }
                try compareMerkleCommitments(rebuilt, cell, through: level)
                result[key] = rebuilt
                metrics.createdCells += 1
            } else {
                stack.append((cell, level, true))
                stack.append(contentsOf: cell.refs.map { ($0, merkleChildLevel(cell, level), false) })
            }
        }
        let updated = result[try MerkleNodeKey(new, 0)]!
        guard try updated.hash(0).lowercased() == newHash, updated.depth(0) == BigUInt(newDepth) else {
            throw ErrorTonSdkSwift("Merkle update new root mismatch")
        }
        return (updated, metrics)
    }
}

private func isReplacementBranch(_ cell: Cell, _ level: UInt32) -> Bool {
    cell.type == .prunedBranch && level < 3 && cell.mask.level == level + 1
}

private struct MerkleLookupKey: Hashable {
    let hash: String
    let level: UInt32
}

private func merkleLookupKey(_ cell: Cell, _ level: UInt32) throws -> MerkleLookupKey {
    MerkleLookupKey(hash: try cell.hash(level).lowercased(), level: level)
}

/// Higher pruned hashes are stored independently from their lower commitments.
/// Matching only the highest requested hash can accept inconsistent lower data.
private func compareMerkleCommitments(_ lhs: Cell, _ rhs: Cell, through level: UInt32) throws {
    guard lhs.mask.apply(level: level).value == rhs.mask.apply(level: level).value else {
        throw ErrorTonSdkSwift("Merkle update subtree level mask mismatch")
    }
    for index in 0...level {
        guard try lhs.hash(index).lowercased() == rhs.hash(index).lowercased(),
              lhs.depth(index) == rhs.depth(index) else {
            throw ErrorTonSdkSwift("Merkle update subtree hash or depth mismatch")
        }
    }
}

private func oldMerkleCells(_ root: Cell, matching proof: Cell? = nil) throws -> [MerkleLookupKey: Cell] {
    var result: [MerkleLookupKey: Cell] = [:]
    var visited = Set<MerkleNodeKey>()
    var stack: [(Cell, Cell?, UInt32)] = [(root, proof, 0)]
    while let (cell, proof, level) = stack.popLast() {
        if let proof { try compareMerkleCommitments(cell, proof, through: level) }
        // A source cell can occur with different partial proof representations.
        // Visit by proof identity so each supplied representation is checked.
        guard visited.insert(try MerkleNodeKey(proof ?? cell, level)).inserted else { continue }
        let key = try merkleLookupKey(cell, level)
        // A complete subtree and its pruned commitment share lower hashes. Keep
        // the more complete representation instead of depending on DAG walk order.
        if let previous = result[key] {
            try compareMerkleCommitments(previous, cell, through: level)
            if cell.mask.level < previous.mask.level { result[key] = cell }
        } else {
            result[key] = cell
        }
        if let proof {
            if proof.type == .prunedBranch { continue }
            guard cell.refs.count == proof.refs.count else {
                throw ErrorTonSdkSwift("Merkle update old proof shape mismatch")
            }
            stack.append(contentsOf: zip(cell.refs, proof.refs).map {
                ($0, $1, merkleChildLevel(cell, level))
            })
        } else {
            stack.append(contentsOf: cell.refs.map { ($0, nil, merkleChildLevel(cell, level)) })
        }
    }
    return result
}
