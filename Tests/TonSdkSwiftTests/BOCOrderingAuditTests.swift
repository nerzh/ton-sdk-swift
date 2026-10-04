import XCTest
@testable import TonSdkSwift

final class BOCOrderingAuditTests: XCTestCase {
    func testBreadthAndDepthOrdersAreDistinctAndBothRoundTrip() throws {
        let short = try Cell(bits: [.b0])
        let deepLeaf = try Cell(bits: [.b1])
        let middle = try Cell(bits: [.b0, .b1], refs: [deepLeaf])
        let long = try Cell(bits: [.b1, .b0], refs: [middle])
        let root = try Cell(refs: [short, long])
        let breadth = try Boc.breadthFirstSort(root: [root])
        let depth = try Boc.depthFirstSort(root: [root])
        XCTAssertEqual(breadth.cells, [root, short, long, middle, deepLeaf])
        XCTAssertEqual(depth.cells, [root, long, middle, deepLeaf, short])
        let breadthBOC = try Boc.serialize(root: [root], options: .init(hasIndex: true, topologicalOrder: "breadth-first"))
        let depthBOC = try Boc.serialize(root: [root], options: .init(hasIndex: true, topologicalOrder: "depth-first"))
        XCTAssertNotEqual(breadthBOC, depthBOC)
        XCTAssertEqual(try Boc.deserialize(data: breadthBOC), [root])
        XCTAssertEqual(try Boc.deserialize(data: depthBOC), [root])
    }

    func testBreadthFirstWaitsForAllParentsAndPreservesRootAndReferenceOrder() throws {
        let shared = try Cell(bits: [.b1])
        let left = try Cell(bits: [.b0], refs: [shared])
        let right = try Cell(bits: [.b1], refs: [shared, shared])
        let firstRoot = try Cell(bits: [.b0, .b1], refs: [left, shared])
        let secondRoot = try Cell(bits: [.b1, .b0], refs: [right, shared])
        let roots = [firstRoot, secondRoot]
        let sorted = try Boc.breadthFirstSort(root: roots)
        XCTAssertEqual(sorted.cells, [firstRoot, secondRoot, left, right, shared])
        for (index, cell) in sorted.cells.enumerated() {
            for child in cell.refs {
                XCTAssertGreaterThan(try XCTUnwrap(sorted.hashmap[child.hash().lowercased()]), index)
            }
        }
        let decoded = try Boc.deserialize(data: Boc.serialize(root: roots, options: .init(hasIndex: true)))
        XCTAssertEqual(decoded, roots)
        XCTAssertTrue(decoded[0].refs[1] === decoded[1].refs[1])
        XCTAssertTrue(decoded[0].refs[0].refs[0] === decoded[1].refs[1])
        XCTAssertTrue(decoded[1].refs[0].refs[0] === decoded[1].refs[0].refs[1])
    }

    func testRootThatIsAnotherRootsDescendantKeepsRequestedRootListOrder() throws {
        let descendant = try Cell(bits: [.b1])
        let ancestor = try Cell(bits: [.b0], refs: [descendant])
        let roots = [descendant, ancestor]
        XCTAssertEqual(try Boc.breadthFirstSort(root: roots).cells, [ancestor, descendant])
        let encoded = try Boc.serialize(root: roots, options: .init(hasIndex: true))
        XCTAssertEqual(try Boc.deserializeHeader(bytes: encoded).rootList, [1, 0])
        let decoded = try Boc.deserialize(data: encoded)
        XCTAssertEqual(decoded, roots)
        XCTAssertTrue(decoded[0] === decoded[1].refs[0])
    }

}
