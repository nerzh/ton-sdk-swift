// Original SDK implementation of TON HashmapAug/HashmapAugE.

/// Supplies the schema of an augmentation. Decode must consume exactly its own
/// bits/references; encode must return an ordinary cell. Combine receives the
/// left subtree first and the right subtree second, including noncommutative
/// aggregations. Callbacks must not mutate cells or external shared state.
public struct DictionaryAugmentation<Extra> {
    public let empty: () throws -> Extra
    public let decode: (CellSlice) throws -> Extra
    public let encode: (Extra) throws -> Cell
    public let combine: (Extra, Extra) throws -> Extra

    public init(empty: @escaping () throws -> Extra,
                decode: @escaping (CellSlice) throws -> Extra,
                encode: @escaping (Extra) throws -> Cell,
                combine: @escaping (Extra, Extra) throws -> Extra) {
        self.empty = empty
        self.decode = decode
        self.encode = encode
        self.combine = combine
    }
}

/// Persistent augmented dictionary with explicit leaf extras. Extras are kept
/// encoded, so mutable Extra objects never become shared dictionary storage.
/// Leaves contain extra then value. Forks contain two child references followed
/// by the extra's references. Every successful mutation refreshes root extra.
public struct HashmapAugE<Extra> {
    public let keySize: Int
    public let augmentation: DictionaryAugmentation<Extra>
    public private(set) var root: Cell?
    private var encodedExtra: Cell
    public var isEmpty: Bool { root == nil }

    public init(keySize: Int, root: Cell? = nil, augmentation: DictionaryAugmentation<Extra>) throws {
        try DictionaryLabel.validateWidth(keySize)
        self.keySize = keySize
        self.augmentation = augmentation
        self.root = root
        encodedExtra = try Self.encode(augmentation.empty(), using: augmentation)
        if let root { encodedExtra = try extraCell(in: root, width: keySize) }
    }

    private init(keySize: Int, root: Cell?, encodedExtra: Cell, augmentation: DictionaryAugmentation<Extra>) {
        self.keySize = keySize
        self.root = root
        self.encodedExtra = encodedExtra
        self.augmentation = augmentation
    }

    public func rootExtra() throws -> Extra { try augmentation.decode(encodedExtra.parse()) }

    private static func encode(_ extra: Extra, using codec: DictionaryAugmentation<Extra>) throws -> Cell {
        let encoded = try codec.encode(extra)
        guard !encoded.isExotic else { throw ErrorTonSdkSwift("Dictionary augmentation must encode an ordinary cell") }
        // Decode once to reject codecs that produce trailing bits/references.
        let slice = encoded.parse()
        _ = try codec.decode(slice)
        guard slice.bits.isEmpty, slice.refs.isEmpty else {
            throw ErrorTonSdkSwift("Dictionary augmentation codec left trailing data")
        }
        return encoded
    }

    private var tree: DictionaryTree {
        DictionaryTree(prefix: false, forkExtra: { left, right, width in
            let l = try self.augmentation.decode(self.extraCell(in: left, width: width).parse())
            let r = try self.augmentation.decode(self.extraCell(in: right, width: width).parse())
            return try Self.encode(self.augmentation.combine(l, r), using: self.augmentation)
        })
    }

    private func extraCell(in cell: Cell, width: Int) throws -> Cell {
        // A dummy hook permits an augmented fork payload without computing it.
        let parser = DictionaryTree(prefix: false, forkExtra: { _, _, _ in try Cell() })
        let node = try parser.parse(cell, width: width)
        if !node.leaf { try node.body.skipRefs(size: 2) }
        let bits = node.body.bits, refs = node.body.refs
        _ = try augmentation.decode(node.body)
        if !node.leaf && (!node.body.bits.isEmpty || !node.body.refs.isEmpty) {
            throw ErrorTonSdkSwift("Augmented fork has trailing data")
        }
        return try Cell(bits: Array(bits.prefix(bits.count - node.body.bits.count)),
                        refs: Array(refs.prefix(refs.count - node.body.refs.count)))
    }

    public func get(_ key: [Bit]) throws -> (value: CellSlice, extra: Extra)? {
        try DictionaryLabel.validateKey(key, width: keySize)
        guard let value = try tree.get(root, width: keySize, key: key) else { return nil }
        let extra = try augmentation.decode(value)
        return (value, extra)
    }

    @discardableResult
    public mutating func set(_ key: [Bit], value: CellSlice, extra: Extra) throws -> CellSlice? {
        try update(key, value: value, extra: extra, mode: .set)
    }

    @discardableResult
    public mutating func add(_ key: [Bit], value: CellSlice, extra: Extra) throws -> CellSlice? {
        try update(key, value: value, extra: extra, mode: .add)
    }

    @discardableResult
    public mutating func replace(_ key: [Bit], value: CellSlice, extra: Extra) throws -> CellSlice? {
        try update(key, value: value, extra: extra, mode: .replace)
    }

    private mutating func update(_ key: [Bit], value: CellSlice, extra: Extra, mode: DictionaryTree.Mode) throws -> CellSlice? {
        try DictionaryLabel.validateKey(key, width: keySize)
        let encoded = try Self.encode(extra, using: augmentation)
        let payload = try CellBuilder().storeSlice(encoded.parse()).storeSlice(value).cell()
        let result = try tree.update(root, width: keySize, key: key, value: payload.parse(), mode: mode)
        let nextExtra = try result.0.map { try extraCell(in: $0, width: keySize) } ?? encodedExtra
        if let previous = result.1 { _ = try augmentation.decode(previous) }
        root = result.0
        encodedExtra = nextExtra
        return result.1
    }

    @discardableResult
    public mutating func remove(_ key: [Bit]) throws -> CellSlice? {
        try DictionaryLabel.validateKey(key, width: keySize)
        let result = try tree.remove(root, width: keySize, key: key)
        let nextExtra = try result.0.map { try extraCell(in: $0, width: keySize) }
            ?? Self.encode(augmentation.empty(), using: augmentation)
        if let previous = result.1 { _ = try augmentation.decode(previous) }
        root = result.0
        encodedExtra = nextExtra
        return result.1
    }

    @discardableResult
    public func iterate(_ body: ([Bit], CellSlice, Extra) throws -> Bool) throws -> Bool {
        try tree.iterate(root, width: keySize) { key, cursor in
            let extra = try augmentation.decode(cursor)
            return try body(key, cursor, extra)
        }
    }

    /// Filters atomically and recomputes every changed fork extra.
    public mutating func filter(_ keep: ([Bit], CellSlice, Extra) throws -> Bool) throws {
        var staged = self
        try iterate { key, value, extra in
            if try !keep(key, value, extra) { try staged.remove(key) }
            return true
        }
        self = staged
    }

    public func cell() throws -> Cell {
        try CellBuilder().storeMaybeRef(root).storeSlice(encodedExtra.parse()).cell()
    }

    public func write(to builder: CellBuilder) throws { try builder.storeSlice(cell().parse()) }

    /// Decodes an envelope without opening its root. An empty extra must equal
    /// the encoded default. A nonempty envelope's extra is retained verbatim;
    /// call validateAugmentation to verify it against all visible descendants.
    public static func read(from slice: CellSlice, keySize: Int,
                            augmentation: DictionaryAugmentation<Extra>) throws -> Self {
        try DictionaryLabel.validateWidth(keySize)
        if let source = slice.sourceCell, source.isExotic {
            throw ErrorTonSdkSwift("Dictionary decoding requires an ordinary source cell")
        }
        let cursor = CellSlice(bits: slice.bits, refs: slice.refs)
        let root = try cursor.loadMaybeRef()
        let bits = cursor.bits, refs = cursor.refs
        _ = try augmentation.decode(cursor)
        let extra = try Cell(bits: Array(bits.prefix(bits.count - cursor.bits.count)),
                             refs: Array(refs.prefix(refs.count - cursor.refs.count)))
        if root == nil {
            let expected = try Self.encode(augmentation.empty(), using: augmentation)
            guard extra == expected else { throw ErrorTonSdkSwift("Nondefault augmentation for an empty dictionary") }
        }
        let result = Self(keySize: keySize, root: root, encodedExtra: extra, augmentation: augmentation)
        slice.bits = cursor.bits; slice.refs = cursor.refs
        return result
    }

    public func writeRoot(to builder: CellBuilder) throws {
        guard let root, !root.isExotic else { throw ErrorTonSdkSwift("An inline augmented root must be nonempty and ordinary") }
        try builder.storeSlice(root.parse())
    }

    /// Reads an inline root. At a leaf the untyped value consumes the remaining
    /// slice; at a fork only label, two child refs and the schema's extra are read.
    public static func readRoot(from slice: CellSlice, keySize: Int,
                                augmentation: DictionaryAugmentation<Extra>) throws -> Self {
        try DictionaryLabel.validateWidth(keySize)
        if let source = slice.sourceCell, source.isExotic {
            throw ErrorTonSdkSwift("Dictionary decoding requires an ordinary source cell")
        }
        let cursor = CellSlice(bits: slice.bits, refs: slice.refs)
        let label = try DictionaryLabel.read(from: cursor, maximum: keySize)
        if label.count == keySize {
            cursor.bits = []; cursor.refs = []
        } else {
            try cursor.skipRefs(size: 2)
            _ = try augmentation.decode(cursor)
        }
        let root = try Cell(bits: Array(slice.bits.prefix(slice.bits.count - cursor.bits.count)),
                            refs: Array(slice.refs.prefix(slice.refs.count - cursor.refs.count)))
        let result = try Self(keySize: keySize, root: root, augmentation: augmentation)
        slice.bits = cursor.bits; slice.refs = cursor.refs
        return result
    }

    /// Validates stored fork aggregation and the envelope extra. Leaf extras are
    /// supplied by the caller's value schema and cannot be inferred here.
    public func validateAugmentation() throws {
        func visit(_ cell: Cell, width: Int) throws -> Cell {
            let node = try tree.parse(cell, width: width)
            let actual = try extraCell(in: cell, width: width)
            if node.leaf { return actual }
            let childWidth = width - node.label.count - 1
            let left = try augmentation.decode(visit(node.body.refs[0], width: childWidth).parse())
            let right = try augmentation.decode(visit(node.body.refs[1], width: childWidth).parse())
            let expected = try Self.encode(augmentation.combine(left, right), using: augmentation)
            guard actual == expected else { throw ErrorTonSdkSwift("Invalid dictionary fork augmentation") }
            return actual
        }
        let actual = try root.map { try visit($0, width: keySize) }
            ?? Self.encode(augmentation.empty(), using: augmentation)
        guard actual == encodedExtra else { throw ErrorTonSdkSwift("Invalid dictionary envelope augmentation") }
    }
}
