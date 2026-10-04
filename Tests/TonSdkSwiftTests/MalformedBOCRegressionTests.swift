import Foundation
import TonSdkSwift
import XCTest

final class MalformedBOCRegressionTests: XCTestCase {
    // Locally constructed BOC: one ordinary leaf containing the UTF-8 bytes "SDK".
    // Each negative case changes a named wire field; no external fuzz corpus is used.
    private let leafBOC = Data([
        0xb5, 0xee, 0x9c, 0x72, 1, 1, 1, 1, 0, 5, 0,
        0, 6, 0x53, 0x44, 0x4b,
    ])

    func testLocalFixtureAndEveryTruncation() throws {
        let expected = try CellBuilder().storeBytes(Data("SDK".utf8)).cell()
        do {
            XCTAssertEqual(try Boc.deserialize(data: leafBOC), [expected])
            for length in 0..<leafBOC.count {
                XCTAssertThrowsError(try Boc.deserialize(
                    data: Data(leafBOC.prefix(length))), "length=\(length)")
            }
            XCTAssertThrowsError(try Boc.deserialize(data: leafBOC + Data([0x53])))
        }
    }

    func testInvalidIntegerWidths() throws {
        for (offset, values): (Int, [UInt8]) in [(4, [0, 5, 6, 7]), (5, [0, 9, 255])] {
            for value in values {
                var bytes = leafBOC
                bytes[offset] = value
                XCTAssertThrowsError(try Boc.deserialize(data: bytes), "offset=\(offset), value=\(value)")
            }
        }
    }

    func testReservedFlagsAndCacheWithoutIndex() throws {
        for flag: UInt8 in [0x08, 0x10, 0x20] {
            var bytes = leafBOC
            bytes[4] |= flag
            XCTAssertThrowsError(try Boc.deserialize(data: bytes))
        }
    }

    func testInconsistentCountsSizesAndRootIndexes() throws {
        for (offset, values): (Int, [UInt8]) in [
            (6, [0, 2, 255]), (7, [0, 2, 255]), (8, [1, 255]),
            (9, [0, 4, 6, 255]), (10, [1, 255]),
        ] {
            for value in values {
                var bytes = leafBOC
                bytes[offset] = value
                XCTAssertThrowsError(try Boc.deserialize(data: bytes), "offset=\(offset), value=\(value)")
            }
        }
    }

    func testOversizedEightBytePayloadLength() throws {
        for leadingByte: UInt8 in [0x7f, 0x80, 0xff] {
            var bytes = leafBOC
            bytes[5] = 8
            bytes.replaceSubrange(9..<10, with: [leadingByte] + Array(repeating: UInt8.max, count: 7))
            XCTAssertThrowsError(try Boc.deserialize(data: bytes))
        }
    }

    func testInvalidCellDescriptorsAndUnconsumedCellData() throws {
        // Too many references, absent cell, missing stored hashes, unknown exotic type,
        // and level masks that do not agree with an ordinary leaf.
        for descriptor: UInt8 in [5, 6, 7, 0x17, 0x10, 0x08, 0x20, 0x60, 0xe0] {
            var bytes = leafBOC
            bytes[11] = descriptor
            XCTAssertThrowsError(try Boc.deserialize(data: bytes), "descriptor=\(descriptor)")
        }
        var extraCell = leafBOC
        extraCell[9] += 2
        extraCell.append(contentsOf: [0, 0])
        XCTAssertThrowsError(try Boc.deserialize(data: extraCell))
    }

    func testReferenceCyclesAndMissingChildren() throws {
        // Extend the local fixture with a reference to a second, empty cell.
        var parent = leafBOC
        parent[6] = 2
        parent[9] = 8
        parent[11] = 1
        parent.append(contentsOf: [1, 0, 0])
        let decoded = try Boc.deserialize(data: parent)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.refs.count, 1)
        for index: UInt8 in [0, 2, 255] {
            var bytes = parent
            bytes[16] = index
            XCTAssertThrowsError(try Boc.deserialize(data: bytes), "reference=\(index)")
        }
    }

    func testLeanHeaderCountsIndexesAndTruncations() throws {
        var lean = leafBOC
        lean.replaceSubrange(0..<4, with: [0x68, 0xff, 0x65, 0xf3])
        lean[10] = 5 // Lean BOC omits the root list and requires a cumulative index.
        XCTAssertEqual(try Boc.deserialize(data: lean), try Boc.deserialize(data: leafBOC))
        for (offset, values): (Int, [UInt8]) in [(6, [0, 2]), (7, [0, 2]), (10, [0, 4, 6])] {
            for value in values {
                var bytes = lean
                bytes[offset] = value
                XCTAssertThrowsError(try Boc.deserialize(data: bytes), "offset=\(offset), value=\(value)")
            }
        }
        for length in 0..<lean.count {
            XCTAssertThrowsError(try Boc.deserialize(data: Data(lean.prefix(length))), "length=\(length)")
        }
    }

    func testEverscaleBigBOCIsRejected() throws {
        let big = Data([0xb6, 0xff, 0x9a, 0x73, 1, 1, 1, 1, 0, 7, 1, 7, 0, 13, 0, 0, 3, 1, 2, 3])
        XCTAssertThrowsError(try Boc.deserializeHeader(bytes: big))
        XCTAssertThrowsError(try Boc.deserialize(data: big))
    }
}
