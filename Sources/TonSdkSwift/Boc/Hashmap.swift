//
//  File.swift
//
//
//  Created by Oleh Hudeichuk on 28.02.2024.
//

import Foundation
import BigInt

public struct HashmapOptions<K, V> {
    /// When supplied, must match the dictionary initializer's explicit keySize.
    public var keySize: Int?
    @available(*, deprecated, message: "Prefix dictionaries are not supported by Hashmap")
    public var prefixed: Bool?
    @available(*, deprecated, message: "Use Hashmap for nonempty roots")
    public var nonEmpty: Bool?
    public var serializers: (key: (K) throws -> [Bit], value: (V) throws -> Cell)?
    public var deserializers: (key: ([Bit]) throws -> K, value: (Cell) throws -> V)?
    
    public init(keySize: Int? = nil, 
                prefixed: Bool? = nil,
                nonEmpty: Bool? = nil,
                serializers: (key: (K) throws -> [Bit], value: (V) throws -> Cell)? = nil,
                deserializers: (key: ([Bit]) throws -> K, value: (Cell) throws -> V)? = nil
    ) {
        self.keySize = keySize
        self.prefixed = prefixed
        self.nonEmpty = nonEmpty
        self.serializers = serializers
        self.deserializers = deserializers
    }
}

struct HashmapNode {
    var key: [Bit]
    var value: Cell
}

public struct LazyDeserialize<Element> {
    private let closure: () throws -> Element
    
    public init(closure: @escaping () throws -> Element) {
        self.closure = closure
    }
    
    public func deserialize() throws -> Element {
        try closure()
    }
}

open class Hashmap<K, V> {
    
    public var hashmap: [String: Cell] { didSet { preservedRoot = nil } }
    public var keySize: Int { didSet { preservedRoot = nil } }
    fileprivate var preservedRoot: Cell?
    public var serializeKey: (K) throws -> [Bit]
    public var serializeValue: (V) throws -> Cell
    public var deserializeKey: ([Bit]) throws -> K
    public var deserializeValue: (Cell) throws -> V
    
    public init(keySize: Int, options: HashmapOptions<K, V>? = nil) throws {
        try DictionaryLabel.validateWidth(keySize)
        if let optionWidth = options?.keySize, optionWidth != keySize {
            throw ErrorTonSdkSwift("Hashmap option keySize must match the explicit keySize")
        }
        guard options?.prefixed != true, options?.nonEmpty != true else {
            throw ErrorTonSdkSwift("Prefix dictionaries are not supported by Hashmap and Hashmap for nonempty roots")
        }
        let serializers: (key: (K) throws -> [Bit], value: (V) throws -> Cell) = options?.serializers ?? (key: { $0 as! [Bit] }, value: { $0 as! Cell })
        let deserializers: (key: ([Bit]) throws -> K, value: (Cell) throws -> V) = options?.deserializers ?? (key: { $0 as! K }, value: { $0 as! V })
        
        self.hashmap = [:]
        self.keySize = keySize
        self.serializeKey = serializers.key
        self.serializeValue = serializers.value
        self.deserializeKey = deserializers.key
        self.deserializeValue = deserializers.value
    }
    
    private convenience init(
        hashmap: [String : Cell],
        keySize: Int,
        serializeKey: @escaping (K) throws -> [Bit],
        serializeValue: @escaping (V) throws -> Cell,
        deserializeKey: @escaping ([Bit]) throws -> K,
        deserializeValue: @escaping (Cell) throws -> V
    ) throws {
        try self.init(
            keySize: keySize,
            options: .init(keySize: keySize,
                           prefixed: nil,
                           nonEmpty: nil,
                           serializers: (key: serializeKey, value: serializeValue),
                           deserializers: (key: deserializeKey, value: deserializeValue)
                          )
        )
        self.hashmap = hashmap
    }
    
    public func makeIterator() throws -> AnyIterator<(LazyDeserialize<K>, LazyDeserialize<V>)> {
        var iterator = try sortHashmap().makeIterator()
        
        return AnyIterator {
            guard let node = iterator.next() else { return nil }
            let key = LazyDeserialize(closure: { try self.deserializeKey(node.key) })
            let value = LazyDeserialize(closure: { try self.deserializeValue(node.value) })
            return (key, value)
        }
    }
    
    public func get(_ key: K) throws -> V? {
        let k = try checkedKey(key)
        guard let v = hashmap[k] else { return nil }
        return try deserializeValue(v)
    }
    
    public func has(_ key: K) throws -> Bool {
        try get(key) != nil
    }
    
    @discardableResult
    public func set(_ key: K, _ value: V) throws -> Self {
        let k = try checkedKey(key)
        let v = try serializeValue(value)
        hashmap[k] = v
        return self
    }
    
    @discardableResult
    public func add(_ key: K, _ value: V) throws -> Self {
        if try !has(key) {
            return try set(key, value)
        }
        return self
    }
    
    @discardableResult
    public func replace(_ key: K, _ value: V) throws -> Self {
        if try has(key) {
            return try set(key, value)
        }
        return self
    }
    
    public func getSet(_ key: K, _ value: V) throws -> V? {
        let prev = try get(key)
        try set(key, value)
        return prev
    }
    
    public func getAdd(_ key: K, _ value: V) throws -> V? {
        let prev = try get(key)
        try add(key, value)
        return prev
    }
    
    public func getReplace(_ key: K, _ value: V) throws -> V? {
        let prev = try get(key)
        try replace(key, value)
        return prev
    }
    
    public func delete(_ key: K) throws -> Self {
        let k = try checkedKey(key)
        hashmap.removeValue(forKey: k)
        return self
    }
    
    public func isEmpty() -> Bool {
        return hashmap.isEmpty
    }
    
    public func forEach(_ callbackfn: (LazyDeserialize<K>, LazyDeserialize<V>) throws -> Void) throws {
        for (key, value) in try self.makeIterator() {
            try callbackfn(key, value)
        }
    }
    
    public func getRaw(_ key: [Bit]) -> Cell? {
        guard key.count == keySize else { return nil }
        return hashmap[key.map { String($0) }.joined()]
    }
    
    /// Legacy nonthrowing insertion. Invalid key widths are ignored; use
    /// setRawChecked to receive a validation error.
    @discardableResult
    public func setRaw(_ key: [Bit], _ value: Cell) -> Self {
        guard key.count == keySize else { return self }
        hashmap[key.map { String($0) }.joined()] = value
        return self
    }

    @discardableResult
    public func setRawChecked(_ key: [Bit], _ value: Cell) throws -> Self {
        try DictionaryLabel.validateKey(key, width: keySize)
        return setRaw(key, value)
    }

    private func checkedKey(_ key: K) throws -> String {
        let bits = try serializeKey(key)
        try DictionaryLabel.validateKey(bits, width: keySize)
        return bits.map { String($0) }.joined()
    }

    fileprivate func sortHashmap() throws -> [HashmapNode] {
        try DictionaryLabel.validateWidth(keySize)
        return try hashmap.sorted { $0.key < $1.key }.map { entry in
            guard entry.key.count == keySize,
                  entry.key.allSatisfy({ $0 == "0" || $0 == "1" }) else {
                throw ErrorTonSdkSwift("Hashmap key has an invalid width or bit string")
            }
            return HashmapNode(key: entry.key.map { $0 == "0" ? .b0 : .b1 }, value: entry.value)
        }
    }

    public func buildMerkleProof(keys: [K]) throws -> Cell {
        var binaryKeys: [[Bit]] = .init()
        for (index, key) in keys.enumerated() {
            if try !self.has(key) {
                throw ErrorTonSdkSwift("Trying to generate merkle proof for a missing key at position: \(index)")
            }
            let serializedKey: [Bit] = try serializeKey(key)
            if serializedKey.count != keySize {
                throw ErrorTonSdkSwift("\(#function) \(#line) Serialized size is not equal to keySize")
            }
            binaryKeys.append(try serializeKey(key))
        }
        let encoded = try cell()
        let slice: CellSlice
        if self is HashmapE<K, V> {
            guard let root = encoded.refs.first else { throw ErrorTonSdkSwift("Cannot prove an empty dictionary") }
            slice = root.parse()
        } else {
            slice = encoded.parse()
        }
        return try processMerkleProof(prefix: [], slice: slice, n: keySize, keyBits: binaryKeys).toMerkleProof()
    }
    
    private func processMerkleProof(prefix: [Bit], slice: CellSlice, n: Int, keyBits: [[Bit]]) throws -> Cell {
        /// Reading label
        let originalCell: Cell = try CellBuilder().storeSlice(slice).cell()
        if keyBits.count == 0 {
            /// no keys to prove, prune the whole subdict
            return try originalCell.toPrunedBranch()
        }
        
        let lb0: Bit = try slice.loadBit()
        var prefixLength: Int = 0
        var pp: [Bit] = prefix
        
        if lb0 == .b0 {
            /// Short label detected

            /// Read
            prefixLength = try slice.loadUnaryLength()

            /// Read prefix
            for _ in 0..<prefixLength {
                try pp.append(slice.loadBit())
            }
        } else {
            let lb1: Bit = try slice.loadBit()
            
            if lb1 == .b0 {
                /// Long label detected
                prefixLength = try Int(slice.loadBigUInt(size: Int(ceil(log2(Double(n + 1))))))
                for _ in 0..<prefixLength {
                    try pp.append(slice.loadBit())
                }
            } else {
                /// Same label detected
                let bit: Bit = try slice.loadBit()
                prefixLength = try Int(slice.loadBigUInt(size: Int(ceil(log2(Double(n + 1))))))
                for _ in 0..<prefixLength {
                    pp.append(bit)
                }
            }
        }
        
        if n - prefixLength != 0 {
            let slice: CellSlice = originalCell.parse()
            var left: Cell = try slice.loadRef()
            var right: Cell = try slice.loadRef()
            /// NOTE: Left and right branches are implicitly contain prefixes '0' and '1'
            if (!left.isExotic) {
                let leftKeys = keyBits.filter { pp + [.b0] == $0.prefix(pp.count + 1) }
                left = try processMerkleProof(prefix: pp + [.b0], slice: left.parse(), n: n - prefixLength - 1, keyBits: leftKeys)
            }
            if (!right.isExotic) {
                let rightKeys = keyBits.filter { pp + [.b1] == $0.prefix(pp.count + 1) }
                right = try processMerkleProof(prefix: pp + [.b1], slice: right.parse(), n: n - prefixLength - 1, keyBits: rightKeys)
            }
            
            return try CellBuilder()
                .storeSlice(slice)
                .storeRef(left)
                .storeRef(right)
                .cell()
        }
        
        return originalCell
    }
    
    public func buildMerkleUpdate(key: K, newValue: V) throws -> Cell {
        let oldProof: Cell = try buildMerkleProof(keys: [key]).refs[0]
        let dict = try self.copy()
        try dict.set(key, newValue)
        let newProof: Cell = try dict.buildMerkleProof(keys: [key]).refs[0]
        return try Cell.toMerkleUpdate(c1: oldProof, c2: newProof)
    }
    
    fileprivate func serialize() throws -> Cell {
        if let preservedRoot { return preservedRoot }
        var nodes = try sortHashmap()
        guard !nodes.isEmpty else {
            throw ErrorTonSdkSwift("Hashmap: can't be empty. It must contain at least 1 key-value pair.")
        }
        
        return try Hashmap.serializeEdge(&nodes)
    }
    
    fileprivate static func serializeEdge(_ nodes: inout [HashmapNode]) throws -> Cell {
        guard !nodes.isEmpty else {
            throw ErrorTonSdkSwift("A nonempty dictionary cannot contain an empty edge")
        }

        let edge = CellBuilder()
        let label = try serializeLabel(&nodes)
        try edge.storeBits(label)
        
        // hmn_leaf#_
        if nodes.count == 1 {
            let leaf = serializeLeaf(node: nodes[0])
            try edge.storeSlice(leaf.slice())
        }
        
        // hmn_fork#_
        if nodes.count > 1 {

            var (leftNodes, rightNodes) = serializeFork(nodes: &nodes)
            
            let leftEdge = try serializeEdge(&leftNodes)
            try edge.storeRef(leftEdge)

            let rightEdge = try serializeEdge(&rightNodes)
            try edge.storeRef(rightEdge)
        }

        return try edge.cell()
    }
    
    fileprivate static func serializeLabel(_ nodes: inout [HashmapNode]) throws -> [Bit] {
        guard let first = nodes.first?.key, let last = nodes.last?.key else {
            throw ErrorTonSdkSwift("Cannot serialize an empty dictionary edge")
        }
        let length = DictionaryLabel.commonPrefix(first, last)
        let label = Array(first.prefix(length))
        let builder = CellBuilder()
        try DictionaryLabel.write(label, maximum: first.count, to: builder)
        for index in nodes.indices { nodes[index].key.removeFirst(length) }
        return builder.bits
    }

    fileprivate static func serializeFork(nodes: inout [HashmapNode]) -> ([HashmapNode], [HashmapNode]) {
        var leftNodes = [HashmapNode]()
        var rightNodes = [HashmapNode]()

        for (index, _) in nodes.enumerated() {
            if !nodes[index].key.isEmpty {
                let firstBit = nodes[index].key.removeFirst()
                if firstBit == .b0 {
                    leftNodes.append(.init(key: nodes[index].key, value: nodes[index].value))
                } else {
                    rightNodes.append(.init(key: nodes[index].key, value: nodes[index].value))
                }
            }
        }

        return (leftNodes, rightNodes)
    }

    fileprivate static func serializeLeaf(node: HashmapNode) -> Cell {
        node.value
    }
    
    public class func deserialize(
        keySize: Int,
        slice: CellSlice,
        options: HashmapOptions<K, V>?
    ) throws -> Hashmap<K, V> {
        if let source = slice.sourceCell, source.isExotic {
            throw ErrorTonSdkSwift("Dictionary decoding requires an ordinary source cell")
        }
        guard slice.bits.count >= 2 else {
            throw ErrorTonSdkSwift("Empty hashmap")
        }

        let hashmap = try Hashmap<K, V>(keySize: keySize, options: options)
        let originalRoot = try CellBuilder().storeSlice(slice).cell()
        let cursor = CellSlice(bits: slice.bits, refs: slice.refs)
        let nodes = try Self.deserializeEdge(cursor, keySize)

        for node in nodes {
            hashmap.setRaw(node.key, node.value)
        }

        hashmap.preservedRoot = originalRoot
        slice.bits = cursor.bits
        slice.refs = cursor.refs
        return hashmap
    }
    
    static func deserializeEdge(
        _ edge: CellSlice,
        _ keySize: Int,
        _ key: [Bit] = []
    ) throws -> [HashmapNode] {
        var nodes: [HashmapNode] = []
        var currentKey = key
        currentKey += try deserializeLabel(edge, keySize - currentKey.count)

        if currentKey.count == keySize {
            let value = try CellBuilder().storeSlice(edge).cell()
            return nodes + [.init(key: currentKey, value: value)]
        }

        guard edge.bits.isEmpty, edge.refs.count == 2 else {
            throw ErrorTonSdkSwift("Invalid dictionary fork")
        }
        for i in 0..<2 {
            let child = try edge.loadRef()
            guard !child.isExotic else { throw ErrorTonSdkSwift("Cannot eagerly decode an exotic dictionary edge") }
            let forkEdge = child.slice()
            let forkKey = currentKey + [try Bit(i)]

            nodes += try deserializeEdge(forkEdge, keySize, forkKey)
        }

        return nodes
    }

    public static func deserializeLabel(_ edge: CellSlice, _ m: Int) throws -> [Bit] {
        try DictionaryLabel.read(from: edge, maximum: m)
    }

    public static func deserializeLabelShort(_ edge: CellSlice) throws -> [Bit] {
        guard let zeroIndex = edge.bits.firstIndex(of: .b0) else {
            throw ErrorTonSdkSwift("Invalid Label")
        }
        let length = zeroIndex
        try edge.skip(size: length + 1)
        
        return try edge.loadBits(size: length)
    }

    public static func deserializeLabelLong(_ edge: CellSlice, _ m: Int) throws -> [Bit] {
        try DictionaryLabel.validateWidth(m)
        let length = Int(try edge.loadBigUInt(size: DictionaryLabel.lengthWidth(m)))
        guard length <= m else { throw ErrorTonSdkSwift("Invalid dictionary label length") }
        return try edge.loadBits(size: length)
    }

    public static func deserializeLabelSame(_ edge: CellSlice, _ m: Int) throws -> [Bit] {
        try DictionaryLabel.validateWidth(m)
        let repeated = try edge.loadBit()
        let length = Int(try edge.loadBigUInt(size: DictionaryLabel.lengthWidth(m)))
        guard length <= m else { throw ErrorTonSdkSwift("Invalid dictionary label length") }
        return Array(repeating: repeated, count: length)
    }

    public func cell() throws -> Cell {
        try serialize()
    }
    
    public func copy() throws -> Hashmap {
        let result = try Hashmap(
            hashmap: hashmap,
            keySize: keySize,
            serializeKey: serializeKey,
            serializeValue: serializeValue,
            deserializeKey: deserializeKey,
            deserializeValue: deserializeValue
        )
        result.preservedRoot = preservedRoot
        return result
    }

    public class func parse(
        keySize: Int,
        slice: CellSlice,
        options: HashmapOptions<K, V>? = nil
    ) throws -> Hashmap<K, V> {
        try deserialize(keySize: keySize, slice: slice, options: options)
    }
}



open class HashmapE<K, V>: Hashmap<K, V> {
    
    public override init(keySize: Int, options: HashmapOptions<K, V>? = nil) throws {
        try super.init(keySize: keySize, options: options)
    }
    
    private convenience init(
        hashmap: [String : Cell],
        keySize: Int,
        serializeKey: @escaping (K) throws -> [Bit],
        serializeValue: @escaping (V) throws -> Cell,
        deserializeKey: @escaping ([Bit]) throws -> K,
        deserializeValue: @escaping (Cell) throws -> V
    ) throws {
        try self.init(
            keySize: keySize,
            options: .init(keySize: keySize,
                           prefixed: nil,
                           nonEmpty: nil,
                           serializers: (key: serializeKey, value: serializeValue),
                           deserializers: (key: deserializeKey, value: deserializeValue)
                          )
        )
        self.hashmap = hashmap
    }
    
    public override func serialize() throws -> Cell {
        if let preservedRoot {
            return try CellBuilder().storeBit(.b1).storeRef(preservedRoot).cell()
        }
        var nodes = try sortHashmap()
        let result = CellBuilder()

        if nodes.isEmpty {
            return try result
                .storeBit(.b0)
                .cell()
        }

        return try result
            .storeBit(.b1)
            .storeRef(try HashmapE.serializeEdge(&nodes))
            .cell()
    }

    public override class func deserialize(
        keySize: Int,
        slice: CellSlice,
        options: HashmapOptions<K, V>? = nil
    ) throws -> HashmapE<K, V> {
        if let source = slice.sourceCell, source.isExotic {
            throw ErrorTonSdkSwift("Dictionary decoding requires an ordinary source cell")
        }
        guard !slice.bits.isEmpty else {
            throw ErrorTonSdkSwift("bad hashmap size flag")
        }
        
        let hashmap = try HashmapE<K, V>(keySize: keySize, options: options)
        let cursor = CellSlice(bits: slice.bits, refs: slice.refs)
        if try cursor.loadBit() == .b0 {
            slice.bits = cursor.bits
            return hashmap
        }

        let originalRoot = try cursor.loadRef()
        guard !originalRoot.isExotic else { throw ErrorTonSdkSwift("Cannot eagerly decode an exotic dictionary root") }
        let edge = originalRoot.slice()
        let nodes = try Hashmap<K, V>.deserializeEdge(edge, keySize)

        for node in nodes {
            hashmap.setRaw(node.key, node.value)
        }

        hashmap.preservedRoot = originalRoot
        slice.bits = cursor.bits
        slice.refs = cursor.refs
        return hashmap
    }

    public override class func parse(
        keySize: Int,
        slice: CellSlice,
        options: HashmapOptions<K, V>? = nil
    ) throws -> HashmapE<K, V> {
        try deserialize(keySize: keySize, slice: slice, options: options)
    }
    
    public override func copy() throws -> HashmapE {
        let result = try HashmapE(
            hashmap: hashmap,
            keySize: keySize,
            serializeKey: serializeKey,
            serializeValue: serializeValue,
            deserializeKey: deserializeKey,
            deserializeValue: deserializeValue
        )
        result.preservedRoot = preservedRoot
        return result
    }
}
