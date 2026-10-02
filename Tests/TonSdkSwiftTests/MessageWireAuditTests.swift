import Foundation
import BigInt
import XCTest
@testable import TonSdkSwift

final class MessageWireAuditTests: XCTestCase {
    func testRelaxedSourcesIncludeExternalAddressesInBothOutgoingHeaders() throws {
        // TON block.tlb uses src:MsgAddress for both CommonMsgInfoRelaxed tags.
        // MsgAddress includes addr_extern as well as addr_none and internal forms.
        let source = MessageAddress.external([.b1, .b0, .b1])
        let destination = MessageAddress.standard(workchain: 0, address: Data(repeating: 0, count: 32))
        let headers: [RawCommonMsgInfo] = [
            .internalMessage(.init(src: source, dest: destination, value: try CurrencyCollection(grams: 7))),
            .externalOutbound(.init(src: source, dest: .external([.b0]), createdLt: 1, createdAt: 2))
        ]
        for header in headers {
            XCTAssertThrowsError(try header.cell())
            let encoded = try header.cell(relaxed: true)
            XCTAssertThrowsError(try RawCommonMsgInfo.parse(cs: encoded.parse()))
            XCTAssertEqual(try RawCommonMsgInfo.parse(cs: encoded.parse(), relaxed: true).cell(relaxed: true), encoded)
            XCTAssertEqual(try CommonMsgInfo.parse(cs: encoded.parse()).cell(), encoded)
            let message = try Message(options: .init(info: .raw(header)))
            XCTAssertEqual(try Message.parse(cs: message.cell().parse()).cell(), try message.cell())
        }
    }

    func testLegacyInboundRejectsInternalSourceAndSupportsRawExternalSource() throws {
        let destination = try Address(address: "0:" + String(repeating: "0", count: 64))
        // The legacy optional Address can represent addr_none, but cannot hold
        // addr_extern. Accepting a nonnil value used to write an invalid header.
        XCTAssertThrowsError(try CommonMsgInfo.extInMsgInfo(.init(src: destination, dest: destination)).cell())
        let valid = try CommonMsgInfo.extInMsgInfo(.init(dest: destination)).cell()
        XCTAssertEqual(try CommonMsgInfo.parse(cs: valid.parse()).cell(), valid)
        let external = CommonMsgInfo.raw(.externalInbound(.init(
            src: .external([.b1]), dest: MessageAddress(destination))))
        XCTAssertEqual(try CommonMsgInfo.parse(cs: external.cell().parse()).cell(), try external.cell())
    }

    func testStateInitRejectsIncorrectLibraryKeyWidthIncludingMutation() throws {
        let invalid = try HashmapE<[Bit], SimpleLib>(keySize: 255)
        XCTAssertThrowsError(try StateInit(options: .init(library: invalid)))
        let libraries = try HashmapE<[Bit], SimpleLib>(keySize: 256)
        let state = try StateInit(options: .init(library: libraries))
        libraries.keySize = 255
        XCTAssertThrowsError(try state.cell())
        libraries.keySize = 256
        XCTAssertEqual(try state.cell().bits, [.b0, .b0, .b0, .b0, .b0])
    }

    func testStateInitRejectsMalformedSimpleLibLeavesWithoutDiscardingData() throws {
        let code = try Cell(bits: [.b1])
        let invalidValues = [
            try Cell(bits: [], refs: [code]),
            try Cell(bits: [.b0, .b1], refs: [code]),
            try Cell(bits: [.b0]),
            try Cell(bits: [.b0], refs: [code, code])
        ]
        for value in invalidValues {
            // hml_same$11 v=0 n=256, followed by the invalid SimpleLib value.
            let root = try CellBuilder().storeBits([.b1, .b1, .b0]).storeUInt(256, 9)
                .storeSlice(value.parse()).cell()
            let state = try CellBuilder().storeBits([.b0, .b0, .b0, .b0, .b1]).storeRef(root).cell()
            XCTAssertThrowsError(try StateInit.parse(cs: state.parse()))
        }
    }

    func testStateInitPreservesNonminimalLibraryLabelsAndAllowsValidUpdates() throws {
        let code = try Cell(bits: [.b1])
        // A long label is valid even though this homogeneous key has a shorter
        // same-label encoding. Parsing must retain its original root hash.
        let root = try CellBuilder().storeBits([.b1, .b0]).storeUInt(256, 9)
            .storeBits(Array(repeating: .b0, count: 256)).storeBit(.b0).storeRef(code).cell()
        let encoded = try CellBuilder().storeBits([.b0, .b0, .b0, .b0, .b1]).storeRef(root).cell()
        let state = try StateInit.parse(cs: encoded.parse())
        XCTAssertEqual(try state.cell().hash(), try encoded.hash())
        let libraries = try XCTUnwrap(state.data.library)
        let key = Array(repeating: Bit.b0, count: 256)
        try libraries.set(key, SimpleLib(options: .init(publicValue: .b1, rootValue: code)))
        let changed = try StateInit.parse(cs: state.cell().parse())
        XCTAssertEqual(try changed.data.library?.get(key)?.data.public, .b1)
        XCTAssertNotEqual(try state.cell().hash(), try encoded.hash())
    }
}
