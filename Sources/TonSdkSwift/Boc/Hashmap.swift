//
//  File.swift
//
//
//  Created by Oleh Hudeichuk on 28.02.2024.
//

import Foundation
import BigInt

struct HashmapOptions<K, V> {
    var keySize: Int?
    var prefixed: Bool?
    var nonEmpty: Bool?
    var serializers: (key: (K) -> [Bit], value: (V) -> Cell)?
    var deserializers: (key: ([Bit]) -> K, value: (Cell) -> V)?
}

typealias HashmapNode = (key: [Bit], value: Cell)

class Hashmap<K: Collection, V> where K.Element == Bit {
    var hashmap: [String: Cell]
    var keySize: Int
    var serializeKey: (K) -> [Bit]
    var serializeValue: (V) -> Cell
    var deserializeKey: ([Bit]) -> K
    var deserializeValue: (Cell) -> V
    
    init(keySize: Int, options: HashmapOptions<K, V>? = nil) {
        let serializers: (key: (K) -> [Bit], value: (V) -> Cell) = options?.serializers ?? (key: { $0 as! [Bit] }, value: { $0 as! Cell })
        let deserializers: (key: ([Bit]) -> K, value: (Cell) -> V) = options?.deserializers ?? (key: { $0 as! K }, value: { $0 as! V })
        
        self.hashmap = [:]
        self.keySize = keySize
        self.serializeKey = serializers.key
        self.serializeValue = serializers.value
        self.deserializeKey = deserializers.key
        self.deserializeValue = deserializers.value
    }
    
    func makeIterator() -> AnyIterator<(K, V)> {
        var iterator = hashmap.makeIterator()
        return AnyIterator {
            guard let (k, v) = iterator.next() else { return nil }
            #warning("ForceUnwrap")
            let key = self.deserializeKey( Array(k).map { try! Bit($0.wholeNumberValue!) } )
            let value = self.deserializeValue(v)
            return (key, value)
        }
    }
    
    func get(_ key: K) -> V? {
        let k = serializeKey(key).map { String($0) }.joined()
        guard let v = hashmap[k] else { return nil }
        return deserializeValue(v)
    }
    
    func has(_ key: K) -> Bool {
        get(key) != nil
    }
    
    @discardableResult
    func set(_ key: K, _ value: V) -> Self {
        let k = serializeKey(key).map { String($0) }.joined()
        let v = serializeValue(value)
        hashmap[k] = v
        return self
    }
    
    @discardableResult
    func add(_ key: K, _ value: V) -> Self {
        if !has(key) {
            return set(key, value)
        }
        return self
    }
    
    @discardableResult
    func replace(_ key: K, _ value: V) -> Self {
        if has(key) {
            return set(key, value)
        }
        return self
    }
    
    func getSet(_ key: K, _ value: V) -> V? {
        let prev = get(key)
        set(key, value)
        return prev
    }
    
    func getAdd(_ key: K, _ value: V) -> V? {
        let prev = get(key)
        add(key, value)
        return prev
    }
    
    func getReplace(_ key: K, _ value: V) -> V? {
        let prev = get(key)
        replace(key, value)
        return prev
    }
    
    func delete(_ key: K) -> Self {
        let k = serializeKey(key).map { String($0) }.joined()
        hashmap.removeValue(forKey: k)
        return self
    }
    
    func isEmpty() -> Bool {
        return hashmap.isEmpty
    }
    
    func forEach(_ callbackfn: (K, V) -> Void) {
        for (key, value) in self.makeIterator() {
            callbackfn(key, value)
        }
    }
    
    func getRaw(_ key: [Bit]) -> Cell? {
        hashmap[key.map { String($0) }.joined()]
    }
    
    @discardableResult
    func setRaw(_ key: [Bit], _ value: Cell) -> Self {
        hashmap[key.map { String($0) }.joined()] = value
        return self
    }
    
    fileprivate func sortHashmap() throws -> [HashmapNode] {
        let sorted = try hashmap.sorted { $0.key < $1.key }.map { ( try $0.key.map { try Bit($0.wholeNumberValue!) }, $0.value) }
        return sorted
    }
    
    fileprivate func serialize() throws -> Cell {
        let nodes = try sortHashmap()
        guard !nodes.isEmpty else {
            throw ErrorTonSdkSwift("Hashmap: can't be empty. It must contain at least 1 key-value pair.")
        }
        
        return try Hashmap.serializeEdge(nodes)
    }
    
    fileprivate static func serializeEdge(_ nodes: [HashmapNode]) throws -> Cell {
        // hme_empty$0
        if nodes.isEmpty {
            let label = try serializeLabelShort([])
            return try CellBuilder().storeBits(label).cell()
        }

        let edge = CellBuilder()
        let label = try serializeLabel(nodes)
        try edge.storeBits(label)

        // hmn_leaf#_
        if nodes.count == 1 {
            let leaf = serializeLeaf(node: nodes[0])
            try edge.storeSlice(leaf.slice())
        }

        // hmn_fork#_
        if nodes.count > 1 {
            // Left edge can be empty, anyway we need to create hme_empty$0 to support right one
            let (leftNodes, rightNodes) = serializeFork(nodes: nodes)
            let leftEdge = try serializeEdge(leftNodes)
            try edge.storeRef(leftEdge)

            if !rightNodes.isEmpty {
                let rightEdge = try serializeEdge(rightNodes)
                try edge.storeRef(rightEdge)
            }
        }

        return try edge.cell()
    }
    
    fileprivate static func serializeLabel(_ nodes: [HashmapNode]) throws -> [Bit] {
        guard let first = nodes.first?.key, let last = nodes.last?.key else {
            return []
        }
        
        let m = first.count
        var sameBitsLength = 0
        
        for i in 0..<m {
            if first[i] != last[i] {
                sameBitsLength = i
                break
            }
        }
        
        if first[0] != last[0] || m == 0 {
            return try serializeLabelShort([])
        }
        
        let label = Array(first.prefix(sameBitsLength))
        var repeated: [Bit] = []
        
        for bit in label {
            if bit == .b0 || bit == .b1 {
                repeated.append(bit)
            } else {
                break
            }
        }
        
        let labelShort = try serializeLabelShort(label)
        let labelLong = try serializeLabelLong(label, m)
        var labelSame: [Bit]? = nil
        
        if nodes.count > 1 && repeated.count > 1 {
            labelSame = try serializeLabelSame(repeated, m)
        }
        
        var labels: [(bits: Int, label: [Bit])] = [
            (label.count, labelShort),
            (label.count, labelLong),
        ]
        
        if let labelSame = labelSame {
            labels.append((repeated.count, labelSame))
        }
        
        labels.sort { $0.label.count < $1.label.count }
        
        guard let choosen = labels.first?.label else {
            return []
        }
        
        for var node in nodes {
            node.key.removeFirst(choosen.count)
        }
        
        return choosen
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
            .storeBits(Array(repeating: .b1, count: bits.count + 1))
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
    
    static func deserialize<K, V>(
        keySize: Int,
        slice: CellSlice,
        options: HashmapOptions<K, V>?
    ) throws -> Hashmap<K, V> {
        guard slice.bits.count >= 2 else {
            throw ErrorTonSdkSwift("Empty hashmap")
        }

        let hashmap = Hashmap<K, V>(keySize: keySize, options: options)
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
        var edge = edge
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

    static func deserializeLabel(_ edge: CellSlice, _ m: Int) throws -> [Bit] {
        // m = length at most possible bits of n (key)
        var edge = edge
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

    static func deserializeLabelShort(_ edge: CellSlice) throws -> [Bit] {
        guard let zeroIndex = edge.bits.firstIndex(of: .b0) else {
            throw ErrorTonSdkSwift("Invalid Label")
        }
        var edge = edge
        let length = zeroIndex
        try edge.skip(size: length + 1)
        
        return try edge.loadBits(size: length)
    }

    static func deserializeLabelLong(_ edge: CellSlice, _ m: Int) throws -> [Bit] {
        var edge = edge
        let length = try edge.loadBigUInt(size: Int(ceil(log2(Double(m + 1)))))
        return try edge.loadBits(size: Int(length))
    }

    static func deserializeLabelSame(_ edge: CellSlice, _ m: Int) throws -> [Bit] {
        var edge = edge
        let repeated = try edge.loadBit()
        let length = try edge.loadBigUInt(size: Int(ceil(log2(Double(m + 1)))))
        return Array(repeating: repeated, count: Int(length))
    }

    func cell() throws -> Cell {
        try serialize()
    }

    static func parse<K, V>(
        keySize: Int,
        slice: CellSlice,
        options: HashmapOptions<K, V>? = nil
    ) throws -> Hashmap<K, V> {
        try deserialize(keySize: keySize, slice: slice, options: options)
    }

}

