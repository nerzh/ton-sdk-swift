import XCTest
import BigInt
@testable import TonSdkSwift

final class RawDictionaryTests: XCTestCase {
    private func bits(_ text: String) -> [Bit] { text.map { $0 == "0" ? .b0 : .b1 } }
    private func key(_ value: Int, _ width: Int = 8) throws -> [Bit] {
        try CellBuilder().storeUInt(BigUInt(value), width).bits
    }
    private func value(_ value: Int) throws -> CellSlice {
        try CellBuilder().storeUInt(BigUInt(value), 16).cell().parse()
    }

    func testStructuralMutationPreservesNoncanonicalSiblingAndOwnLabel() throws {
        let left = try Cell(bits: bits("0100") + bits("10101010"))
        let right = try Cell(bits: bits("1011") + bits("01010101"))
        let root = try Cell(bits: bits("1000"), refs: [left, right]) // long empty label
        var map = try RawHashmap(keySize: 2, root: root)
        try map.set(bits("00"), value: value(7))
        XCTAssertTrue(try XCTUnwrap(map.root).refs[1] === right)
        XCTAssertEqual(map.root?.bits, root.bits)
        XCTAssertEqual(map.root?.refs[0].bits.prefix(4), left.bits.prefix(4))
        XCTAssertEqual(try map.get(bits("11"))?.bits, bits("01010101"))
        let changed = try XCTUnwrap(map.root)
        try map.add(bits("00"), value: value(9))
        try map.replace(bits("01"), value: value(9))
        try map.remove(bits("01"))
        XCTAssertTrue(map.root === changed)
    }

    func testIndependentCallerAndReturnedCursorsAndValueCopies() throws {
        var map = try RawHashmap(keySize: 8)
        let input = try value(9)
        try map.set(key(1), value: input)
        input.bits = []
        let cursor = try XCTUnwrap(map.get(key(1)))
        cursor.bits = []
        XCTAssertEqual(try map.get(key(1))?.loadBigUInt(size: 16), 9)
        var copy = map
        try copy.set(key(1), value: value(10))
        XCTAssertEqual(try map.get(key(1))?.loadBigUInt(size: 16), 9)
        XCTAssertEqual(try copy.get(key(1))?.loadBigUInt(size: 16), 10)
    }

    func testPrunedSiblingRemainsOpaqueForLookupUpdateAndEarlyStop() throws {
        let visible = try Cell(bits: bits("00") + bits("101"))
        let hidden = try Cell(bits: bits("00111")).toPrunedBranch()
        let original = try Cell(bits: bits("00"), refs: [visible, hidden])
        var map = try RawHashmap(keySize: 1, root: original)
        XCTAssertEqual(try map.get([.b0])?.bits, bits("101"))
        var visits = 0
        XCTAssertFalse(try map.iterate { key, _ in
            XCTAssertEqual(key, [.b0]); visits += 1; return false
        })
        XCTAssertEqual(visits, 1)
        try map.set([.b0], value: value(5))
        XCTAssertTrue(map.root?.refs[1] === hidden)
        XCTAssertThrowsError(try map.get([.b1]))
        let before = map.root
        XCTAssertThrowsError(try map.remove([.b0])) // collapse requires hidden label
        XCTAssertTrue(map.root === before)
        var iterator = map.makeIterator()
        XCTAssertEqual(try iterator.next()?.key, [.b0])
        XCTAssertThrowsError(try iterator.next())
        XCTAssertThrowsError(try iterator.next()) // failure does not skip the item
    }

    func testMutationsAreAtomicOnOverflowAndInvalidWidths() throws {
        var map = try RawHashmap(keySize: 8)
        try map.set(key(1), value: value(1))
        let before = map.root
        XCTAssertThrowsError(try map.set([], value: value(2)))
        XCTAssertThrowsError(try map.set(key(2), value: CellSlice(bits: Array(repeating: .b0, count: 1023), refs: [])))
        XCTAssertTrue(map.root === before)
    }

    func testEnvelopeIsLazyAtomicAndLeavesFollowingFields() throws {
        let pruned = try Cell(bits: [.b0]).toPrunedBranch()
        let marker = try Cell(bits: [.b1])
        let slice = CellSlice(bits: bits("101"), refs: [pruned, marker])
        let map = try RawHashmap.read(from: slice, keySize: 256)
        XCTAssertTrue(map.root === pruned)
        XCTAssertEqual(slice.bits, bits("01"))
        XCTAssertEqual(slice.refs, [marker])
        XCTAssertEqual(try map.cell().refs, [pruned])
        let missing = CellSlice(bits: [.b1], refs: [])
        XCTAssertThrowsError(try RawHashmap.read(from: missing, keySize: 8))
        XCTAssertEqual(missing.bits, [.b1])
        let full = try CellBuilder().storeRefs([marker, marker, marker, marker])
        XCTAssertThrowsError(try map.write(to: full))
        XCTAssertTrue(full.bits.isEmpty)
    }

    func testInlineForkConsumesExactlyItsLabelAndTwoReferences() throws {
        var map = try RawHashmap(keySize: 2)
        try map.set(bits("00"), value: value(1))
        try map.set(bits("11"), value: value(2))
        let builder = CellBuilder()
        try map.writeRoot(to: builder)
        let tail = try Cell(bits: [.b1])
        try builder.storeBits(bits("11001")).storeRef(tail)
        let cursor = try builder.cell().parse()
        let decoded = try RawHashmap.readRoot(from: cursor, keySize: 2)
        XCTAssertEqual(decoded.root, map.root)
        XCTAssertEqual(cursor.bits, bits("11001"))
        XCTAssertEqual(cursor.refs, [tail])
        let bad = CellSlice(bits: bits("00"), refs: [])
        XCTAssertThrowsError(try RawHashmap.readRoot(from: bad, keySize: 2))
        XCTAssertEqual(bad.bits, bits("00"))
    }

    func testEmptyWidthAndInlineLeaf() throws {
        var map = try RawHashmap(keySize: 0)
        try map.set([], value: value(23))
        XCTAssertEqual(Array(try XCTUnwrap(map.root).bits.prefix(2)), bits("00"))
        let cursor = try XCTUnwrap(map.root).parse()
        let decoded = try RawHashmap.readRoot(from: cursor, keySize: 0)
        XCTAssertEqual(try decoded.get([])?.loadBigUInt(size: 16), 23)
        XCTAssertTrue(cursor.bits.isEmpty)
        XCTAssertNotNil(try map.remove([]))
        XCTAssertTrue(map.isEmpty)
    }

    func testExhaustiveSmallKeysAndReverseRemoval() throws {
        var map = try RawHashmap(keySize: 5)
        for number in (0..<32).reversed() { try map.set(key(number, 5), value: value(number)) }
        XCTAssertEqual(try map.count(), 32)
        var encountered = [Int]()
        try map.iterate { key, cursor in
            let number = Int(key.toBigUInt())
            XCTAssertEqual(try cursor.loadBigUInt(size: 16), BigUInt(number))
            encountered.append(number)
            return true
        }
        XCTAssertEqual(encountered, Array(0..<32))
        for number in (0..<32).reversed() {
            XCTAssertEqual(try map.remove(key(number, 5))?.loadBigUInt(size: 16), BigUInt(number))
            XCTAssertNil(try map.get(key(number, 5)))
        }
        XCTAssertTrue(map.isEmpty)
    }

    func testSearchSubtreeFilterCombineAndDiff() throws {
        var map = try RawHashmap(keySize: 4)
        for number in [0, 2, 5, 8, 15] { try map.set(key(number, 4), value: value(number)) }
        XCTAssertEqual(try map.minimum()?.key, try key(0, 4))
        XCTAssertEqual(try map.maximum()?.key, try key(15, 4))
        XCTAssertEqual(try map.find(key(3, 4))?.key, try key(5, 4))
        XCTAssertEqual(try map.find(key(5, 4), next: false)?.key, try key(2, 4))
        XCTAssertEqual(try map.find(key(5, 4), inclusive: true)?.key, try key(5, 4))
        XCTAssertNil(try map.find(key(15, 4)))
        let upper = try map.subtree(prefix: [.b1])
        XCTAssertEqual(try upper.count(), 2)
        let stripped = try map.subtree(prefix: [.b1], strippingPrefix: true)
        XCTAssertEqual(stripped.keySize, 3)
        XCTAssertEqual(try stripped.get(bits("111"))?.loadBigUInt(size: 16), 15)
        let snapshot = map.root
        try map.filter { _, _ in true }
        XCTAssertTrue(map.root === snapshot)
        enum Failure: Error { case deliberate }
        XCTAssertThrowsError(try map.filter { key, _ in
            if key.first == .b1 { throw Failure.deliberate }
            return false
        })
        XCTAssertTrue(map.root === snapshot)
        var filtered = map
        try filtered.filter { key, _ in key.first == .b1 }
        XCTAssertEqual(try filtered.count(), 2)
        var differences = [[Bit]]()
        try map.scanDiff(filtered) { key, old, new in
            XCTAssertNotNil(old); XCTAssertNil(new); differences.append(key); return true
        }
        XCTAssertEqual(differences, try [0, 2, 5].map { try key($0, 4) })
        try filtered.combine(map)
        XCTAssertEqual(try filtered.count(), 5)
        var conflict = try RawHashmap(keySize: 4)
        try conflict.set(key(0, 4), value: value(999))
        let before = filtered.root
        XCTAssertThrowsError(try filtered.combine(conflict))
        XCTAssertTrue(filtered.root === before)
    }

    func testMalformedForksAndLabelsThrowWithoutMutation() throws {
        for root in [try Cell(bits: bits("00")), try Cell(bits: bits("1011")), try Cell(bits: bits("00"), refs: [Cell()])] {
            var map = try RawHashmap(keySize: 2, root: root)
            XCTAssertThrowsError(try map.get(bits("00")))
            XCTAssertThrowsError(try map.set(bits("00"), value: value(1)))
            XCTAssertTrue(map.root === root)
        }
    }
    func testDiffAndCombineSkipAlignedIdenticalPrunedBranches() throws {
        let hidden = try Cell(bits: bits("001")).toPrunedBranch()
        let old = try Cell(bits: bits("000"))
        let changed = try Cell(bits: bits("001"))
        let oldRoot = try Cell(bits: bits("00"), refs: [old, hidden])
        let newRoot = try Cell(bits: bits("00"), refs: [changed, hidden])
        let a = try RawHashmap(keySize: 1, root: oldRoot)
        let b = try RawHashmap(keySize: 1, root: newRoot)
        var differences = 0
        XCTAssertTrue(try a.scanDiff(b) { key, old, new in
            XCTAssertEqual(key, [.b0]); XCTAssertEqual(old?.bits, [.b0]); XCTAssertEqual(new?.bits, [.b1])
            differences += 1; return true
        })
        XCTAssertEqual(differences, 1)
        var same = a
        try same.combine(a)
        XCTAssertTrue(same.root === oldRoot)
        // A noncanonical left label differs in representation, but carries the
        // same key and value; the shared hidden sibling must remain unopened.
        let noncanonical = try Cell(bits: bits("100")) // long empty label + zero value
        let alternative = try RawHashmap(keySize: 1, root: Cell(bits: bits("00"), refs: [noncanonical, hidden]))
        try same.combine(alternative)
        XCTAssertTrue(same.root === oldRoot)
        XCTAssertEqual(try b.find([.b1], next: false)?.key, [.b0])
    }

    func testInlineReadersRejectKnownExoticOrigins() throws {
        let leaf = try Cell(bits: [.b1])
        let merkle = try Cell.toMerkleUpdate(c1: leaf, c2: leaf)
        let cursor = merkle.parse()
        let beforeBits = cursor.bits
        let beforeRefs = cursor.refs
        XCTAssertThrowsError(try RawHashmap.readRoot(from: cursor, keySize: 1))
        XCTAssertThrowsError(try PfxHashmapE.readRoot(from: cursor, keySize: 1))
        let codec = DictionaryAugmentation<Int>(empty: { 0 }, decode: { _ in 0 },
            encode: { _ in try Cell() }, combine: +)
        XCTAssertThrowsError(try HashmapAugE.readRoot(from: cursor, keySize: 1, augmentation: codec))
        XCTAssertEqual(cursor.bits, beforeBits)
        XCTAssertEqual(cursor.refs, beforeRefs)
    }

}
