// Original SDK implementation of TON PfxHashmap/PfxHashmapE.

/// Variable-length keys forming a prefix code. Unlike a general string trie,
/// no stored key can be a prefix of another. Colliding insertions throw without
/// modifying the root. The empty key is valid only as the sole stored key.
public struct PfxHashmapE {
    public let keySize: Int
    public private(set) var root: Cell?
    public var isEmpty: Bool { root == nil }
    private var tree: DictionaryTree { DictionaryTree(prefix: true) }

    public init(keySize: Int, root: Cell? = nil) throws {
        try DictionaryLabel.validateWidth(keySize)
        self.keySize = keySize
        self.root = root
    }

    public func get(_ key: [Bit]) throws -> CellSlice? {
        try DictionaryLabel.validateKey(key, width: keySize, prefix: true)
        return try tree.get(root, width: keySize, key: key)
    }

    @discardableResult
    public mutating func set(_ key: [Bit], value: CellSlice) throws -> CellSlice? {
        try update(key, value: value, mode: .set)
    }

    @discardableResult
    public mutating func add(_ key: [Bit], value: CellSlice) throws -> CellSlice? {
        try update(key, value: value, mode: .add)
    }

    @discardableResult
    public mutating func replace(_ key: [Bit], value: CellSlice) throws -> CellSlice? {
        try update(key, value: value, mode: .replace)
    }

    private mutating func update(_ key: [Bit], value: CellSlice, mode: DictionaryTree.Mode) throws -> CellSlice? {
        try DictionaryLabel.validateKey(key, width: keySize, prefix: true)
        let result = try tree.update(root, width: keySize, key: key, value: value, mode: mode)
        root = result.0
        return result.1
    }

    @discardableResult
    public mutating func remove(_ key: [Bit]) throws -> CellSlice? {
        try DictionaryLabel.validateKey(key, width: keySize, prefix: true)
        let result = try tree.remove(root, width: keySize, key: key)
        root = result.0
        return result.1
    }

    /// Returns the stored key that prefixes the query, with its unused suffix.
    /// Exact lookup remains exact; this API explicitly performs prefix matching.
    public func prefixMatch(_ query: [Bit]) throws -> (key: [Bit], value: CellSlice, remainder: [Bit])? {
        guard var current = root else { return nil }
        var remaining = query
        var path = [Bit]()
        var width = keySize
        while true {
            let node = try tree.parse(current, width: width)
            guard remaining.starts(with: node.label) else { return nil }
            remaining.removeFirst(node.label.count)
            path += node.label
            if node.leaf { return (path, node.body, remaining) }
            guard !remaining.isEmpty else { return nil }
            let bit = remaining.removeFirst()
            path.append(bit)
            width -= node.label.count + 1
            current = node.body.refs[Int(bit.rawValue)]
        }
    }

    @discardableResult
    public func iterate(_ body: ([Bit], CellSlice) throws -> Bool) throws -> Bool {
        try tree.iterate(root, width: keySize, body)
    }

    public func cell() throws -> Cell { try CellBuilder().storeMaybeRef(root).cell() }
    public func write(to builder: CellBuilder) throws { try builder.storeSlice(cell().parse()) }

    public static func read(from slice: CellSlice, keySize: Int) throws -> Self {
        if let source = slice.sourceCell, source.isExotic {
            throw ErrorTonSdkSwift("Dictionary decoding requires an ordinary source cell")
        }
        let cursor = CellSlice(bits: slice.bits, refs: slice.refs)
        let result = try Self(keySize: keySize, root: cursor.loadMaybeRef())
        slice.bits = cursor.bits; slice.refs = cursor.refs
        return result
    }

    public func writeRoot(to builder: CellBuilder) throws {
        guard let root, !root.isExotic else { throw ErrorTonSdkSwift("An inline prefix root must be nonempty and ordinary") }
        try builder.storeSlice(root.parse())
    }

    public static func readRoot(from slice: CellSlice, keySize: Int) throws -> Self {
        try DictionaryLabel.validateWidth(keySize)
        if let source = slice.sourceCell, source.isExotic {
            throw ErrorTonSdkSwift("Dictionary decoding requires an ordinary source cell")
        }
        let cursor = CellSlice(bits: slice.bits, refs: slice.refs)
        let label = try DictionaryLabel.read(from: cursor, maximum: keySize)
        let leaf = try cursor.loadBit() == .b0
        if leaf { cursor.bits = []; cursor.refs = [] }
        else {
            guard label.count < keySize else { throw ErrorTonSdkSwift("Prefix fork exceeds key width") }
            try cursor.skipRefs(size: 2)
        }
        let root = try Cell(bits: Array(slice.bits.prefix(slice.bits.count - cursor.bits.count)),
                            refs: Array(slice.refs.prefix(slice.refs.count - cursor.refs.count)))
        let result = try Self(keySize: keySize, root: root)
        slice.bits = cursor.bits; slice.refs = cursor.refs
        return result
    }
}
