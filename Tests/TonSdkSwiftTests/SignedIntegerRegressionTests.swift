import BigInt
import Foundation
import TonSdkSwift
import XCTest

final class SignedIntegerRegressionTests: XCTestCase {
    func testKnownNegativeWireValues() throws {
        XCTAssertEqual(Array(try CellBuilder().storeInt(-127, 8).bytes()), [0x81])
        XCTAssertEqual(Array(try CellBuilder().storeInt(-3, 8).bytes()), [0xfd])
        XCTAssertEqual(Array(try CellBuilder().storeInt(-239, 32).bytes()), [0xff, 0xff, 0xff, 0x11])
    }

    func testEverySignedByteMatchesNativeBitPattern() throws {
        for value in Int(Int8.min)...Int(Int8.max) {
            let builder = try CellBuilder().storeInt(BigInt(value), 8)
            XCTAssertEqual(try builder.bytes(), Data([UInt8(bitPattern: Int8(value))]), "value: \(value)")
            XCTAssertEqual(try builder.cell().parse().loadBigInt(size: 8), BigInt(value), "value: \(value)")
        }
    }

    func testNonByteAlignedAndWideNegativeValues() throws {
        let narrow = try CellBuilder().storeInt(-3, 7)
        XCTAssertEqual(narrow.bits, [.b1, .b1, .b1, .b1, .b1, .b0, .b1])
        XCTAssertEqual(try narrow.cell().parse().loadBigInt(size: 7), -3)

        let builder = try CellBuilder().storeInt(-3, 257)
        XCTAssertEqual(builder.bits, Array(repeating: Bit.b1, count: 255) + [.b0, .b1])
        XCTAssertEqual(try builder.cell().parse().loadBigInt(size: 257), -3)

        let minimum = -(BigInt(1) << 255)
        let wide = try CellBuilder().storeInt(minimum + 1, 256)
        XCTAssertEqual(try wide.bytes(), Data([0x80] + Array(repeating: UInt8(0), count: 30) + [1]))
        XCTAssertEqual(try wide.cell().parse().loadBigInt(size: 256), minimum + 1)
    }

    func testSignedBoundariesAndRejectedValuesPreserveBuilder() throws {
        let reference = try CellBuilder().cell()
        for size in [1, 7, 8, 32, 257] {
            let limit = BigInt(1) << (size - 1)
            for value in [-limit, limit - 1] {
                let builder = try CellBuilder().storeInt(value, size)
                let expected: [Bit] = value < 0
                    ? [.b1] + Array(repeating: .b0, count: size - 1)
                    : [.b0] + Array(repeating: .b1, count: size - 1)
                XCTAssertEqual(builder.bits, expected, "size: \(size), value: \(value)")
                XCTAssertEqual(try builder.cell().parse().loadBigInt(size: size), value)
            }
            for value in [-limit - 1, limit] {
                let builder = try CellBuilder().storeBit(.b1).storeRef(reference)
                XCTAssertThrowsError(try builder.storeInt(value, size))
                XCTAssertEqual(builder.bits, [.b1])
                XCTAssertEqual(builder.refs.count, 1)
                XCTAssertTrue(builder.refs.first === reference)
                XCTAssertEqual(builder.size, 1023)
                XCTAssertEqual(builder.remainder, 1022)
            }
        }
    }

    func testInsufficientCapacityLeavesBuilderUnchanged() throws {
        let reference = try CellBuilder().cell()
        for prefixSize in [1, 8] {
            let builder = try CellBuilder(size: 8).storeUInt(1, prefixSize).storeRef(reference)
            let originalBits = builder.bits
            for value: BigInt in [-3, 0, 3] {
                XCTAssertThrowsError(try builder.storeInt(value, 8))
                XCTAssertEqual(builder.bits, originalBits)
                XCTAssertEqual(builder.refs.count, 1)
                XCTAssertTrue(builder.refs.first === reference)
                XCTAssertEqual(builder.size, 8)
                XCTAssertEqual(builder.remainder, 8 - prefixSize)
            }
        }
        let exact = try CellBuilder(size: 8).storeBit(.b1).storeInt(-3, 7)
        XCTAssertEqual(try exact.bytes(), Data([0xfd]))
        XCTAssertEqual(exact.remainder, 0)
    }

    func testVariableSignedIntegerPayloadUsesTwosComplement() throws {
        for (value, expected): (BigInt, [UInt8]) in [(-127, [0x81]), (-3, [0xfd]), (-239, [0xff, 0x11])] {
            let slice = try CellBuilder().storeVarInt(value, 8).cell().parse()
            XCTAssertEqual(try slice.loadBigUInt(size: 3), BigUInt(expected.count))
            XCTAssertEqual(try slice.loadBytes(size: expected.count), Data(expected))
            XCTAssertTrue(slice.bits.isEmpty)
        }
    }

    func testInvalidSignedWidthsLeaveBuilderUnchanged() throws {
        let reference = try CellBuilder().cell()
        for size in [Int.min, -1, 0, 1023, 1024, Int.max] {
            for value: BigInt in [-3, 0, 3] {
                let builder = try CellBuilder().storeBit(.b1).storeRef(reference)
                XCTAssertThrowsError(try builder.storeInt(value, size))
                XCTAssertEqual(builder.bits, [.b1])
                XCTAssertEqual(builder.refs.count, 1)
                XCTAssertTrue(builder.refs.first === reference)
                XCTAssertEqual(builder.size, 1023)
                XCTAssertEqual(builder.remainder, 1022)
            }
        }
    }

    func testStandardAddressWriterPreservesEveryWorkchainByte() throws {
        let hash = Data(repeating: 0x11, count: 32)
        for value in Int(Int8.min)...Int(Int8.max) {
            let workchain = Int8(value)
            let address = try Address(address: "0:" + String(repeating: "11", count: 32), workchain: workchain)
            let cell = try CellBuilder().storeAddress(address).cell()
            XCTAssertEqual(cell.bits.count, 267)
            let slice = cell.parse()
            XCTAssertEqual(try slice.loadBigUInt(size: 3), 4)
            XCTAssertEqual(try slice.loadBigUInt(size: 8), BigUInt(UInt8(bitPattern: workchain)), "workchain: \(value)")
            XCTAssertEqual(try slice.loadBytes(size: 32), hash)
            XCTAssertTrue(slice.bits.isEmpty)
        }
    }
}
