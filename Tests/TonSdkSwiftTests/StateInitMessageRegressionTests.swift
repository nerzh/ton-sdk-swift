import Foundation
import BigInt
import XCTest
@testable import TonSdkSwift

final class StateInitMessageRegressionTests: XCTestCase {
    private func zeroAddress() throws -> Address {
        try Address(address: "0:" + String(repeating: "0", count: 64))
    }

    private func info() throws -> CommonMsgInfo {
        try .extInMsgInfo(.init(dest: zeroAddress()))
    }

    private func bits(_ text: String) -> [Bit] { text.map { $0 == "1" ? .b1 : .b0 } }

    private func library(_ code: Cell) throws -> HashmapE<[Bit], SimpleLib> {
        let dictionary = try HashmapE<[Bit], SimpleLib>(keySize: 256, options: .init(
            serializers: (key: { $0 }, value: { try $0.cell() }),
            deserializers: (key: { $0 }, value: { try SimpleLib.parse($0.parse()) })))
        let key = try CellBuilder().storeUInt(BigUInt(code.hash(), radix: 16)!, 256).bits
        try dictionary.set(key, SimpleLib(options: .init(publicValue: .b0, rootValue: code)))
        return dictionary
    }

    func testSplitDepthPresenceAndInlineTickTockLiteralLayouts() throws {
        for (depth, expected) in [(nil, "00000"), (BigUInt(0), "1000000000"),
                                  (BigUInt(23), "1101110000"), (BigUInt(31), "1111110000")] {
            let state = try StateInit(options: .init(splitDepth: depth))
            let encoded = try state.cell()
            XCTAssertEqual(encoded.bits, bits(expected))
            XCTAssertTrue(encoded.refs.isEmpty)
            XCTAssertEqual(try StateInit.parse(cs: encoded.parse()).data.splitDepth, depth)
        }
        let special = try TickTock(options: .init(tick: .b0, tock: .b1))
        let encoded = try StateInit(options: .init(splitDepth: 23, tickTock: special)).cell()
        XCTAssertEqual(encoded.bits, bits("110111101000"))
        XCTAssertTrue(encoded.refs.isEmpty)
        XCTAssertEqual(try StateInit.parse(cs: encoded.parse()).cell(), encoded)
        XCTAssertThrowsError(try StateInit(options: .init(splitDepth: 32)))
    }

    func testStateFieldReferenceOrderAndLiteralLibraryHash() throws {
        // Public interoperability facts from the upstream handoff; independently
        // constructed TL-B data, without copying EverX implementation/test code.
        let code = try CellBuilder().storeUInt(BigUInt("07fffffffffffffe", radix: 16)!, 61).cell()
        XCTAssertEqual(try code.hash(), "7a0b957a15e93cca3ce96ccb4aecf275a3718a263c8aeca2ab14fe6e1e62172c")
        let libraries = try library(code)
        let special = try TickTock(options: .init(tick: .b0, tock: .b1)).cell()
        let state = try StateInit(options: .init(splitDepth: 23, special: special, code: code, data: code, library: libraries))
        let encoded = try state.cell()
        XCTAssertEqual(encoded.bits, bits("110111101111"))
        XCTAssertEqual(encoded.refs.count, 3)
        XCTAssertTrue(encoded.refs[0] === code)
        XCTAssertTrue(encoded.refs[1] === code)
        XCTAssertEqual(try encoded.refs[2].hash(), "c39760fbba54774b6c7fa76bfd46d6fb89d1fe0b19570bef3c4d08decc8b4566")
        let cursor = encoded.parse()
        let decoded = try StateInit.parse(cs: cursor)
        XCTAssertEqual(try decoded.cell(), encoded)
        XCTAssertTrue(cursor.bits.isEmpty)
        XCTAssertTrue(cursor.refs.isEmpty)
        let alternateCode = try CellBuilder().storeUInt(BigUInt("07ffffe01fe01ffe", radix: 16)!, 61).cell()
        let alternate = try StateInit(options: .init(splitDepth: 31, code: alternateCode, library: libraries)).cell()
        XCTAssertEqual(try StateInit.parse(cs: alternate.parse()).cell(), alternate)
    }

    func testSpecialCellAdapterRejectsNonTickTockAndTickTockMutationIsSerialized() throws {
        for invalid in [try Cell(bits: [.b1]), try Cell(bits: [.b1, .b0, .b0]),
                        try Cell(bits: [.b1, .b0], refs: [Cell(bits: [])])] {
            XCTAssertThrowsError(try StateInit(options: .init(special: invalid)))
        }
        var special = try TickTock(options: .init(tick: .b0, tock: .b0))
        special.data.tick = .b1
        XCTAssertEqual(try special.cell().bits, [.b1, .b0])
    }

    func testAllPlacementCombinationsRoundTripWithExactHashes() throws {
        let code = try Cell(bits: [.b1])
        let state = try StateInit(options: .init(splitDepth: 0, code: code))
        let body = try Cell(bits: [.b0, .b1], refs: [code])
        let message = try Message(options: .init(info: info(), stateInit: state, body: body))
        for stateReference in [false, true] {
            for bodyReference in [false, true] {
                let placement = MessagePlacement(stateInitByReference: stateReference, bodyByReference: bodyReference)
                let encoded = try message.cell(placement: placement)
                let decoded = try Message.parse(cs: encoded.parse())
                XCTAssertEqual(decoded.placement, placement)
                XCTAssertEqual(try decoded.cell().hash(), try encoded.hash())
                XCTAssertEqual(try decoded.data.stateInit?.cell(), try state.cell())
                XCTAssertEqual(decoded.data.body, body)
            }
        }
    }

    func testAutomaticPackingConsidersBuilderBitsAndReferences() throws {
        let leaf = try Cell(bits: [.b1])
        let state = try StateInit(options: .init(code: leaf, data: leaf, library: library(leaf)))
        let tiny = try Cell(bits: [.b1])
        let large = try Cell(bits: Array(repeating: .b1, count: 800))
        // Four reference slots force each of the four valid placement choices.
        for (prefixRefs, body, stateRef, bodyRef) in [
            (0, tiny, false, false), (0, large, false, true),
            (2, tiny, true, false), (2, large, true, true)
        ] {
            let message = try Message(options: .init(info: info(), stateInit: state, body: body))
            let builder = try CellBuilder().storeUInt(0x35, 7)
            for _ in 0..<prefixRefs { try builder.storeRef(leaf) }
            try message.store(to: builder)
            let cursor = try builder.cell().parse()
            XCTAssertEqual(try cursor.loadBigUInt(size: 7), 0x35)
            for _ in 0..<prefixRefs { XCTAssertEqual(try cursor.loadRef(), leaf) }
            let decoded = try Message.parse(cs: cursor)
            XCTAssertEqual(decoded.placement, .init(stateInitByReference: stateRef, bodyByReference: bodyRef))
            XCTAssertEqual(decoded.data.body, body)
        }
        let message = try Message(options: .init(info: info(), body: tiny))
        let prefixed = try CellBuilder().storeBits(Array(repeating: .b0, count: 746))
        try message.store(to: prefixed)
        let cursor = try prefixed.cell().parse().skipBits(size: 746)
        XCTAssertEqual(try Message.parse(cs: cursor).placement?.bodyByReference, true)
    }

    func testMessageMutationChangesBytesAndRepacksDecodedInlineBody() throws {
        let original = try Message(options: .init(info: info(), body: Cell(bits: [.b1])))
        let originalCell = try original.cell()
        var message = try Message.parse(cs: originalCell.parse())
        message.data.body = try Cell(bits: Array(repeating: .b0, count: 900))
        XCTAssertNotEqual(try message.cell().hash(), try originalCell.hash())
        let decoded = try Message.parse(cs: message.cell().parse())
        XCTAssertTrue(try XCTUnwrap(decoded.placement).bodyByReference)
        XCTAssertEqual(decoded.data.body?.bits.count, 900)
        message.data.info = try .extInMsgInfo(.init(dest: zeroAddress(), importFee: Coins(nanoValue: 99)))
        let updated = try Message.parse(cs: message.cell().parse())
        guard case let .extInMsgInfo(header) = updated.data.info else { return XCTFail("Expected inbound header") }
        XCTAssertEqual(header.importFee.nanoValue, 99)
    }

    func testFailedPackingDoesNotMutateDestination() throws {
        let message = try Message(options: .init(info: info(), body: Cell(bits: Array(repeating: .b1, count: 900))))
        let sentinel = try Cell(bits: [.b1])
        let destination = try CellBuilder().storeUInt(37, 8).storeRef(sentinel)
        let oldBits = destination.bits, oldRefs = destination.refs
        XCTAssertThrowsError(try message.store(to: destination, placement: .init(stateInitByReference: false, bodyByReference: false)))
        XCTAssertEqual(destination.bits, oldBits)
        XCTAssertEqual(destination.refs, oldRefs)
        let tooSmall = CellBuilder(size: 100)
        XCTAssertThrowsError(try message.store(to: tooSmall))
        XCTAssertTrue(tooSmall.bits.isEmpty)
        XCTAssertTrue(tooSmall.refs.isEmpty)
    }

    func testUnchangedHeaderKeepsNoncanonicalVarUIntEncoding() throws {
        let header = try CellBuilder().storeUInt(2, 2).storeUInt(0, 2)
            .storeAddress(zeroAddress()).storeUInt(1, 4).storeUInt(0, 8)
        let original = try header.storeBits([.b0, .b0, .b1]).cell()
        let parsed = try Message.parse(cs: original.parse())
        XCTAssertEqual(try parsed.cell().hash(), try original.hash())
    }

    func testReferencedExoticBodyIdentityAndEmptyBodyPlacement() throws {
        let libraryCell = try CellBuilder().storeUInt(2, 8).storeUInt(0, 256).cell(.libraryReference)
        let message = try Message(options: .init(info: info(), body: libraryCell))
        let parsed = try Message.parse(cs: message.cell().parse())
        XCTAssertTrue(try XCTUnwrap(parsed.placement).bodyByReference)
        XCTAssertTrue(parsed.data.body === libraryCell)
        let empty = try Message(options: .init(info: info()))
        let encoded = try empty.cell(placement: .init(stateInitByReference: false, bodyByReference: true))
        XCTAssertEqual(try Message.parse(cs: encoded.parse()).cell(), encoded)
    }

    func testStateLibraryMutationIsNotHiddenByMessageCache() throws {
        let code = try Cell(bits: [.b1])
        let libraries = try library(code)
        let state = try StateInit(options: .init(library: libraries))
        let message = try Message(options: .init(info: info(), stateInit: state))
        let before = try message.cell().hash()
        let secondKey = try CellBuilder().storeUInt(123, 256).bits
        try libraries.set(secondKey, SimpleLib(options: .init(publicValue: .b1, rootValue: code)))
        XCTAssertNotEqual(try message.cell().hash(), before)
    }

    func testMalformedReferencedStateAndInvalidDestinationFailSafely() throws {
        let stateWithTrailingBits = try Cell(bits: [.b0, .b0, .b0, .b0, .b0, .b1])
        let exotic = try CellBuilder().storeUInt(2, 8).storeUInt(0, 256).cell(.libraryReference)
        for state in [stateWithTrailingBits, exotic] {
            let message = try CellBuilder().storeSlice(info().cell().parse())
                .storeBits([.b1, .b1, .b0]).storeRef(state).cell()
            XCTAssertThrowsError(try Message.parse(cs: message.parse()))
        }
        let message = try Message(options: .init(info: info()))
        let invalid = CellBuilder(size: Int.min)
        invalid.bits = [.b1]
        XCTAssertThrowsError(try message.store(to: invalid))
        XCTAssertEqual(invalid.bits, [.b1])
        XCTAssertThrowsError(try StateInit.parse(cs: Cell(bits: [.b0, .b1, .b1]).parse()))
    }
}
