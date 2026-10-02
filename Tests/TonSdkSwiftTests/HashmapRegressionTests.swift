import XCTest
import BigInt
@testable import TonSdkSwift

/// Independent TON TL-B vectors, including the homogeneous-key hash reported
/// by the EverBlockSwift audit. No sibling checkout or fixture is required.
final class HashmapRegressionTests: XCTestCase {
    private func bits(_ string: String) -> [Bit] { string.map { $0 == "0" ? .b0 : .b1 } }

    func testHighBit64And256BitKeysAreNotDropped() throws {
        for width in [64, 256] {
            let dictionary = try HashmapE<[Bit], Cell>(keySize: width)
            let low = Array(repeating: Bit.b0, count: width)
            let high = [Bit.b1] + Array(repeating: Bit.b0, count: width - 1)
            let max = Array(repeating: Bit.b1, count: width)
            try dictionary.set(low, CellBuilder().storeUInt(1, 8).cell())
            try dictionary.set(high, CellBuilder().storeUInt(2, 8).cell())
            try dictionary.set(max, CellBuilder().storeUInt(3, 8).cell())
            let decoded = try HashmapE<[Bit], Cell>.parse(keySize: width, slice: dictionary.cell().parse())
            XCTAssertEqual(decoded.hashmap.count, 3)
            XCTAssertEqual(try decoded.get(high)?.bits, bits("00000010"))
            let ordered = try Array(dictionary.makeIterator()).map { try $0.0.deserialize() }
            XCTAssertEqual(ordered, [low, high, max])
        }
    }

    func testHomogeneousSingletonUsesSameLabelWithLiteralHash() throws {
        let dictionary = try Hashmap<[Bit], Cell>(keySize: 8)
        try dictionary.set(bits("11111111"), Cell(bits: bits("1111111")))
        let root = try dictionary.cell()
        XCTAssertEqual(root.bits, bits("11110001111111"))
        XCTAssertEqual(try root.hash(), "32b8a2b95a8f49ef533679bb102dc5e3210f83896fb6e3bedc164999972ce3d0")
    }

    func testWholeMixedCommonPrefixPrecedesFork() throws {
        let dictionary = try Hashmap<[Bit], Cell>(keySize: 9)
        try dictionary.set(bits("000000010"), Cell(bits: [.b0]))
        try dictionary.set(bits("000000011"), Cell(bits: [.b1]))
        let root = try dictionary.cell()
        XCTAssertEqual(root.bits, bits("10100000000001"))
        XCTAssertEqual(root.refs.count, 2)
        XCTAssertEqual(root.refs[0].bits, bits("000"))
        XCTAssertEqual(root.refs[1].bits, bits("001"))
        let decoded = try Hashmap<[Bit], Cell>.parse(keySize: 9, slice: root.parse())
        XCTAssertEqual(decoded.hashmap.count, 2)
    }

    func testWrongKeyWidthsAreRejectedBeforeMutation() throws {
        let dictionary = try HashmapE<[Bit], Cell>(keySize: 8)
        let value = try Cell()
        try dictionary.set(bits("10000000"), value)
        let original = try dictionary.cell()
        XCTAssertThrowsError(try dictionary.set(bits("1"), value))
        XCTAssertThrowsError(try dictionary.add(bits("111111111"), value))
        XCTAssertThrowsError(try dictionary.replace([], value))
        XCTAssertThrowsError(try dictionary.setRawChecked([], value))
        dictionary.setRaw([], value) // Legacy API ignores invalid widths.
        XCTAssertEqual(try dictionary.cell(), original)
        dictionary.hashmap["abc"] = value
        XCTAssertThrowsError(try dictionary.cell())
        XCTAssertThrowsError(try dictionary.makeIterator())
    }

    func testEnvelopeConsumesOnlyItsOwnFields() throws {
        let dictionary = try HashmapE<[Bit], Cell>(keySize: 1)
        try dictionary.set([.b0], Cell())
        let trailing = try Cell(bits: [.b1])
        let wire = try CellBuilder().storeSlice(dictionary.cell().parse()).storeBits(bits("101"))
            .storeRef(trailing).cell().parse()
        let decoded = try HashmapE<[Bit], Cell>.parse(keySize: 1, slice: wire)
        XCTAssertEqual(decoded.hashmap.count, 1)
        XCTAssertEqual(wire.bits, bits("101"))
        XCTAssertEqual(wire.refs, [trailing])
        let empty = CellSlice(bits: bits("0101"), refs: [trailing])
        XCTAssertTrue(try HashmapE<[Bit], Cell>.parse(keySize: 1, slice: empty).isEmpty())
        XCTAssertEqual(empty.bits, bits("101"))
        XCTAssertEqual(empty.refs, [trailing])
    }

    func testFacadePreservesNoncanonicalRootAndCopyUntilMutation() throws {
        let root = try CellBuilder().storeBits(bits("10")).storeUInt(8, 4)
            .storeUInt(255, 8).storeUInt(42, 8).cell()
        let envelope = try CellBuilder().storeBit(.b1).storeRef(root).cell()
        let map = try HashmapE<[Bit], Cell>.parse(keySize: 8, slice: envelope.parse())
        XCTAssertEqual(try map.cell(), envelope)
        XCTAssertEqual(try map.copy().cell(), envelope)
        try map.set(bits("00000000"), Cell())
        XCTAssertNotEqual(try map.cell(), envelope)
    }

    func testLabelAllFormsBoundsAndTieBreaking() throws {
        for key in ["", "0", "1", "01", "11", "000", "010", "11111111"] {
            for maximum in [key.count, max(key.count, 8)] {
                let builder = CellBuilder()
                try DictionaryLabel.write(bits(key), maximum: maximum, to: builder)
                let slice = try builder.storeBit(.b1).cell().parse()
                XCTAssertEqual(try DictionaryLabel.read(from: slice, maximum: maximum), bits(key))
                XCTAssertEqual(slice.bits, [.b1])
            }
        }
        let tied = CellBuilder()
        try DictionaryLabel.write([.b1], maximum: 1, to: tied)
        XCTAssertEqual(tied.bits, bits("0101")) // short wins the short/long tie
        XCTAssertThrowsError(try DictionaryLabel.read(from: CellSlice(bits: bits("1011"), refs: []), maximum: 2))
        XCTAssertThrowsError(try DictionaryLabel.read(from: CellSlice(bits: bits("011"), refs: []), maximum: 1))
        XCTAssertThrowsError(try DictionaryLabel.read(from: CellSlice(bits: [], refs: []), maximum: 0))
        XCTAssertThrowsError(try Hashmap<[Bit], Cell>(keySize: -1))
    }

    func testMerkleProofForHashmapEUsesRootNotEnvelope() throws {
        let map = try HashmapE<[Bit], Cell>(keySize: 2)
        try map.set(bits("00"), Cell(bits: [.b0]))
        try map.set(bits("11"), Cell(bits: [.b1]))
        let proof = try map.buildMerkleProof(keys: [bits("00")])
        XCTAssertEqual(proof.type, .merkleProof)
        XCTAssertEqual(try proof.refs[0].hash(0), try map.cell().refs[0].hash(0))
    }
    func testDeprecatedOptionsRejectUnsupportedModes() throws {
        XCTAssertThrowsError(try Hashmap<[Bit], Cell>(keySize: 8, options: .init(prefixed: true)))
        XCTAssertThrowsError(try Hashmap<[Bit], Cell>(keySize: 8, options: .init(nonEmpty: true)))
    }

}
