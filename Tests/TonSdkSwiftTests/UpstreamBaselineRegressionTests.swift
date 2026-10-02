import XCTest
@testable import TonSdkSwift

/// These tests use only the pre-fix API and can also run against commit 5dd7e33.
final class UpstreamBaselineRegressionTests: XCTestCase {
    func testZeroMaskHasZeroLevel() {
        XCTAssertEqual(Mask(maskValue: 0).level, 0)
    }

    func testStateInitIncludesSplitDepthPresenceBit() throws {
        let state = try StateInit(options: .init(splitDepth: 23)).cell()
        XCTAssertEqual(state.bits.map { String($0.rawValue) }.joined(), "1101110000")
    }

    func testStateInitStoresTickTockInline() throws {
        let special = try TickTock(options: .init(tick: .b0, tock: .b1)).cell()
        let state = try StateInit(options: .init(special: special)).cell()
        XCTAssertEqual(state.bits.map { String($0.rawValue) }.joined(), "0101000")
        XCTAssertTrue(state.refs.isEmpty)
    }

    func testMutatingMessageBodyChangesSerialization() throws {
        let address = try Address(address: "0:" + String(repeating: "0", count: 64))
        var message = try Message(options: .init(info: .extInMsgInfo(.init(dest: address)), body: Cell(bits: [.b1])))
        let original = try message.cell()
        message.data.body = try Cell(bits: [.b0])
        XCTAssertNotEqual(try message.cell(), original)
    }

    func testAllRootsAndSharedDescendantsSurviveSerialization() throws {
        let leaf = try Cell(bits: [.b1])
        let parent = try Cell(bits: [.b0], refs: [leaf])
        let roots = try Boc.deserialize(data: Boc.serialize(root: [parent, leaf]))
        XCTAssertEqual(roots.count, 2)
        guard roots.count == 2 else { return }
        XCTAssertEqual(try roots[0].hash(), try parent.hash())
        XCTAssertEqual(try roots[1].hash(), try leaf.hash())
    }
}
