// Original SDK implementation of TON Hashmap/HashmapE.

/// A persistent fixed-width dictionary that preserves original cell encodings.
/// Raw roots and envelopes are accepted lazily. Accessing a pruned or malformed
/// path throws; unvisited branches remain opaque. Mutations are atomic.
public struct RawHashmap {
    public let keySize: Int
    public private(set) var root: Cell?
    private var tree: DictionaryTree { DictionaryTree(prefix: false) }
    public var isEmpty: Bool { root == nil }

    public init(keySize: Int, root: Cell? = nil) throws {
        try DictionaryLabel.validateWidth(keySize)
        self.keySize = keySize
        self.root = root
    }

    public func get(_ key: [Bit]) throws -> CellSlice? {
        try DictionaryLabel.validateKey(key, width: keySize)
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
        try DictionaryLabel.validateKey(key, width: keySize)
        let result = try tree.update(root, width: keySize, key: key, value: value, mode: mode)
        root = result.0
        return result.1
    }

    @discardableResult
    public mutating func remove(_ key: [Bit]) throws -> CellSlice? {
        try DictionaryLabel.validateKey(key, width: keySize)
        let result = try tree.remove(root, width: keySize, key: key)
        root = result.0
        return result.1
    }

    /// Visits entries in unsigned ascending bit order. False stops before opening
    /// any later branch, including pruned siblings. Each value is a fresh cursor.
    @discardableResult
    public func iterate(_ body: ([Bit], CellSlice) throws -> Bool) throws -> Bool {
        try tree.iterate(root, width: keySize, body)
    }

    public func count() throws -> Int {
        var result = 0
        try iterate { _, _ in result += 1; return true }
        return result
    }

    /// A throwing lazy iterator; failures leave the failing item pending.
    public struct Iterator {
        private var pending: [(Cell, Int, [Bit])]
        fileprivate init(root: Cell?, width: Int) { pending = root.map { [($0, width, [])] } ?? [] }
        public mutating func next() throws -> (key: [Bit], value: CellSlice)? {
            let tree = DictionaryTree(prefix: false)
            while let (cell, width, path) = pending.last {
                let node = try tree.parse(cell, width: width)
                pending.removeLast()
                let key = path + node.label
                if node.leaf { return (key, node.body) }
                let nextWidth = width - node.label.count - 1
                pending.append((node.body.refs[1], nextWidth, key + [.b1]))
                pending.append((node.body.refs[0], nextWidth, key + [.b0]))
            }
            return nil
        }
    }

    public func makeIterator() -> Iterator { Iterator(root: root, width: keySize) }

    public func minimum() throws -> (key: [Bit], value: CellSlice)? {
        var iterator = makeIterator()
        return try iterator.next()
    }

    public func maximum() throws -> (key: [Bit], value: CellSlice)? {
        guard var cell = root else { return nil }
        var path = [Bit]()
        var width = keySize
        while true {
            let node = try tree.parse(cell, width: width)
            path += node.label
            if node.leaf { return (path, node.body) }
            path.append(.b1)
            width -= node.label.count + 1
            cell = node.body.refs[1]
        }
    }

    /// Unsigned successor/predecessor, optionally including an equal key.
    public func find(_ key: [Bit], next: Bool = true, inclusive: Bool = false) throws -> (key: [Bit], value: CellSlice)? {
        try DictionaryLabel.validateKey(key, width: keySize)
        func search(_ cell: Cell, _ width: Int, _ path: [Bit]) throws -> (key: [Bit], value: CellSlice)? {
            // The known path can rule out a whole opaque subtree before its
            // cell is opened (important for pruned neighbor searches).
            let pathLower = path + Array(repeating: Bit.b0, count: keySize - path.count)
            let pathUpper = path + Array(repeating: Bit.b1, count: keySize - path.count)
            if next && (pathUpper.lexicographicallyPrecedes(key) || (!inclusive && pathUpper == key)) { return nil }
            if !next && (key.lexicographicallyPrecedes(pathLower) || (!inclusive && pathLower == key)) { return nil }
            let node = try tree.parse(cell, width: width)
            let prefix = path + node.label
            let lower = prefix + Array(repeating: Bit.b0, count: keySize - prefix.count)
            let upper = prefix + Array(repeating: Bit.b1, count: keySize - prefix.count)
            if next && (upper.lexicographicallyPrecedes(key) || (!inclusive && upper == key)) { return nil }
            if !next && (key.lexicographicallyPrecedes(lower) || (!inclusive && lower == key)) { return nil }
            if node.leaf { return (prefix, node.body) }
            let first = next ? 0 : 1
            let childWidth = width - node.label.count - 1
            if let result = try search(node.body.refs[first], childWidth, prefix + [first == 0 ? .b0 : .b1]) { return result }
            return try search(node.body.refs[1 - first], childWidth, prefix + [first == 0 ? .b1 : .b0])
        }
        return try root.map { try search($0, keySize, []) } ?? nil
    }

    /// Returns only keys beginning with prefix; stripping it reduces keySize.
    /// Empty prefixes retain the original root without opening it.
    public func subtree(prefix: [Bit], strippingPrefix: Bool = false) throws -> RawHashmap {
        guard prefix.count <= keySize else { throw ErrorTonSdkSwift("Subtree prefix exceeds key width") }
        let outputWidth = strippingPrefix ? keySize - prefix.count : keySize
        if prefix.isEmpty { return self }
        var remaining = prefix
        var width = keySize
        var accumulated = [Bit]()
        var current = root
        while let cell = current {
            let node = try tree.parse(cell, width: width)
            let common = DictionaryLabel.commonPrefix(remaining, node.label)
            if common == remaining.count {
                let label = strippingPrefix ? Array(node.label.dropFirst(common)) : accumulated + node.label
                let output = try tree.edge(label, width: outputWidth, leaf: node.leaf, body: node.body)
                return try RawHashmap(keySize: outputWidth, root: output)
            }
            guard common == node.label.count, !node.leaf else { break }
            remaining.removeFirst(common)
            let bit = remaining.removeFirst()
            accumulated += node.label + [bit]
            width -= node.label.count + 1
            current = node.body.refs[Int(bit.rawValue)]
        }
        return try RawHashmap(keySize: outputWidth)
    }

    /// Transactional filtering. Accepted branches keep their original cells.
    public mutating func filter(_ keep: ([Bit], CellSlice) throws -> Bool) throws {
        func visit(_ cell: Cell, _ width: Int, _ path: [Bit]) throws -> Cell? {
            let node = try tree.parse(cell, width: width)
            let key = path + node.label
            if node.leaf { return try keep(key, node.body) ? cell : nil }
            let childWidth = width - node.label.count - 1
            let left = try visit(node.body.refs[0], childWidth, key + [.b0])
            let right = try visit(node.body.refs[1], childWidth, key + [.b1])
            if let left, let right {
                if left === node.body.refs[0] && right === node.body.refs[1] { return cell }
                return try Cell(bits: node.header, refs: [left, right])
            }
            guard let survivor = left ?? right else { return nil }
            let child = try tree.parse(survivor, width: childWidth)
            return try tree.edge(node.label + [left == nil ? .b1 : .b0] + child.label, width: width, leaf: child.leaf, body: child.body)
        }
        if let root { self.root = try visit(root, keySize, []) }
    }

    /// Combines disjoint entries or identical encoded values. Conflicts and
    /// traversal errors leave this dictionary unchanged.
    public mutating func combine(_ other: RawHashmap) throws {
        guard keySize == other.keySize else { throw ErrorTonSdkSwift("Dictionary widths differ") }
        func merge(_ a: Cell?, _ b: Cell?, _ width: Int) throws -> Cell? {
            if a == b || b == nil { return a }
            guard let a else { return b }
            guard let b else { return a }
            let left = try tree.parse(a, width: width)
            let right = try tree.parse(b, width: width)
            if left.label == right.label {
                if left.leaf {
                    guard left.body == right.body else { throw ErrorTonSdkSwift("Conflicting dictionary values") }
                    return a
                }
                let childWidth = width - left.label.count - 1
                let zero = try merge(left.body.refs[0], right.body.refs[0], childWidth)!
                let one = try merge(left.body.refs[1], right.body.refs[1], childWidth)!
                if zero === left.body.refs[0] && one === left.body.refs[1] { return a }
                return try Cell(bits: left.header, refs: [zero, one])
            }
            var staged = try RawHashmap(keySize: width, root: a)
            try tree.iterate(b, width: width) { key, value in
                if let old = try staged.get(key) {
                    guard old == value else { throw ErrorTonSdkSwift("Conflicting dictionary values") }
                } else { try staged.set(key, value: value) }
                return true
            }
            return staged.root
        }
        root = try merge(root, other.root, keySize)
    }

    /// Reports logical value differences in ascending order. Equal subtrees,
    /// including opaque pruned cells at aligned paths, are skipped unopened.
    @discardableResult
    public func scanDiff(_ other: RawHashmap, _ body: ([Bit], CellSlice?, CellSlice?) throws -> Bool) throws -> Bool {
        guard keySize == other.keySize else { throw ErrorTonSdkSwift("Dictionary widths differ") }
        func compare(_ a: Cell?, _ b: Cell?, width: Int, path: [Bit]) throws -> Bool {
            if a == b { return true }
            guard let a else {
                return try tree.iterate(b, width: width, path: path) { try body($0, nil, $1) }
            }
            guard let b else {
                return try tree.iterate(a, width: width, path: path) { try body($0, $1, nil) }
            }
            let lnode = try tree.parse(a, width: width)
            let rnode = try tree.parse(b, width: width)
            if lnode.label == rnode.label {
                let prefix = path + lnode.label
                if lnode.leaf { return lnode.body == rnode.body ? true : try body(prefix, lnode.body, rnode.body) }
                let childWidth = width - lnode.label.count - 1
                return try compare(lnode.body.refs[0], rnode.body.refs[0], width: childWidth, path: prefix + [.b0])
                    && compare(lnode.body.refs[1], rnode.body.refs[1], width: childWidth, path: prefix + [.b1])
            }
            // Differently compressed paths are merged by key while retaining
            // independent cursors and ascending callback order.
            var ai = Iterator(root: a, width: width), bi = Iterator(root: b, width: width)
            var left = try ai.next(), right = try bi.next()
            while left != nil || right != nil {
                if let l = left, let r = right, l.key == r.key {
                    if l.value != r.value, try !body(path + l.key, l.value, r.value) { return false }
                    left = try ai.next(); right = try bi.next()
                } else if let l = left, right == nil || l.key.lexicographicallyPrecedes(right!.key) {
                    if try !body(path + l.key, l.value, nil) { return false }
                    left = try ai.next()
                } else if let r = right {
                    if try !body(path + r.key, nil, r.value) { return false }
                    right = try bi.next()
                }
            }
            return true
        }
        return try compare(root, other.root, width: keySize, path: [])
    }

    public func write(to builder: CellBuilder) throws {
        let encoded = try CellBuilder().storeMaybeRef(root).cell()
        try builder.storeSlice(encoded.parse())
    }

    public func cell() throws -> Cell { try CellBuilder().storeMaybeRef(root).cell() }

    /// Consumes only the flag and optional root reference. Failed reads leave
    /// the supplied cursor unchanged.
    public static func read(from slice: CellSlice, keySize: Int) throws -> RawHashmap {
        if let source = slice.sourceCell, source.isExotic {
            throw ErrorTonSdkSwift("Dictionary decoding requires an ordinary source cell")
        }
        let cursor = CellSlice(bits: slice.bits, refs: slice.refs)
        let result = try RawHashmap(keySize: keySize, root: cursor.loadMaybeRef())
        slice.bits = cursor.bits
        slice.refs = cursor.refs
        return result
    }

    public func writeRoot(to builder: CellBuilder) throws {
        guard let root, !root.isExotic else { throw ErrorTonSdkSwift("An inline dictionary root must be nonempty and ordinary") }
        try builder.storeSlice(root.parse())
    }

    /// Fork roots consume their label and two references. Leaf roots consume
    /// the remaining slice because an untyped value has no known boundary.
    public static func readRoot(from slice: CellSlice, keySize: Int) throws -> RawHashmap {
        try DictionaryLabel.validateWidth(keySize)
        if let source = slice.sourceCell, source.isExotic {
            throw ErrorTonSdkSwift("Dictionary decoding requires an ordinary source cell")
        }
        let cursor = CellSlice(bits: slice.bits, refs: slice.refs)
        let label = try DictionaryLabel.read(from: cursor, maximum: keySize)
        let root: Cell
        if label.count == keySize {
            root = try Cell(bits: slice.bits, refs: slice.refs)
            cursor.bits = []; cursor.refs = []
        } else {
            let bits = Array(slice.bits.prefix(slice.bits.count - cursor.bits.count))
            let refs = [try cursor.loadRef(), try cursor.loadRef()]
            root = try Cell(bits: bits, refs: refs)
        }
        let result = try RawHashmap(keySize: keySize, root: root)
        slice.bits = cursor.bits; slice.refs = cursor.refs
        return result
    }
}
