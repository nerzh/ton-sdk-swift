import Foundation
import BigInt
import XCTest
@testable import TonSdkSwift

final class MessageWireRegressionTests: XCTestCase {
    private let identifier = Data(repeating: 0xa5, count: 32)

    func testAllAddressTagsLengthsAndFollowingField() throws {
        let anycast = try Anycast(rewritePrefix: [.b1, .b0, .b1])
        let addresses: [(MessageAddress, Int, BigUInt)] = [
            (.none, 2, 0), (.external([.b1, .b0, .b1]), 14, 1),
            (.standard(workchain: -1, address: identifier), 267, 2),
            (.standard(workchain: -128, address: identifier, anycast: anycast), 275, 2),
            (.variable(workchain: -65536, address: [.b1, .b0], anycast: anycast), 54, 3)
        ]
        for (address, length, tag) in addresses {
            let cell = try address.cell()
            XCTAssertEqual(cell.bits.count, length)
            XCTAssertEqual(try cell.parse().loadBigUInt(size: 2), tag)
            let builder = try CellBuilder().storeSlice(cell.parse()).storeUInt(19, 5)
            let cursor = try builder.cell().parse()
            XCTAssertEqual(try MessageAddress.parse(cs: cursor), address)
            XCTAssertEqual(try cursor.loadBigUInt(size: 5), 19)
            XCTAssertTrue(cursor.bits.isEmpty)
        }
        let external = try MessageAddress.external([.b1, .b0, .b1]).cell()
        XCTAssertEqual(external.bits.map(\.description).joined(), "01000000011101")
        let standard = try MessageAddress.standard(workchain: -1, address: identifier).cell()
        XCTAssertEqual(Array(standard.bits.prefix(11)).map(\.description).joined(), "10011111111")
    }

    func testAddressValidationAndFriendlyAdapterAreSeparate() throws {
        XCTAssertThrowsError(try Anycast(rewritePrefix: []))
        XCTAssertThrowsError(try Anycast(rewritePrefix: Array(repeating: .b0, count: 31)))
        XCTAssertThrowsError(try MessageAddress.standard(workchain: 0, address: Data([0])).cell())
        XCTAssertThrowsError(try MessageAddress.external(Array(repeating: .b0, count: 512)).cell())
        XCTAssertThrowsError(try MessageAddress.variable(workchain: 0, address: Array(repeating: .b0, count: 512)).cell())
        let boundary = MessageAddress.external(Array(repeating: .b1, count: 511))
        XCTAssertEqual(try MessageAddress.parse(cs: boundary.cell().parse()), boundary)
        let raw = MessageAddress.standard(workchain: -128, address: identifier)
        XCTAssertEqual(try raw.asAddress()?.workchain, -128)
        XCTAssertEqual(try raw.asAddress()?.hash, identifier)
        XCTAssertThrowsError(try MessageAddress.variable(workchain: 0, address: []).asAddress())
        XCTAssertThrowsError(try MessageAddress.standard(workchain: 0, address: identifier,
            anycast: Anycast(rewritePrefix: [.b1])).asAddress())
        let friendly = try Address(address: "0:" + String(repeating: "00", count: 32))
        XCTAssertEqual(try MessageAddress(friendly).asAddress(), friendly)
        for invalidDepth in [0, 31] {
            let input = try CellBuilder().storeUInt(2, 2).storeBit(.b1).storeUInt(BigUInt(invalidDepth), 5).cell().parse()
            XCTAssertThrowsError(try MessageAddress.parse(cs: input))
        }
    }

    func testCurrencyWidthsLiteralEncodingAndDictionaryValueCopies() throws {
        let empty = try CurrencyCollection()
        XCTAssertEqual(try empty.cell().bits, [.b0, .b0, .b0, .b0, .b0])
        var value = try CurrencyCollection(grams: 1)
        try value.setAmount(0, for: 0)
        let cell = try value.cell()
        XCTAssertEqual(cell.bits.map(\.description).joined(), "0001000000011")
        // hml_same$11, value=0, length=32 (six bits), VarUInteger32 zero (five bits).
        XCTAssertEqual(cell.refs[0].bits.map(\.description).joined(), "11010000000000")
        var copy = value
        try copy.setAmount((BigUInt(1) << 248) - 1, for: UInt32.max)
        XCTAssertNil(try value.amount(for: UInt32.max))
        XCTAssertEqual(try copy.amount(for: UInt32.max), (BigUInt(1) << 248) - 1)
        let decoded = try CurrencyCollection.parse(cs: copy.cell().parse())
        XCTAssertEqual(try decoded.cell().hash(), try copy.cell().hash())
        XCTAssertEqual(try decoded.amount(for: 0), 0)
        XCTAssertEqual(try decoded.amount(for: UInt32.max), (BigUInt(1) << 248) - 1)
        var identifiers: [UInt32] = []
        try copy.forEachAmount { key, _ in identifiers.append(key); return true }
        XCTAssertEqual(identifiers, [0, UInt32.max])
        var removed = copy
        XCTAssertTrue(try removed.removeAmount(for: 0))
        XCTAssertFalse(try removed.removeAmount(for: 0))
        XCTAssertNil(try removed.amount(for: 0))
        XCTAssertEqual(try copy.amount(for: 0), 0)
        let before = try copy.cell().hash()
        XCTAssertThrowsError(try copy.setAmount(BigUInt(1) << 248, for: 1))
        XCTAssertEqual(try copy.cell().hash(), before)
        XCTAssertThrowsError(try CurrencyCollection(grams: BigUInt(1) << 120))
        copy.grams = BigUInt(1) << 120
        XCTAssertThrowsError(try copy.cell())
    }

    func testCurrencyReadLeavesEnclosingFieldsAndPreservesNoncanonicalRoot() throws {
        // Full 32-bit short label is legal even though hml_same would be shorter.
        let root = try CellBuilder().storeBit(.b0).storeBits(Array(repeating: .b1, count: 32))
            .storeBit(.b0).storeBits(Array(repeating: .b0, count: 32)).storeUInt(0, 5).cell()
        let currency = try CurrencyCollection(grams: 0, otherRoot: root)
        let cursor = try CellBuilder().storeSlice(currency.cell().parse()).storeUInt(3, 2).cell().parse()
        let parsed = try CurrencyCollection.parse(cs: cursor)
        XCTAssertTrue(parsed.other.root === root)
        XCTAssertEqual(try parsed.amount(for: 0), 0)
        XCTAssertEqual(try cursor.loadBigUInt(size: 2), 3)
        XCTAssertEqual(try parsed.cell(), try currency.cell())
        let invalidValue = try CellBuilder().storeBit(.b1).storeBit(.b1).storeBit(.b0).storeUInt(32, 6)
            .storeUInt(0, 5).storeBit(.b1).cell()
        XCTAssertThrowsError(try CurrencyCollection(otherRoot: invalidValue).amount(for: 0))
    }

    func testRawHeadersSupportOutboundVariableAnycastAndExtraCurrencies() throws {
        let standard = MessageAddress.standard(workchain: 0, address: identifier)
        let variable = MessageAddress.variable(workchain: 1024, address: [.b1, .b0, .b1],
                                              anycast: try Anycast(rewritePrefix: [.b1]))
        var currencies = try CurrencyCollection(grams: 100)
        try currencies.setAmount(123, for: 0xffff_ffff)
        let headers: [RawCommonMsgInfo] = [
            .internalMessage(.init(src: standard, dest: variable, value: currencies, ihrFee: 2, fwdFee: 3, createdLt: 4, createdAt: 5)),
            .externalInbound(.init(src: .external([.b0, .b1]), dest: variable, importFee: 9)),
            .externalOutbound(.init(src: standard, dest: .external([.b1]), createdLt: 10, createdAt: 11))
        ]
        for header in headers {
            let encoded = try header.cell()
            let decoded = try RawCommonMsgInfo.parse(cs: encoded.parse())
            XCTAssertEqual(try decoded.cell(), encoded)
            let facade = try CommonMsgInfo.parse(cs: encoded.parse())
            XCTAssertEqual(try facade.cell(), encoded)
            let message = try Message(options: .init(info: facade, body: Cell(bits: [.b1])))
            XCTAssertEqual(try Message.parse(cs: message.cell().parse()).cell(), try message.cell())
        }
        let external = CommonMsgInfo.extOutMsgInfo(.init(src: standard, dest: .none, createdLt: 7, createdAt: 8))
        let encoded = try external.cell()
        XCTAssertEqual(Array(encoded.bits.prefix(2)), [.b1, .b1])
        guard case let .extOutMsgInfo(parsed) = try CommonMsgInfo.parse(cs: encoded.parse()) else {
            return XCTFail("Expected external outbound header")
        }
        XCTAssertEqual(parsed.createdLt, 7)
        XCTAssertEqual(parsed.createdAt, 8)
    }

    func testStrictAndRelaxedHeaderValidation() throws {
        let standard = MessageAddress.standard(workchain: 0, address: identifier)
        let relaxed = RawCommonMsgInfo.internalMessage(.init(dest: standard, value: try CurrencyCollection()))
        XCTAssertThrowsError(try relaxed.cell())
        let cell = try relaxed.cell(relaxed: true)
        XCTAssertThrowsError(try RawCommonMsgInfo.parse(cs: cell.parse()))
        XCTAssertEqual(try RawCommonMsgInfo.parse(cs: cell.parse(), relaxed: true).cell(relaxed: true), cell)
        XCTAssertThrowsError(try RawCommonMsgInfo.externalInbound(.init(src: standard, dest: standard)).cell())
        XCTAssertThrowsError(try RawCommonMsgInfo.externalOutbound(.init(src: standard, dest: standard)).cell())
        XCTAssertThrowsError(try RawCommonMsgInfo.internalMessage(.init(src: standard, dest: .none,
                                                                       value: CurrencyCollection())).cell())
    }
}
