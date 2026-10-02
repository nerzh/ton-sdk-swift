import BigInt
import Foundation
import SwiftExtensionsPack
import XCTest
@testable import TonSdkSwift

final class UpstreamCellBOCRegressionTests: XCTestCase {
    func testMixedHashPoliciesCannotProduceAmbiguousBOCs() throws {
        let payload = try CellBuilder().storeUInt(1, 8).storeUInt(2, 8)
            .storeUInt(0, 256).storeUInt(0, 16).bits
        let pruned = try Cell(bits: payload, type: .prunedBranch)
        let ton = try Cell(refs: [pruned])
        let everscale = try Cell(refs: [pruned], compatibility: .everscale)
        XCTAssertNotEqual(try ton.hash(), try everscale.hash())
        XCTAssertThrowsError(try Cell(refs: [ton], compatibility: .everscale))
        XCTAssertThrowsError(try Boc.serialize(root: [ton, everscale]))
        // Pruned records themselves use identical descriptors under both policies.
        XCTAssertEqual(try Boc.deserialize(data: everscale.toBoc(), compatibility: .everscale), [everscale])
    }

    func testDictionarySkippingAndUnaryPreloadingValidateBeforeConsumption() throws {
        let reference = try Cell()
        let empty = CellSlice(bits: [.b0, .b1], refs: [reference])
        try empty.skipDict()
        XCTAssertEqual(empty.bits, [.b1])
        XCTAssertTrue(empty.refs.first === reference)
        let full = CellSlice(bits: [.b1, .b0], refs: [reference])
        try full.skipDict()
        XCTAssertEqual(full.bits, [.b0])
        XCTAssertTrue(full.refs.isEmpty)
        let missing = CellSlice(bits: [.b1], refs: [])
        XCTAssertThrowsError(try missing.skipDict())
        XCTAssertEqual(missing.bits, [.b1])
        for bits: [Bit] in [[], [.b1], [.b1, .b1]] {
            let malformed = CellSlice(bits: bits, refs: [])
            XCTAssertThrowsError(try malformed.preloadUnaryLength())
            XCTAssertEqual(malformed.bits, bits)
        }
        XCTAssertEqual(try CellSlice(bits: [.b1, .b1, .b0], refs: []).preloadUnaryLength(), 2)
    }

    func testMerkleUpdateValidatesPrunedHashesAndRejectsCorruptMetadata() throws {
        let original = try Cell(bits: [.b1, .b0])
        let pruned = try original.toPrunedBranch()
        XCTAssertEqual(try pruned.hash(0), try original.hash(0))
        let update = try Cell.toMerkleUpdate(c1: pruned, c2: original)
        XCTAssertEqual(update.type, .merkleUpdate)
        XCTAssertEqual(try Boc.deserialize(data: update.toBoc()).first, update)
        var corrupt = update.bits
        corrupt[8] = corrupt[8] == .b0 ? .b1 : .b0
        XCTAssertThrowsError(try Cell(bits: corrupt, refs: update.refs, type: .merkleUpdate))
        XCTAssertThrowsError(try Cell(bits: Array(corrupt.dropLast()), refs: update.refs, type: .merkleUpdate))
    }

    func testShapeInspectionAndProofPresenceAreSeparateFromAuthenticity() throws {
        let child = try Cell()
        let bits = try CellBuilder().storeUInt(3, 8).storeUInt(0, 256).storeUInt(0, 16).bits
        XCTAssertThrowsError(try Cell(bits: bits, refs: [child], type: .merkleProof))
        let shape = try Cell(bits: bits, refs: [child], type: .merkleProof, checkMerkleMetadata: false)
        let boc = try shape.toBoc()
        XCTAssertThrowsError(try Boc.deserialize(data: boc))
        XCTAssertEqual(try Boc.deserialize(data: boc, checkMerkleProofs: true, checkMerkleMetadata: false).first, shape)
        XCTAssertThrowsError(try Boc.deserialize(data: child.toBoc(), checkMerkleProofs: true))
    }

    func testMaskBoundsAndNegativeCursorOperationsAreSafeAndAtomic() throws {
        XCTAssertEqual(Mask(maskValue: UInt32.max).hashCount, 33)
        XCTAssertFalse(Mask(maskValue: 7).isSignificant(level: UInt32.max))
        let cell = try Cell(bits: [.b1, .b0], refs: [Cell()])
        let slice = cell.parse()
        XCTAssertThrowsError(try slice.skipBits(size: -1))
        XCTAssertThrowsError(try slice.skipRefs(size: -1))
        XCTAssertThrowsError(try slice.loadBytes(size: Int.max))
        XCTAssertThrowsError(try slice.preloadBytes(size: Int.min))
        XCTAssertEqual(slice.bits, cell.bits)
        XCTAssertEqual(slice.refs.count, 1)
        XCTAssertEqual(slice.consumedBits, 0)
        XCTAssertEqual(slice.consumedRefs, 0)
        XCTAssertTrue(slice.sourceCell === cell)
        XCTAssertEqual(try cell.hash(UInt32.max), try cell.hash(3))
        XCTAssertEqual(cell.depth(UInt32.max), cell.depth(3))
    }

    func testSharedDAGAllWriterOptionsAndObjectIdentity() throws {
        let leaf = try Cell(bits: [.b1])
        let middle = try Cell(bits: [.b0], refs: [leaf])
        let first = try Cell(refs: [middle, leaf])
        let second = try Cell(bits: [.b1, .b1], refs: [leaf, middle])
        for indexed in [false, true] {
            for crc in [false, true] {
                for sort in ["breadth-first", "depth-first"] {
                    for cache in indexed ? [false, true] : [false] {
                        let encoded = try Boc.serialize(root: [first, second, middle], options: .init(
                            hasIndex: indexed, hashCrc32: crc, hasCacheBits: cache, topologicalOrder: sort))
                        let decoded = try Boc.deserialize(data: encoded)
                        XCTAssertEqual(decoded, [first, second, middle])
                        XCTAssertTrue(decoded[0].refs[0] === decoded[2])
                        XCTAssertTrue(decoded[0].refs[1] === decoded[1].refs[0])
                        XCTAssertTrue(decoded[1].refs[1] === decoded[2])
                    }
                }
            }
        }
        XCTAssertThrowsError(try Boc.serialize(root: [first, first]))
        XCTAssertThrowsError(try Boc.serialize(root: [], options: .init()))
        XCTAssertThrowsError(try Boc.serialize(root: [first], options: .init(flags: 1)))
        XCTAssertThrowsError(try Boc.serialize(root: [first], options: .init(topologicalOrder: "unknown")))
        XCTAssertThrowsError(try Boc.serialize(root: [first], options: .init(hasCacheBits: true)))
    }

    func testLiteralCumulativeIndexesAndLeanHeaders() throws {
        let leaf = try CellBuilder().storeUInt(1, 8).cell()
        let root = try CellBuilder().storeUInt(2, 8).storeRef(leaf).cell()
        let encoded = try Boc.serialize(root: [root], options: .init(hasIndex: true, hashCrc32: false))
        XCTAssertEqual(Array(encoded), [0xb5, 0xee, 0x9c, 0x72, 0x81, 1, 2, 1, 0, 7, 0, 4, 7, 1, 2, 2, 1, 0, 2, 1])
        var bad = encoded
        bad[11] = 3
        XCTAssertThrowsError(try Boc.deserialize(data: bad))
        XCTAssertEqual(try Boc.deserialize(data: bad, validateIndex: false), [root])
        bad[11] = 8
        XCTAssertThrowsError(try Boc.deserializeHeader(bytes: bad))
        let lean = Data([0x68, 0xff, 0x65, 0xf3, 1, 1, 1, 1, 0, 2, 2, 0, 0])
        XCTAssertEqual(try Boc.deserialize(data: lean), [try Cell()])
        var leanCRC = lean
        leanCRC.replaceSubrange(0..<4, with: [0xac, 0xc3, 0xa7, 0x28])
        leanCRC.append(leanCRC.crc32cBytesLE())
        XCTAssertEqual(try Boc.deserialize(data: leanCRC), [try Cell()])
    }

    func testStoredHashDepthAndMaskChecksIncludingPrunedCells() throws {
        for cell in [try Cell(), try Cell(bits: [.b1]).toPrunedBranch()] {
            let levels = (0...cell.mask.level).filter { cell.mask.isSignificant(level: $0) }
            var body = try (cell.getRefsDescriptor() + cell.getBitsDescriptor()).toBytes()
            body[0] |= 16
            for level in levels { body.append(try cell.hash(level).hexToBytes()) }
            for level in levels { body.append(try Cell.getDepthDescriptor(UInt32(cell.depth(level))).toBytes()) }
            body.append(try cell.getAugmentedBits().toBytes())
            let header = Data([0xb5, 0xee, 0x9c, 0x72, 1, 1, 1, 1, 0, UInt8(body.count), 0])
            XCTAssertEqual(try Boc.deserialize(data: header + body), [cell])
            var bad = body
            bad[2] ^= 1
            XCTAssertThrowsError(try Boc.deserialize(data: header + bad))
            bad = body
            bad[2 + levels.count * 32] ^= 1
            XCTAssertThrowsError(try Boc.deserialize(data: header + bad))
        }
        var badMask = try Boc.serialize(root: [Cell()], options: .init(hashCrc32: false))
        badMask[11] |= 32
        XCTAssertThrowsError(try Boc.deserialize(data: badMask))
    }

    func testTruncationsCRCCompletionTagsAndTrailingBytes() throws {
        let valid = try Cell(bits: [.b1, .b0, .b1], refs: [Cell()]).toBoc()
        for length in 0..<valid.count { XCTAssertThrowsError(try Boc.deserialize(data: Data(valid.prefix(length))), "length=\(length)") }
        var badCRC = valid
        badCRC[badCRC.count - 1] ^= 1
        XCTAssertThrowsError(try Boc.deserialize(data: badCRC))
        XCTAssertThrowsError(try Boc.deserialize(data: valid + Data([0])))
        for terminator: UInt8 in [0, 0x80] {
            let malformed = Data([0xb5, 0xee, 0x9c, 0x72, 1, 1, 1, 1, 0, 3, 0, 0, 1, terminator])
            XCTAssertThrowsError(try Boc.deserialize(data: malformed))
        }
        // Self-reference, backward reference, invalid root and overflowing counters.
        for bytes: [UInt8] in [
            [0xb5, 0xee, 0x9c, 0x72, 1, 1, 1, 1, 0, 3, 0, 1, 0, 0],
            [0xb5, 0xee, 0x9c, 0x72, 1, 1, 2, 1, 0, 5, 0, 0, 0, 1, 0, 0],
            [0xb5, 0xee, 0x9c, 0x72, 1, 1, 1, 1, 0, 2, 1, 0, 0],
            [0xb5, 0xee, 0x9c, 0x72, 4, 8] + Array(repeating: 255, count: 20)
        ] { XCTAssertThrowsError(try Boc.deserialize(data: Data(bytes))) }
    }

    func testTONConstructionBoundAndExplicitEverscaleDecodeBound() throws {
        // Retain ancestors so teardown does not rely on a 2048-frame release cascade.
        var cells = [try Cell()]
        for _ in 0..<1024 { cells.append(try Cell(refs: [cells.last!])) }
        XCTAssertThrowsError(try Cell(refs: [cells.last!]))
        XCTAssertEqual(try Boc.deserialize(data: cells.last!.toBoc()).first?.depth(), 1024)
        XCTAssertThrowsError(try Boc.deserialize(data: cells.last!.toBoc(), maxDepth: 1023))
        for _ in 1024..<2048 { cells.append(try Cell(refs: [cells.last!], compatibility: .everscale)) }
        let encoded = try cells.last!.toBoc()
        XCTAssertThrowsError(try Boc.deserialize(data: encoded))
        XCTAssertEqual(try Boc.deserialize(data: encoded, compatibility: .everscale).first?.depth(), 2048)
        let deeper = try Cell(refs: [cells.last!], compatibility: .everscale)
        XCTAssertThrowsError(try Boc.deserialize(data: deeper.toBoc(), compatibility: .everscale))
        XCTAssertEqual(try Boc.deserialize(data: deeper.toBoc(), maxDepth: 2049, compatibility: .everscale).first?.depth(), 2049)
        while !cells.isEmpty { cells.removeLast() }
    }

    func testDataBackedBigLeafRequiresExplicitReadOptIn() throws {
        let cell = try Cell(bigData: Data([1, 2, 3]))
        let encoded = try Boc.serialize(root: [cell], options: .init(hashCrc32: false))
        XCTAssertEqual(Array(encoded), [0xb6, 0xff, 0x9a, 0x73, 1, 1, 1, 1, 0, 7, 1, 7, 0, 13, 0, 0, 3, 1, 2, 3])
        XCTAssertEqual(try cell.hash(), "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81")
        XCTAssertThrowsError(try Boc.deserialize(data: encoded))
        XCTAssertEqual(try Boc.deserialize(data: encoded, allowBigCells: true).first?.bigData, cell.bigData)
        let megabyte = try Cell(bigData: Data(repeating: 0x42, count: 1024 * 1024))
        XCTAssertEqual(try Boc.deserialize(data: megabyte.toBoc(), allowBigCells: true).first?.bigData, megabyte.bigData)
        XCTAssertEqual(megabyte.bitLength, 8 * 1024 * 1024)
        XCTAssertEqual(megabyte.depth(), 0)
        XCTAssertThrowsError(try Cell(bigData: Data(repeating: 0, count: 0x1000000)))
        XCTAssertThrowsError(try Cell(bits: [], type: .big))
        XCTAssertThrowsError(try Cell(refs: [cell]))
    }
}
