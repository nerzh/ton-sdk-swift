import Foundation
import XCTest
@testable import TonSdkSwift

final class CellCoreAuditTests: XCTestCase {
    func testCompatibilityExampleDistinguishesGappedMaskHashing() throws {
        let leaf = try Cell()
        let branch = try leaf.prunedBranch(merkleDepth: 1)
        let ton = try Cell(refs: [branch])
        let ever = try Cell(refs: [branch], compatibility: .everscale)
        XCTAssertEqual(branch.mask.value, 2)
        XCTAssertEqual(ton.compatibility, .ton)
        XCTAssertNotEqual(try ton.hash(), try ever.hash())
        XCTAssertEqual(try Boc.deserialize(data: ton.toBoc()).first, ton)
        XCTAssertEqual(try Boc.deserialize(data: ever.toBoc(), compatibility: .everscale).first, ever)
    }

    func testMaskOperationsRetainAllThirtyTwoBits() {
        for width in 0...32 {
            let value: UInt32 = width == 32 ? .max : (UInt32(1) << width) - 1
            let mask = Mask(maskValue: value)
            XCTAssertEqual(mask.level, UInt32(width))
            XCTAssertEqual(mask.hashIndex, UInt32(width))
            XCTAssertEqual(mask.hashCount, UInt32(width + 1))
            for level in 0...33 {
                let expected: UInt32 = level >= width ? value : (UInt32(1) << level) - 1
                XCTAssertEqual(mask.apply(level: UInt32(level)).value, expected)
                XCTAssertEqual(mask.isSignificant(level: UInt32(level)), level <= width)
            }
            XCTAssertEqual(mask.apply(level: .max).value, value)
            XCTAssertFalse(mask.isSignificant(level: .max))
        }
        let sparse = Mask(maskValue: 0x8000_0101)
        XCTAssertEqual(sparse.level, 32)
        XCTAssertEqual(sparse.hashCount, 4)
        XCTAssertEqual(sparse.apply(level: 8).value, 1)
        XCTAssertEqual(sparse.apply(level: 16).value, 257)
        XCTAssertEqual(sparse.apply(level: 32).value, sparse.value)
        XCTAssertTrue(sparse.isSignificant(level: 32))
        XCTAssertFalse(sparse.isSignificant(level: 31))
    }

    func testAddressWriterRejectsInvalidMutableHashWithoutChangingBuilder() throws {
        var address = try Address(address: "0:" + String(repeating: "0", count: 64))
        for count in [0, 1, 31, 33] {
            address.hash = Data(repeating: 0, count: count)
            let builder = try CellBuilder().storeBit(.b1)
            XCTAssertThrowsError(try builder.storeAddress(address))
            XCTAssertEqual(builder.bits, [.b1])
        }
        address.hash = Data(repeating: 0xab, count: 32)
        let cell = try CellBuilder().storeAddress(address).cell()
        XCTAssertEqual(cell.bits.count, 267)
        XCTAssertEqual(try cell.parse().loadAddress(), address)
    }

    func testSliceDictionaryReadersPreserveCursorAndSourceValidation() throws {
        let invalid = try Cell(bits: [.b0, .b0])
        let slice = CellSlice(bits: [.b1, .b0], refs: [invalid])
        XCTAssertThrowsError(try slice.loadDict(keySize: 1) as HashmapE<Int, Cell>)
        XCTAssertEqual(slice.bits, [.b1, .b0])
        XCTAssertTrue(slice.refs.first === invalid)
        let exotic = try Cell().toMerkleProof().parse()
        XCTAssertThrowsError(try exotic.preloadDict(keySize: 1) as HashmapE<Int, Cell>)
        XCTAssertThrowsError(try exotic.loadDict(keySize: 1) as HashmapE<Int, Cell>)
        XCTAssertEqual(exotic.consumedBits, 0)
        XCTAssertEqual(exotic.consumedRefs, 0)
    }
}
