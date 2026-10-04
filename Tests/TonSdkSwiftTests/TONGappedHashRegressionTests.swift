import Foundation
import XCTest
@testable import TonSdkSwift

final class TONGappedHashRegressionTests: XCTestCase {
    // Fixed preimages and hashes from the TON branch of the original SDK audit.
    // TON DataCell::compute_hash uses the applied mask, including its gaps.
    func testGappedMaskRetainsTONHigherHashDescriptor() throws {
        let payload = try "010278b55d6113eba6bc4ae107b4442afa416b6bc9709b3146657e358e68fa994c340000".hexToBytes()
        let branch = try Cell(bits: payload.toBits(), type: .prunedBranch)
        let parent = try Cell(bits: Data([3, 3, 3]).toBits(), refs: [branch])
        XCTAssertEqual(parent.mask.value, 2)
        XCTAssertEqual(try parent.hash(0), "093fed1748edf1bbb14e25dbbae22e8015c021831ccdc9e2427e145e24aac8c1")
        XCTAssertEqual(try parent.hash(2), "56cd433ccab3cd18856603fa03545e378b17240091a4fd7298ee606e66236fd1")
        XCTAssertEqual(try Boc.deserialize(data: parent.toBoc()), [parent])
    }
}
