import BigInt
import Foundation

extension Cell {
    public var isMerkle: Bool { type == .merkleProof || type == .merkleUpdate }

    /// A TON view capped at an effective hash level. This is not a mask-shift offset.
    /// In particular, a proof's child is viewed at level zero.
    public func virtualized(at effectiveLevel: UInt32 = 0) -> Cell {
        guard mask.level > min(effectiveLevel, 3) else { return self }
        return VirtualCell(cell: self, effectiveLevel: effectiveLevel)
    }

    /// An ordinary TL-B cursor. Raw `parse()` intentionally also permits exotic cells.
    public func ordinarySlice() throws -> CellSlice {
        guard type == .ordinary else { throw ErrorTonSdkSwift("Expected an ordinary cell") }
        return parse()
    }
}

/// Immutable TON virtualization, with no hash recomputation or storage rebuilding.
/// Follows TON's effective-level convention, rather than EverBlock's offset convention.
public final class VirtualCell: Cell {
    public let underlying: Cell
    public let effectiveLevel: UInt32

    public init(cell: Cell, effectiveLevel: UInt32 = 0) {
        if let view = cell as? VirtualCell {
            underlying = view.underlying
            self.effectiveLevel = min(view.effectiveLevel, effectiveLevel, 3)
        } else {
            underlying = cell
            self.effectiveLevel = min(effectiveLevel, 3)
        }
        super.init(wrapping: underlying)
    }

    public override var bits: [Bit] { underlying.bits }
    public override var bigData: Data? { underlying.bigData }
    public override var type: CellType { underlying.type }
    public override var mask: Mask { underlying.mask.apply(level: effectiveLevel) }
    public override var isVirtualized: Bool { true }
    private var childLevel: UInt32 { min(3, effectiveLevel + (isMerkle ? 1 : 0)) }
    public override var refs: [Cell] { underlying.refs.map { $0.virtualized(at: childLevel) } }
    public override func reference(at index: Int) throws -> Cell {
        try underlying.reference(at: index).virtualized(at: childLevel)
    }
    public override func parse() -> CellSlice {
        CellViewSlice(underlying.parse(), sourceCell: self, childLevel: childLevel)
    }
    public override func hash(_ level: UInt32 = 3) throws -> String {
        try underlying.hash(min(level, effectiveLevel))
    }
    public override func depth(_ level: UInt32 = 3) -> BigUInt {
        underlying.depth(min(level, effectiveLevel))
    }
    public override var hashes: [String] {
        (0...mask.level).filter { mask.isSignificant(level: $0) }.map { try! hash($0) }
    }
    public override var depths: [BigUInt] {
        (0...mask.level).filter { mask.isSignificant(level: $0) }.map { depth($0) }
    }
}

/// Access tracking by normalized representation hash. Snapshots are protected by a lock.
/// Hash/depth reads and creation of a cursor do not visit its source. Reading data or
/// references visits that source; `visitOnLoad` also visits the loaded child.
public final class UsageTree {
    private let root: Cell
    private let visitOnLoad: Bool
    private let lock = NSLock()
    private var visited: [String: Cell] = [:]

    public init(root: Cell, visitOnLoad: Bool = false) {
        self.root = root
        self.visitOnLoad = visitOnLoad
        if visitOnLoad { record(root) }
    }

    public func rootCell() -> Cell { UsageCell(root, tree: self, visitOnLoad: visitOnLoad) }

    /// Explicitly includes a cell even when it is not a descendant of the tracked root.
    public func useCell(_ cell: Cell, visitOnLoad: Bool = false) -> Cell {
        record(cell)
        return UsageCell(cell, tree: self, visitOnLoad: visitOnLoad)
    }

    public func contains(_ hash: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return visited[hash.lowercased()] != nil
    }

    public func buildVisitedSet() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(visited.keys)
    }

    /// Selects visited roots, then follows only children present in the same snapshot.
    public func buildVisitedSubtree(isInclude: (String) -> Bool) throws -> Set<String> {
        lock.lock()
        let snapshot = visited
        lock.unlock()
        var pending = snapshot.filter { isInclude($0.key) }.map(\.value)
        var result = Set<String>()
        while let cell = pending.popLast() {
            guard result.insert(try cell.hash().lowercased()).inserted else { continue }
            for child in cell.refs {
                if let visitedChild = snapshot[try child.hash().lowercased()] { pending.append(visitedChild) }
            }
        }
        return result
    }

    fileprivate func record(_ cell: Cell) {
        guard let hash = try? cell.hash().lowercased() else { return }
        let stored = (cell as? UsageCell)?.underlying ?? cell
        lock.lock()
        visited[hash] = stored
        lock.unlock()
    }
}

private final class UsageCell: Cell {
    let underlying: Cell
    // A visited snapshot may retain a view of this same tree. The view must not
    // retain its observer in return; data access remains valid after it expires.
    weak var tree: UsageTree?
    let visitOnLoad: Bool

    init(_ cell: Cell, tree: UsageTree, visitOnLoad: Bool) {
        underlying = cell
        self.tree = tree
        self.visitOnLoad = visitOnLoad
        super.init(wrapping: underlying)
    }

    func child(_ cell: Cell) -> Cell {
        guard let tree else { return cell }
        if visitOnLoad { tree.record(cell) }
        return UsageCell(cell, tree: tree, visitOnLoad: visitOnLoad)
    }

    override var bits: [Bit] { tree?.record(underlying); return underlying.bits }
    override var bigData: Data? {
        if underlying.type == .big { tree?.record(underlying) }
        return underlying.bigData
    }
    override var refs: [Cell] {
        tree?.record(underlying)
        return underlying.refs.map(child)
    }
    override var type: CellType { underlying.type }
    override var mask: Mask { underlying.mask }
    override var isVirtualized: Bool { underlying.isVirtualized }
    override var hashes: [String] { underlying.hashes }
    override var depths: [BigUInt] { underlying.depths }
    override func hash(_ level: UInt32 = 3) throws -> String { try underlying.hash(level) }
    override func depth(_ level: UInt32 = 3) -> BigUInt { underlying.depth(level) }
    override func reference(at index: Int) throws -> Cell {
        let reference = try underlying.reference(at: index)
        tree?.record(underlying)
        return child(reference)
    }
    override func parse() -> CellSlice { CellViewSlice(underlying.parse(), sourceCell: self, owner: self) }
}

private final class CellViewSlice: CellSlice {
    private let owner: UsageCell?
    private let childLevel: UInt32?
    private let underlyingSlice: CellSlice
    // Initial storage is copied only to retain the base cursor's origin counts.
    // Reads delegate to the underlying cursor so nested usage views remain lazy
    // during creation and retain every tracker when data is actually accessed.
    private var initialStorageBits: [Bit] { super.bits }
    private var initialStorageRefs: [Cell] { super.refs }
    init(_ underlyingSlice: CellSlice, sourceCell: Cell, owner: UsageCell? = nil,
         childLevel: UInt32? = nil) {
        self.owner = owner
        self.childLevel = childLevel
        self.underlyingSlice = underlyingSlice
        if let view = underlyingSlice as? CellViewSlice {
            super.init(bits: view.initialStorageBits, refs: view.initialStorageRefs, sourceCell: sourceCell)
        } else {
            super.init(bits: underlyingSlice.bits, refs: underlyingSlice.refs, sourceCell: sourceCell)
        }
    }
    private func recordRead() {
        if let owner { owner.tree?.record(owner.underlying) }
    }
    private func child(_ cell: Cell) -> Cell {
        let wrapped = owner?.child(cell) ?? cell
        return childLevel.map { wrapped.virtualized(at: $0) } ?? wrapped
    }
    override var consumedBits: Int { underlyingSlice.consumedBits }
    override var consumedRefs: Int { underlyingSlice.consumedRefs }
    override var bits: [Bit] {
        get { recordRead(); return underlyingSlice.bits }
        set { underlyingSlice.bits = newValue }
    }
    override var refs: [Cell] {
        get {
            recordRead()
            // Reading the whole array loads every child in visit-on-load mode.
            return underlyingSlice.refs.map(child)
        }
        set { underlyingSlice.refs = newValue }
    }
    override func preloadRef() throws -> Cell {
        let cell = try underlyingSlice.preloadRef()
        recordRead()
        return child(cell)
    }
    override func loadRef() throws -> Cell {
        let cell = try underlyingSlice.loadRef()
        recordRead()
        return child(cell)
    }
}
