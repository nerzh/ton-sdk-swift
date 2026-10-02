import XCTest
import BigInt
@testable import TonSdkSwift

final class AugmentedDictionaryTests: XCTestCase {
    private func bits(_ text: String) -> [Bit] { text.map { $0 == "0" ? .b0 : .b1 } }
    private var sum: DictionaryAugmentation<BigUInt> {
        DictionaryAugmentation(empty: { 0 }, decode: { try $0.loadBigUInt(size: 8) },
                               encode: { try CellBuilder().storeUInt($0, 8).cell() }, combine: +)
    }

    func testLiteralLeafForkEnvelopeAndRefreshAfterRemoval() throws {
        var map = try HashmapAugE(keySize: 1, augmentation: sum)
        try map.set([.b0], value: CellSlice(bits: bits("101"), refs: []), extra: 3)
        XCTAssertEqual(map.root?.bits, bits("0100") + bits("00000011") + bits("101"))
        try map.set([.b1], value: CellSlice(bits: bits("010"), refs: []), extra: 5)
        let root = try XCTUnwrap(map.root)
        XCTAssertEqual(root.bits, bits("00") + bits("00001000"))
        XCTAssertEqual(root.refs[0].bits, bits("00") + bits("00000011") + bits("101"))
        XCTAssertEqual(root.refs[1].bits, bits("00") + bits("00000101") + bits("010"))
        XCTAssertEqual(try map.cell().bits, bits("1") + bits("00001000"))
        XCTAssertEqual(try map.rootExtra(), 8)
        try map.validateAugmentation()
        XCTAssertEqual(try map.remove([.b0])?.bits, bits("101"))
        XCTAssertEqual(try map.rootExtra(), 5)
        try map.validateAugmentation()
        try map.remove([.b1])
        XCTAssertEqual(try map.rootExtra(), 0)
        XCTAssertEqual(try map.cell().bits, bits("000000000"))
    }

    func testNoncommutativeAggregationIsAlwaysLeftThenRight() throws {
        let codec = DictionaryAugmentation<String>(empty: { "" }, decode: { slice in
            let count = Int(try slice.loadBigUInt(size: 8))
            return try slice.loadString(size: count)
        }, encode: { text in
            try CellBuilder().storeUInt(BigUInt(text.utf8.count), 8).storeString(text).cell()
        }, combine: { $0 + $1 })
        var map = try HashmapAugE(keySize: 2, augmentation: codec)
        for (key, extra) in [("11", "D"), ("00", "A"), ("10", "C"), ("01", "B")] {
            try map.set(bits(key), value: CellSlice(bits: [], refs: []), extra: extra)
        }
        XCTAssertEqual(try map.rootExtra(), "ABCD")
        try map.remove(bits("01"))
        XCTAssertEqual(try map.rootExtra(), "ACD")
        try map.validateAugmentation()
    }

    func testReferenceBearingExtrasFollowChildReferences() throws {
        struct Extra { var number: BigUInt; var marker: Cell }
        let marker = try Cell(bits: [.b1])
        let codec = DictionaryAugmentation<Extra>(empty: { Extra(number: 0, marker: marker) },
            decode: { Extra(number: try $0.loadBigUInt(size: 8), marker: try $0.loadRef()) },
            encode: { try CellBuilder().storeUInt($0.number, 8).storeRef($0.marker).cell() },
            combine: { Extra(number: $0.number + $1.number, marker: $0.marker) })
        var map = try HashmapAugE(keySize: 1, augmentation: codec)
        let valueRef = try Cell(bits: [.b0])
        try map.set([.b0], value: CellSlice(bits: [.b1], refs: [valueRef]), extra: Extra(number: 1, marker: marker))
        try map.set([.b1], value: CellSlice(bits: [.b0], refs: []), extra: Extra(number: 2, marker: marker))
        let root = try XCTUnwrap(map.root)
        XCTAssertEqual(root.refs.count, 3)
        XCTAssertTrue(root.refs[2] === marker)
        XCTAssertEqual(root.refs[0].refs, [marker, valueRef])
        let result = try XCTUnwrap(map.get([.b0]))
        XCTAssertEqual(result.extra.number, 1)
        XCTAssertEqual(result.value.refs, [valueRef])
        result.value.refs = []
        XCTAssertEqual(try map.get([.b0])?.value.refs, [valueRef])
        XCTAssertEqual(try map.cell().refs, [root, marker])
        try map.validateAugmentation()
    }

    func testEnvelopePreservesOpaqueRootAndStoredExtraAndFollowingFields() throws {
        let pruned = try Cell(bits: [.b1]).toPrunedBranch()
        let marker = try Cell(bits: [.b0])
        let slice = try CellBuilder().storeBit(.b1).storeUInt(7, 8).storeBits(bits("101"))
            .storeRefs([pruned, marker]).cell().parse()
        let map = try HashmapAugE.read(from: slice, keySize: 256, augmentation: sum)
        XCTAssertTrue(map.root === pruned)
        XCTAssertEqual(try map.rootExtra(), 7)
        XCTAssertEqual(slice.bits, bits("101"))
        XCTAssertEqual(slice.refs, [marker])
        XCTAssertThrowsError(try map.validateAugmentation())
        let badEmpty = try CellBuilder().storeBit(.b0).storeUInt(1, 8).cell().parse()
        let original = badEmpty.bits
        XCTAssertThrowsError(try HashmapAugE.read(from: badEmpty, keySize: 8, augmentation: sum))
        XCTAssertEqual(badEmpty.bits, original)
    }

    func testPrunedSiblingLookupWorksButUnknowableAggregationRollsBack() throws {
        let left = try CellBuilder().storeBits(bits("00")).storeUInt(3, 8).storeBit(.b1).cell()
        let right = try CellBuilder().storeBits(bits("00")).storeUInt(5, 8).storeBit(.b0).cell().toPrunedBranch()
        let root = try CellBuilder().storeBits(bits("00")).storeUInt(8, 8).storeRefs([left, right]).cell()
        var map = try HashmapAugE(keySize: 1, root: root, augmentation: sum)
        XCTAssertEqual(try map.get([.b0])?.extra, 3)
        XCTAssertFalse(try map.iterate { key, _, _ in XCTAssertEqual(key, [.b0]); return false })
        XCTAssertThrowsError(try map.set([.b0], value: CellSlice(bits: [.b0], refs: []), extra: 4))
        XCTAssertTrue(map.root === root)
        XCTAssertEqual(try map.rootExtra(), 8)
        XCTAssertThrowsError(try map.remove([.b0]))
        XCTAssertTrue(map.root === root)
    }

    func testSerializationAggregationAndFilterErrorsAreAtomic() throws {
        var map = try HashmapAugE(keySize: 2, augmentation: sum)
        try map.set(bits("00"), value: CellSlice(bits: [.b0], refs: []), extra: 200)
        let original = map.root
        XCTAssertThrowsError(try map.set(bits("11"), value: CellSlice(bits: [.b1], refs: []), extra: 100)) // uint8 sum overflows
        XCTAssertTrue(map.root === original)
        XCTAssertEqual(try map.rootExtra(), 200)
        try map.set(bits("11"), value: CellSlice(bits: [.b1], refs: []), extra: 1)
        let beforeFilter = map.root
        enum Failure: Error { case callback }
        XCTAssertThrowsError(try map.filter { key, _, _ in
            if key.first == .b1 { throw Failure.callback }
            return false
        })
        XCTAssertTrue(map.root === beforeFilter)
        XCTAssertEqual(try map.rootExtra(), 201)
        try map.filter { key, _, _ in key.first == .b1 }
        XCTAssertEqual(try map.rootExtra(), 1)
    }

    func testInlineAugmentedForkWithReferenceExtraPreservesFollowingFields() throws {
        var map = try HashmapAugE(keySize: 1, augmentation: sum)
        try map.set([.b0], value: CellSlice(bits: [], refs: []), extra: 2)
        try map.set([.b1], value: CellSlice(bits: [], refs: []), extra: 4)
        let builder = CellBuilder()
        try map.writeRoot(to: builder)
        try builder.storeBits(bits("101"))
        let cursor = try builder.cell().parse()
        let decoded = try HashmapAugE.readRoot(from: cursor, keySize: 1, augmentation: sum)
        XCTAssertEqual(decoded.root, map.root)
        XCTAssertEqual(try decoded.rootExtra(), 6)
        XCTAssertEqual(cursor.bits, bits("101"))
    }

    func testExplicitValidationDetectsTamperedForkAndEnvelopeExtras() throws {
        var map = try HashmapAugE(keySize: 1, augmentation: sum)
        try map.set([.b0], value: CellSlice(bits: [], refs: []), extra: 2)
        try map.set([.b1], value: CellSlice(bits: [], refs: []), extra: 4)
        let goodRoot = try XCTUnwrap(map.root)
        let badRoot = try CellBuilder().storeBits(bits("00")).storeUInt(7, 8).storeRefs(goodRoot.refs).cell()
        let bad = try HashmapAugE(keySize: 1, root: badRoot, augmentation: sum)
        XCTAssertThrowsError(try bad.validateAugmentation())
        let envelope = try CellBuilder().storeBit(.b1).storeUInt(7, 8).storeRef(goodRoot).cell()
        let mismatch = try HashmapAugE.read(from: envelope.parse(), keySize: 1, augmentation: sum)
        XCTAssertThrowsError(try mismatch.validateAugmentation())
    }
    func testTypedAdapterComputesLeafExtrasAndRollsBackDecodeFailure() throws {
        let raw = try HashmapAugE(keySize: 8, augmentation: sum)
        enum Failure: Error { case forbidden }
        var map = TypedHashmapAugE<Int, Int, BigUInt>(raw: raw,
            encodeKey: { try CellBuilder().storeUInt(BigUInt($0), 8).bits },
            decodeKey: { Int($0.toBigUInt()) },
            encodeValue: { try CellBuilder().storeUInt(BigUInt($0), 8).cell() },
            decodeValue: { cursor in
                let number = Int(try cursor.loadBigUInt(size: 8))
                if number == 7 { throw Failure.forbidden }
                return number
            }, leafExtra: { BigUInt($0) })
        try map.set(1, value: 3)
        try map.set(2, value: 7)
        XCTAssertEqual(try map.raw.rootExtra(), 10)
        XCTAssertEqual(try map.get(1), 3)
        let before = map.raw.root
        XCTAssertThrowsError(try map.set(2, value: 8))
        XCTAssertTrue(map.raw.root === before)
        XCTAssertEqual(try map.raw.rootExtra(), 10)
    }

}
