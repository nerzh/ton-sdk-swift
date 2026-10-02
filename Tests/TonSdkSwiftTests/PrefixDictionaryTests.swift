import XCTest
@testable import TonSdkSwift

final class PrefixDictionaryTests: XCTestCase {
    private func bits(_ text: String) -> [Bit] { text.map { $0 == "0" ? .b0 : .b1 } }
    private func value(_ text: String) -> CellSlice { CellSlice(bits: bits(text), refs: []) }

    func testLiteralPrefixLeafAndForkTags() throws {
        var map = try PfxHashmapE(keySize: 4)
        try map.set(bits("0"), value: value("101"))
        XCTAssertEqual(map.root?.bits, bits("0100") + bits("0") + bits("101"))
        try map.set(bits("10"), value: value("11"))
        let root = try XCTUnwrap(map.root)
        XCTAssertEqual(root.bits, bits("001"))
        XCTAssertEqual(root.refs[0].bits, bits("000101"))
        XCTAssertEqual(root.refs[1].bits, bits("0100011"))
        XCTAssertEqual(try map.get(bits("0"))?.bits, bits("101"))
        XCTAssertEqual(try map.get(bits("10"))?.bits, bits("11"))
        XCTAssertNil(try map.get(bits("1"))) // no Rust exhausted-query alias
        XCTAssertNil(try map.get(bits("00")))
    }

    func testPrefixCollisionsThrowAndKeepRoot() throws {
        var map = try PfxHashmapE(keySize: 8)
        try map.set(bits("001"), value: value("1"))
        let original = map.root
        XCTAssertThrowsError(try map.set(bits("00"), value: value("0")))
        XCTAssertThrowsError(try map.set(bits("0011"), value: value("0")))
        XCTAssertThrowsError(try map.set([], value: value("0")))
        XCTAssertTrue(map.root === original)
        XCTAssertNil(try map.replace(bits("00"), value: value("0")))
        XCTAssertNil(try map.remove(bits("00")))
        XCTAssertTrue(map.root === original)
    }

    func testPrefixQueriesEarlyStopAndIndependentCursors() throws {
        var map = try PfxHashmapE(keySize: 8)
        for key in ["00", "010", "011", "1"] { try map.set(bits(key), value: value(key)) }
        let found = try XCTUnwrap(map.prefixMatch(bits("011101")))
        XCTAssertEqual(found.key, bits("011"))
        XCTAssertEqual(found.remainder, bits("101"))
        found.value.bits = []
        XCTAssertEqual(try map.get(bits("011"))?.bits, bits("011"))
        XCTAssertNil(try map.prefixMatch(bits("01")))
        var seen = [[Bit]]()
        XCTAssertFalse(try map.iterate { key, _ in seen.append(key); return seen.count < 2 })
        XCTAssertEqual(seen, [bits("00"), bits("010")])
        let snapshot = map.root
        var copy = map
        try copy.remove(bits("1"))
        XCTAssertTrue(map.root === snapshot)
        XCTAssertEqual(try copy.get(bits("011"))?.bits, bits("011"))
    }

    func testRemovalCollapsesForkAndRetainsTag() throws {
        var map = try PfxHashmapE(keySize: 8)
        try map.set(bits("101"), value: value("0"))
        let single = map.root
        try map.set(bits("1000"), value: value("1"))
        XCTAssertEqual(try map.remove(bits("1000"))?.bits, bits("1"))
        XCTAssertEqual(map.root, single)
        try map.remove(bits("101"))
        XCTAssertTrue(map.isEmpty)
    }

    func testOpaqueEnvelopeAndPrunedSibling() throws {
        let left = try Cell(bits: bits("0001")) // empty label, leaf, value 1
        let right = try Cell(bits: bits("0000")).toPrunedBranch()
        let root = try Cell(bits: bits("001"), refs: [left, right])
        var map = try PfxHashmapE(keySize: 1, root: root)
        XCTAssertEqual(try map.get([.b0])?.bits, [.b1])
        try map.set([.b0], value: value("0"))
        XCTAssertTrue(map.root?.refs[1] === right)
        XCTAssertThrowsError(try map.get([.b1]))
        let wire = try CellBuilder().storeSlice(map.cell().parse()).storeBits(bits("101")).cell().parse()
        let decoded = try PfxHashmapE.read(from: wire, keySize: 1)
        XCTAssertEqual(decoded.root, map.root)
        XCTAssertEqual(wire.bits, bits("101"))
    }

    func testInlineRootAndEmptyKey() throws {
        var singleton = try PfxHashmapE(keySize: 0)
        try singleton.set([], value: value("11"))
        XCTAssertEqual(singleton.root?.bits, bits("00011"))
        XCTAssertEqual(try singleton.prefixMatch(bits("101"))?.remainder, bits("101"))
        var map = try PfxHashmapE(keySize: 2)
        try map.set([.b0], value: value("0"))
        try map.set([.b1], value: value("1"))
        let builder = CellBuilder()
        try map.writeRoot(to: builder)
        try builder.storeBits(bits("101"))
        let cursor = try builder.cell().parse()
        let decoded = try PfxHashmapE.readRoot(from: cursor, keySize: 2)
        XCTAssertEqual(decoded.root, map.root)
        XCTAssertEqual(cursor.bits, bits("101"))
    }

    func testMalformedTagsAndForksAreRejectedAtomically() throws {
        for root in [try Cell(bits: bits("00")), try Cell(bits: bits("001")), try Cell(bits: bits("01001"))] {
            var map = try PfxHashmapE(keySize: 1, root: root)
            XCTAssertThrowsError(try map.get([.b0]))
            XCTAssertThrowsError(try map.set([.b0], value: value("1")))
            XCTAssertTrue(map.root === root)
        }
    }
}
