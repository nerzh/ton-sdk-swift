// Original SDK implementation of the TON TL-B dictionary schemas.
// Schema: https://github.com/ton-blockchain/ton/blob/master/crypto/block/block.tlb
import BigInt

/// Shared bounded label codec. All valid encodings are accepted; new labels use
/// the shortest encoding, breaking ties in short/long/same constructor order.
enum DictionaryLabel {
    static func validateWidth(_ width: Int) throws {
        guard (0...1023).contains(width) else {
            throw ErrorTonSdkSwift("Dictionary key width must be in 0...1023")
        }
    }

    static func validateKey(_ key: [Bit], width: Int, prefix: Bool = false) throws {
        try validateWidth(width)
        guard prefix ? key.count <= width : key.count == width else {
            throw ErrorTonSdkSwift("Dictionary key width \(key.count) does not match \(width)")
        }
    }

    static func lengthWidth(_ maximum: Int) -> Int {
        maximum == 0 ? 0 : Int.bitWidth - maximum.leadingZeroBitCount
    }

    static func commonPrefix(_ lhs: [Bit], _ rhs: [Bit]) -> Int {
        var count = 0
        while count < min(lhs.count, rhs.count), lhs[count] == rhs[count] { count += 1 }
        return count
    }

    static func write(_ label: [Bit], maximum: Int, to builder: CellBuilder) throws {
        try validateWidth(maximum)
        guard label.count <= maximum else { throw ErrorTonSdkSwift("Oversized dictionary label") }
        let width = lengthWidth(maximum)
        let shortCost = 2 * label.count + 2
        let longCost = 2 + width + label.count
        let sameCost = 3 + width
        let repeated = label.first.map { bit in label.allSatisfy { $0 == bit } } ?? false
        if shortCost <= longCost && (!repeated || shortCost <= sameCost) {
            try builder.storeBit(.b0).storeBits(Array(repeating: .b1, count: label.count))
                .storeBit(.b0).storeBits(label)
        } else if !repeated || longCost <= sameCost {
            try builder.storeBits([.b1, .b0]).storeUInt(BigUInt(label.count), width).storeBits(label)
        } else {
            try builder.storeBits([.b1, .b1, label[0]]).storeUInt(BigUInt(label.count), width)
        }
    }

    static func read(from slice: CellSlice, maximum: Int) throws -> [Bit] {
        try validateWidth(maximum)
        let length: Int
        if try slice.loadBit() == .b0 {
            var unary = 0
            while try slice.loadBit() == .b1 {
                unary += 1
                guard unary <= maximum else { throw ErrorTonSdkSwift("Oversized short dictionary label") }
            }
            return try slice.loadBits(size: unary)
        }
        let same = try slice.loadBit() == .b1
        let repeated = same ? try slice.loadBit() : .b0
        length = Int(try slice.loadBigUInt(size: lengthWidth(maximum)))
        guard length <= maximum else { throw ErrorTonSdkSwift("Oversized dictionary label") }
        return same ? Array(repeating: repeated, count: length) : try slice.loadBits(size: length)
    }
}

/// The immutable tree machinery shared by ordinary, augmented and prefix maps.
/// A mutation returns a proposed root; callers publish it only after all work succeeds.
struct DictionaryTree {
    let prefix: Bool
    /// Returns the encoded augmentation for a newly constructed fork. It must
    /// inspect only the child extras, and combine left before right.
    var forkExtra: ((_ left: Cell, _ right: Cell, _ width: Int) throws -> Cell)? = nil

    struct Node {
        var label: [Bit]
        var leaf: Bool
        var body: CellSlice
        var header: [Bit]
    }

    enum Mode { case set, add, replace }

    func parse(_ cell: Cell, width: Int) throws -> Node {
        guard !cell.isExotic else { throw ErrorTonSdkSwift("Dictionary access requires an ordinary cell") }
        let slice = cell.parse()
        let label = try DictionaryLabel.read(from: slice, maximum: width)
        let leaf = prefix ? try slice.loadBit() == .b0 : label.count == width
        let header = Array(cell.bits.prefix(cell.bits.count - slice.bits.count))
        if !leaf {
            guard label.count < width, slice.refs.count >= 2 else {
                throw ErrorTonSdkSwift("Invalid dictionary fork")
            }
            if forkExtra == nil {
                guard slice.bits.isEmpty, slice.refs.count == 2 else {
                    throw ErrorTonSdkSwift("Unexpected dictionary fork payload")
                }
            }
        }
        return Node(label: label, leaf: leaf, body: slice, header: header)
    }

    func edge(_ label: [Bit], width: Int, leaf: Bool, body: CellSlice) throws -> Cell {
        let builder = CellBuilder()
        try DictionaryLabel.write(label, maximum: width, to: builder)
        if prefix { try builder.storeBit(leaf ? .b0 : .b1) }
        return try builder.storeSlice(body).cell()
    }

    func forkBody(_ left: Cell, _ right: Cell, width: Int) throws -> CellSlice {
        let builder = try CellBuilder().storeRefs([left, right])
        if let forkExtra { try builder.storeSlice(forkExtra(left, right, width).parse()) }
        return try builder.cell().parse()
    }

    func get(_ root: Cell?, width: Int, key: [Bit]) throws -> CellSlice? {
        guard var cell = root else { return nil }
        var remaining = key
        var width = width
        while true {
            let node = try parse(cell, width: width)
            guard remaining.starts(with: node.label) else { return nil }
            remaining.removeFirst(node.label.count)
            if node.leaf { return remaining.isEmpty ? node.body : nil }
            guard !remaining.isEmpty else { return nil }
            let direction = Int(remaining.removeFirst().rawValue)
            width -= node.label.count + 1
            cell = node.body.refs[direction]
        }
    }

    func update(_ root: Cell?, width: Int, key: [Bit], value: CellSlice, mode: Mode) throws -> (Cell?, CellSlice?) {
        guard let root else {
            return mode == .replace ? (nil, nil) : (try edge(key, width: width, leaf: true, body: value), nil)
        }
        let node = try parse(root, width: width)
        let common = DictionaryLabel.commonPrefix(node.label, key)
        if common < node.label.count {
            if mode == .replace { return (root, nil) }
            guard common < key.count else { throw ErrorTonSdkSwift("Prefix dictionary keys must form a prefix code") }
            let childWidth = width - common - 1
            let existing = try edge(Array(node.label.dropFirst(common + 1)), width: childWidth, leaf: node.leaf, body: node.body)
            let added = try edge(Array(key.dropFirst(common + 1)), width: childWidth, leaf: true, body: value)
            let left = key[common] == .b0 ? added : existing
            let right = key[common] == .b0 ? existing : added
            let body = try forkBody(left, right, width: childWidth)
            return (try edge(Array(key.prefix(common)), width: width, leaf: false, body: body), nil)
        }
        let suffix = Array(key.dropFirst(common))
        if node.leaf {
            guard suffix.isEmpty else {
                if mode == .replace { return (root, nil) }
                throw ErrorTonSdkSwift("Prefix dictionary keys must form a prefix code")
            }
            if mode == .add || (node.body.bits == value.bits && node.body.refs == value.refs) {
                return (root, node.body)
            }
            return (try CellBuilder().storeBits(node.header).storeSlice(value).cell(), node.body)
        }
        guard let directionBit = suffix.first else {
            if mode == .replace { return (root, nil) }
            throw ErrorTonSdkSwift("Prefix dictionary keys must form a prefix code")
        }
        let direction = Int(directionBit.rawValue)
        let childWidth = width - common - 1
        let result = try update(node.body.refs[direction], width: childWidth, key: Array(suffix.dropFirst()), value: value, mode: mode)
        guard let child = result.0 else { throw ErrorTonSdkSwift("Missing updated dictionary child") }
        if child === node.body.refs[direction] { return (root, result.1) }
        var children = Array(node.body.refs.prefix(2))
        children[direction] = child
        let body = try forkBody(children[0], children[1], width: childWidth)
        return (try CellBuilder().storeBits(node.header).storeSlice(body).cell(), result.1)
    }

    func remove(_ root: Cell?, width: Int, key: [Bit]) throws -> (Cell?, CellSlice?) {
        guard let root else { return (nil, nil) }
        let node = try parse(root, width: width)
        guard key.starts(with: node.label) else { return (root, nil) }
        let suffix = Array(key.dropFirst(node.label.count))
        if node.leaf { return suffix.isEmpty ? (nil, node.body) : (root, nil) }
        guard let bit = suffix.first else { return (root, nil) }
        let direction = Int(bit.rawValue)
        let childWidth = width - node.label.count - 1
        let result = try remove(node.body.refs[direction], width: childWidth, key: Array(suffix.dropFirst()))
        guard result.1 != nil else { return (root, nil) }
        if let child = result.0 {
            var children = Array(node.body.refs.prefix(2))
            children[direction] = child
            let body = try forkBody(children[0], children[1], width: childWidth)
            return (try CellBuilder().storeBits(node.header).storeSlice(body).cell(), result.1)
        }
        let sibling = try parse(node.body.refs[1 - direction], width: childWidth)
        let siblingBit: Bit = bit == .b0 ? .b1 : .b0
        let merged = node.label + [siblingBit] + sibling.label
        return (try edge(merged, width: width, leaf: sibling.leaf, body: sibling.body), result.1)
    }

    func iterate(_ root: Cell?, width: Int, path: [Bit] = [], _ body: ([Bit], CellSlice) throws -> Bool) throws -> Bool {
        guard let root else { return true }
        let node = try parse(root, width: width)
        let key = path + node.label
        if node.leaf { return try body(key, node.body) }
        let childWidth = width - node.label.count - 1
        return try iterate(node.body.refs[0], width: childWidth, path: key + [.b0], body)
            && iterate(node.body.refs[1], width: childWidth, path: key + [.b1], body)
    }
}
