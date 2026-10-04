import XCTest
import BigInt
@testable import TonSdkSwift

final class DictionaryAuditRegressionTests: XCTestCase {
    func testLegacyOptionWidthMustAgreeWithExplicitWidth() throws {
        XCTAssertNoThrow(try Hashmap<[Bit], Cell>(keySize: 8))
        XCTAssertNoThrow(try Hashmap<[Bit], Cell>(keySize: 8, options: .init(keySize: 8)))
        XCTAssertNoThrow(try HashmapE<[Bit], Cell>(keySize: 0, options: .init(keySize: 0)))
        XCTAssertThrowsError(try Hashmap<[Bit], Cell>(keySize: 8, options: .init(keySize: 7)))
        XCTAssertThrowsError(try HashmapE<[Bit], Cell>(keySize: 8, options: .init(keySize: -1)))
        let cursor = CellSlice(bits: [.b0, .b1], refs: [])
        XCTAssertThrowsError(try HashmapE<[Bit], Cell>.parse(keySize: 8, slice: cursor,
                                                          options: .init(keySize: 7)))
        XCTAssertEqual(cursor.bits, [.b0, .b1])
    }

    func testEagerEnvelopeFailuresLeaveCallerCursorUnchanged() throws {
        let value = try Cell(bits: [.b1])
        let malformed = try Cell(bits: [.b0, .b0], refs: [value])
        let pruned = try value.toPrunedBranch()
        for refs in [[], [malformed], [pruned]] {
            let cursor = CellSlice(bits: [.b1, .b0, .b1], refs: refs)
            XCTAssertThrowsError(try HashmapE<[Bit], Cell>.parse(keySize: 2, slice: cursor))
            XCTAssertEqual(cursor.bits, [.b1, .b0, .b1])
            XCTAssertEqual(cursor.refs, refs)
        }
        let empty = CellSlice(bits: [.b0, .b1], refs: [value])
        XCTAssertThrowsError(try HashmapE<[Bit], Cell>.parse(keySize: -1, slice: empty))
        XCTAssertEqual(empty.bits, [.b0, .b1])
        XCTAssertEqual(empty.refs, [value])
    }

    func testEagerRootFailureLeavesCallerCursorUnchanged() throws {
        let cursor = CellSlice(bits: [.b0, .b0], refs: [try Cell()])
        let originalRefs = cursor.refs
        XCTAssertThrowsError(try Hashmap<[Bit], Cell>.parse(keySize: 2, slice: cursor))
        XCTAssertEqual(cursor.bits, [.b0, .b0])
        XCTAssertEqual(cursor.refs, originalRefs)
    }

    func testEagerReadersRejectKnownExoticSourceBeforeReadingTag() throws {
        let leaf = try Cell(bits: [.b1])
        let exotic = try leaf.toMerkleProof()
        for eagerEnvelope in [false, true] {
            let cursor = exotic.parse()
            if eagerEnvelope {
                XCTAssertThrowsError(try HashmapE<[Bit], Cell>.parse(keySize: 0, slice: cursor))
            } else {
                XCTAssertThrowsError(try Hashmap<[Bit], Cell>.parse(keySize: 0, slice: cursor))
            }
            XCTAssertEqual(cursor.bits, exotic.bits)
            XCTAssertEqual(cursor.refs, exotic.refs)
        }
    }

}
