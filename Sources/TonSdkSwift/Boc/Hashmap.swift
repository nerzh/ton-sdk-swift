//
//  File.swift
//
//
//  Created by Oleh Hudeichuk on 28.02.2024.
//

import Foundation
import BigInt

public struct HashmapOptions<K, V> {
    public var keySize: Int?
    public var prefixed: Bool?
    public var nonEmpty: Bool?
    public var serializers: (key: (K) throws -> [Bit], value: (V) throws -> Cell)?
    public var deserializers: (key: ([Bit]) throws -> K, value: (Cell) throws -> V)?
    
    public init(keySize: Int? = nil, prefixed: Bool? = nil, nonEmpty: Bool? = nil, serializers: (key: (K) throws -> [Bit], value: (V) throws -> Cell)? = nil, deserializers: (key: ([Bit]) throws -> K, value: (Cell) throws -> V)? = nil) {
        self.keySize = keySize
        self.prefixed = prefixed
        self.nonEmpty = nonEmpty
        self.serializers = serializers
        self.deserializers = deserializers
    }
}

typealias HashmapNode = (key: [Bit], value: Cell)

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
    public var hashmap: [String: Cell]
    public var keySize: Int
    public var serializeKey: (K) throws -> [Bit]
    public var serializeValue: (V) throws -> Cell
    public var deserializeKey: ([Bit]) throws -> K
    public var deserializeValue: (Cell) throws -> V
    
    public init(keySize: Int, options: HashmapOptions<K, V>? = nil) throws {
        let serializers: (key: (K) throws -> [Bit], value: (V) throws -> Cell) = options?.serializers ?? (key: { $0 as! [Bit] }, value: { $0 as! Cell })
        let deserializers: (key: ([Bit]) throws -> K, value: (Cell) throws -> V) = options?.deserializers ?? (key: { $0 as! K }, value: { $0 as! V })
        
        self.hashmap = [:]
        self.keySize = keySize
        self.serializeKey = serializers.key
        self.serializeValue = serializers.value
        self.deserializeKey = deserializers.key
        self.deserializeValue = deserializers.value
    }
    
    public func makeIterator() throws -> AnyIterator<(LazyDeserialize<K>, LazyDeserialize<V>)> {
        var iterator = hashmap.makeIterator()
        
        return AnyIterator {
            guard let (k, v) = iterator.next() else { return nil }
            let key = LazyDeserialize(closure: { try self.deserializeKey( Array(k).map { try Bit($0.wholeNumberValue!) } ) })
            let value = LazyDeserialize(closure: { try self.deserializeValue(v) })
            return (key, value)
        }
    }
    
    public func get(_ key: K) throws -> V? {
        let k = try serializeKey(key).map { String($0) }.joined()
        guard let v = hashmap[k] else { return nil }
        return try deserializeValue(v)
    }
    
    public func has(_ key: K) throws -> Bool {
        try get(key) != nil
    }
    
    @discardableResult
    public func set(_ key: K, _ value: V) throws -> Self {
        let k = try serializeKey(key).map { String($0) }.joined()
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
        let k = try serializeKey(key).map { String($0) }.joined()
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
        hashmap[key.map { String($0) }.joined()]
    }
    
    @discardableResult
    public func setRaw(_ key: [Bit], _ value: Cell) -> Self {
        hashmap[key.map { String($0) }.joined()] = value
        return self
    }
    
    fileprivate func sortHashmap() throws -> [HashmapNode] {
        var sorted = [(order: Int, key: [Bit], value: Cell)]()

        for (bitstring, value) in hashmap {
            let key = try bitstring.map { try Bit(Int(String($0)) ?? 0) }
            guard let order = Int(bitstring, radix: 2) else {
                continue
            }

            if let lt = sorted.firstIndex(where: { $0.order < order }) {
                sorted.insert((order: order, key: key, value: value), at: lt)
            } else {
                sorted.append((order: order, key: key, value: value))
            }
        }

        return sorted.map { (key: $0.key, value: $0.value) }
    }
    
    fileprivate func serialize() throws -> Cell {
        var nodes = try sortHashmap()
        guard !nodes.isEmpty else {
            throw ErrorTonSdkSwift("Hashmap: can't be empty. It must contain at least 1 key-value pair.")
        }
        
        return try Hashmap.serializeEdge(&nodes)
    }
    
    fileprivate static func serializeEdge(_ nodes: inout [HashmapNode]) throws -> Cell {
        // hme_empty$0
        if nodes.isEmpty {
            let label = try serializeLabelShort([])
            return try CellBuilder().storeBits(label).cell()
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
            // Left edge can be empty, anyway we need to create hme_empty$0 to support right one
            var (leftNodes, rightNodes) = serializeFork(nodes: nodes)
            let leftEdge = try serializeEdge(&leftNodes)
            try edge.storeRef(leftEdge)

            if !rightNodes.isEmpty {
                let rightEdge = try serializeEdge(&rightNodes)
                try edge.storeRef(rightEdge)
            }
        }

        return try edge.cell()
    }
    
    fileprivate static func serializeLabel(_ nodes: inout [HashmapNode]) throws -> [Bit] {
        // Each label can always be serialized in at least two different fashions, using
        // hml_short or hml_long constructors. Usually the shortest serialization (and
        // in the case of a tie—the lexicographically smallest among the shortest) is
        // preferred and is generated by TVM hashmap primitives, while the other
        // variants are still considered valid.
        
        // Get nodes keys
        guard 
            let first = nodes.first?.key,
            let last = nodes.last?.key
        else {
            throw ErrorTonSdkSwift("\(#function) \(#line) Bad nodes")
        }
        
        // m = length at most possible bits of n (key)
        let m = first.count
        
        var sameBitsIndex: Int?
        for (index, element) in first.enumerated() {
            if element != last[index] {
                sameBitsIndex = index
                break
            }
        }
        let sameBitsLength = sameBitsIndex ?? first.count
        
        if first[0] != last[0] || m == 0 {
            // hml_short for zero most possible bits
            return try serializeLabelShort([])
        }
        
        let label = Array(first[0..<sameBitsLength])
        let matches = label.join("").regexp(#"(^0+)|(^1+)"#)
        guard let match = matches[0] else {
            throw ErrorTonSdkSwift("\(#function) \(#line) wrong bits \(matches.description)")
        }
        let repeated = try match.split(separator: "").map { number in try Bit(Int(number)!) }
        let labelShort = try serializeLabelShort(label)
        let labelLong = try serializeLabelLong(label, m)
        
        let labelSame = nodes.count > 1 && repeated.count > 1
            ? try serializeLabelSame(repeated, m)
            : nil
        
        var labels: [(bits: Int, label: [Bit])] = [
            (bits: label.count, label: labelShort),
            (bits: label.count, label: labelLong)
        ]
        
        if let labelSame {
            labels.append((bits: repeated.count, label: labelSame))
        }
        
        // Sort labels by their length
        labels.sort { $0.label.count < $1.label.count }
        
        // Get most compact label
        let choosen = labels[0]
        
        // Remove label bits from nodes keys
        for (index, _) in nodes.enumerated() {
            nodes[index].key.removeFirst(choosen.bits)
        }
        
        return choosen.label
    }

    
    fileprivate static func serializeLabelSame(_ bits: [Bit], _ m: Int) throws -> [Bit] {
        let label = CellBuilder()
        
        try label.storeBits([.b1, .b1])
            .storeBit(bits[0])
            .storeUInt(BigUInt(bits.count), Int(ceil(log2(Double(m + 1)))))
        
        return label.bits
    }
    
    fileprivate static func serializeLabelLong(_ bits: [Bit], _ m: Int) throws -> [Bit] {
        let label = CellBuilder()
        
        try label.storeBits([.b1, .b0])
             .storeUInt(BigUInt(bits.count), Int(ceil(log2(Double(m + 1)))))
             .storeBits(bits)
        
        return label.bits
    }
    
    fileprivate static func serializeLabelShort(_ bits: [Bit]) throws -> [Bit] {
        let label = CellBuilder()
        
        try label.storeBit(.b0)
            .storeBits(Array(repeating: .b1, count: bits.count))
            .storeBit(.b0)
            .storeBits(bits)
        
        return label.bits
    }
    
    fileprivate static func serializeFork(nodes: [HashmapNode]) -> ([HashmapNode], [HashmapNode]) {
        var leftNodes = [HashmapNode]()
        var rightNodes = [HashmapNode]()

        for node in nodes {
            var key = node.key
            let value = node.value

            if !key.isEmpty {
                let firstBit = key.removeFirst()
                if firstBit == .b0 {
                    leftNodes.append((key, value))
                } else {
                    rightNodes.append((key, value))
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
        guard slice.bits.count >= 2 else {
            throw ErrorTonSdkSwift("Empty hashmap")
        }

        let hashmap = try Hashmap<K, V>(keySize: keySize, options: options)
        let nodes = try Self.deserializeEdge(slice, keySize)

        for node in nodes {
            hashmap.setRaw(node.key, node.value)
        }

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
            return nodes + [(currentKey, value)]
        }

        for i in 0..<edge.refs.count {
            let forkEdge = try edge.loadRef().slice()
            let forkKey = currentKey + [try Bit(i)]

            nodes += try deserializeEdge(forkEdge, keySize, forkKey)
        }

        return nodes
    }

    public static func deserializeLabel(_ edge: CellSlice, _ m: Int) throws -> [Bit] {
        // m = length at most possible bits of n (key)
        // hml_short$0
        if try edge.loadBit().rawValue == 0 {
            return try deserializeLabelShort(edge)
        }

        // hml_long$10
        if try edge.loadBit().rawValue == 0 {
            return try deserializeLabelLong(edge, m)
        }

        // hml_same$11
        return try deserializeLabelSame(edge, m)
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
        let length = try edge.loadBigUInt(size: Int(ceil(log2(Double(m + 1)))))
        return try edge.loadBits(size: Int(length))
    }

    public static func deserializeLabelSame(_ edge: CellSlice, _ m: Int) throws -> [Bit] {
        let repeated = try edge.loadBit()
        let length = try edge.loadBigUInt(size: Int(ceil(log2(Double(m + 1)))))
        return Array(repeating: repeated, count: Int(length))
    }

    public func cell() throws -> Cell {
        try serialize()
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
    
    public override func serialize() throws -> Cell {
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
        guard slice.bits.count == 1 else {
            throw ErrorTonSdkSwift("bad hashmap size flag")
        }
        
        if try slice.loadBit() == .b0 {
            return try HashmapE<K, V>(keySize: keySize, options: options)
        }

        let hashmap = try HashmapE<K, V>(keySize: keySize, options: options)
        let edge = try slice.loadRef().slice()
        let nodes = try Hashmap<K, V>.deserializeEdge(edge, keySize)

        for node in nodes {
            hashmap.setRaw(node.key, node.value)
        }

        return hashmap
    }

    public override class func parse(
        keySize: Int,
        slice: CellSlice,
        options: HashmapOptions<K, V>? = nil
    ) throws -> HashmapE<K, V> {
        try deserialize(keySize: keySize, slice: slice, options: options)
    }
}