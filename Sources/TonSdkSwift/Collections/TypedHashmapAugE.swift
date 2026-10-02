// Typed value adapter over the SDK's persistent augmented dictionary.

/// Typed access with an explicit key/value schema and automatic leaf extras.
/// The raw tree remains available for wire encoding and proof construction.
public struct TypedHashmapAugE<Key, Value, Extra> {
    public private(set) var raw: HashmapAugE<Extra>
    private let encodeKey: (Key) throws -> [Bit]
    private let decodeKey: ([Bit]) throws -> Key
    private let encodeValue: (Value) throws -> Cell
    private let decodeValue: (CellSlice) throws -> Value
    private let leafExtra: (Value) throws -> Extra

    public init(raw: HashmapAugE<Extra>,
                encodeKey: @escaping (Key) throws -> [Bit],
                decodeKey: @escaping ([Bit]) throws -> Key,
                encodeValue: @escaping (Value) throws -> Cell,
                decodeValue: @escaping (CellSlice) throws -> Value,
                leafExtra: @escaping (Value) throws -> Extra) {
        self.raw = raw
        self.encodeKey = encodeKey
        self.decodeKey = decodeKey
        self.encodeValue = encodeValue
        self.decodeValue = decodeValue
        self.leafExtra = leafExtra
    }

    public func get(_ key: Key) throws -> Value? {
        try raw.get(encodeKey(key)).map { try decodeValue($0.value) }
    }

    @discardableResult
    public mutating func set(_ key: Key, value: Value) throws -> Value? {
        var staged = raw
        let previous = try staged.set(encodeKey(key), value: encodeValue(value).parse(), extra: leafExtra(value))
        let decoded = try previous.map(decodeValue)
        raw = staged
        return decoded
    }

    @discardableResult
    public mutating func add(_ key: Key, value: Value) throws -> Value? {
        var staged = raw
        let previous = try staged.add(encodeKey(key), value: encodeValue(value).parse(), extra: leafExtra(value))
        let decoded = try previous.map(decodeValue)
        raw = staged
        return decoded
    }

    @discardableResult
    public mutating func replace(_ key: Key, value: Value) throws -> Value? {
        var staged = raw
        let previous = try staged.replace(encodeKey(key), value: encodeValue(value).parse(), extra: leafExtra(value))
        let decoded = try previous.map(decodeValue)
        raw = staged
        return decoded
    }

    @discardableResult
    public mutating func remove(_ key: Key) throws -> Value? {
        var staged = raw
        let previous = try staged.remove(encodeKey(key))
        let decoded = try previous.map(decodeValue)
        raw = staged
        return decoded
    }

    @discardableResult
    public func iterate(_ body: (Key, Value, Extra) throws -> Bool) throws -> Bool {
        try raw.iterate { key, value, extra in try body(decodeKey(key), decodeValue(value), extra) }
    }

    public mutating func filter(_ keep: (Key, Value, Extra) throws -> Bool) throws {
        var staged = raw
        try staged.filter { key, value, extra in try keep(decodeKey(key), decodeValue(value), extra) }
        raw = staged
    }
}
