import BigInt
import Foundation
import TonSdkSwift
import XCTest

final class CellViewsRegressionTests: XCTestCase {
    private func leaf(_ value: Int) throws -> Cell { try CellBuilder().storeUInt(BigUInt(value), 8).cell() }

    func testHashReadsAndIndependentCursorCreationDoNotVisit() throws {
        let left = try leaf(1), right = try leaf(2)
        let root = try CellBuilder().storeUInt(3, 8).storeRefs([left, right]).cell()
        let usage = UsageTree(root: root)
        let wrapped = usage.rootCell()
        XCTAssertEqual(try wrapped.hash(), try root.hash())
        XCTAssertEqual(wrapped.depth(), root.depth())
        let first = wrapped.parse(), second = wrapped.parse()
        let third = CellSlice.parse(cell: wrapped)
        XCTAssertTrue(usage.buildVisitedSet().isEmpty)
        XCTAssertTrue(first.sourceCell === wrapped)
        XCTAssertTrue(third.sourceCell === wrapped)
        let firstLeft = try first.loadRef()
        XCTAssertEqual(usage.buildVisitedSet(), try Set([root.hash()]))
        XCTAssertEqual(try firstLeft.parse().loadBigUInt(size: 8), 1)
        XCTAssertEqual(usage.buildVisitedSet(), try Set([root.hash(), left.hash()]))
        XCTAssertTrue(try second.loadRef().isEqual(left))
        XCTAssertEqual(try first.loadBigUInt(size: 8), 3)
        XCTAssertEqual(try second.loadBigUInt(size: 8), 3)
        XCTAssertFalse(try usage.contains(right.hash()))
    }

    func testVisitOnLoadIndividualReferenceAndWholeArray() throws {
        let left = try leaf(1), right = try leaf(2)
        let root = try Cell(refs: [left, right])
        let usage = UsageTree(root: root, visitOnLoad: true)
        let cursor = usage.rootCell().parse()
        XCTAssertEqual(usage.buildVisitedSet(), try Set([root.hash()]))
        _ = try cursor.preloadRef()
        XCTAssertEqual(usage.buildVisitedSet(), try Set([root.hash(), left.hash()]))
        _ = try cursor.loadRef()
        XCTAssertFalse(try usage.contains(right.hash()))
        _ = cursor.refs
        XCTAssertTrue(try usage.contains(right.hash()))

        let another = UsageTree(root: root, visitOnLoad: true)
        _ = try another.rootCell().reference(at: 0)
        XCTAssertFalse(try another.contains(right.hash()))
        XCTAssertThrowsError(try another.rootCell().reference(at: -1))
        _ = another.rootCell().refs
        XCTAssertEqual(another.buildVisitedSet().count, 3)
    }

    func testExplicitUseSnapshotAndConcurrentTracking() throws {
        let leaves = try (0..<32).map(leaf)
        let root = try Cell(refs: Array(leaves.prefix(4)))
        let usage = UsageTree(root: root)
        let firstSnapshot = usage.buildVisitedSet()
        DispatchQueue.concurrentPerform(iterations: leaves.count) { index in
            _ = usage.useCell(leaves[index])
            _ = usage.buildVisitedSet()
        }
        XCTAssertTrue(firstSnapshot.isEmpty)
        XCTAssertEqual(usage.buildVisitedSet(), try Set(leaves.map { try $0.hash() }))
        _ = usage.useCell(root)
        let subtree = try usage.buildVisitedSubtree { hash in
            // A snapshot callback is deliberately reentrant: it must run outside the lock.
            _ = usage.buildVisitedSet()
            return hash == (try! root.hash())
        }
        XCTAssertEqual(subtree, try Set(([root] + Array(leaves.prefix(4))).map { try $0.hash() }))
    }

    func testTONVirtualizationUsesEffectiveLevelAndNestedMerkleContext() throws {
        let original = try leaf(7)
        let branch = try original.prunedBranch(merkleDepth: 1)
        let container = try Cell(refs: [branch])
        let view = container.virtualized(at: 0)
        XCTAssertEqual(view.mask.value, 0)
        XCTAssertEqual(try view.hash(), try container.hash(0))
        XCTAssertEqual(view.depth(UInt32.max), container.depth(0))
        XCTAssertEqual(try view.reference(at: 0).hash(), try branch.hash(0))
        XCTAssertTrue(container.virtualized(at: 3) === container)
        XCTAssertEqual(try view.virtualized(at: 2).hash(), try container.hash(0))
        let proof = try MerkleProof(proof: container).cell()
        let proofView = proof.virtualized(at: 0)
        let childView = try proofView.reference(at: 0)
        XCTAssertEqual(try childView.hash(), try container.hash(1))
        XCTAssertEqual(childView.mask.value, container.mask.apply(level: 1).value)
        XCTAssertThrowsError(try view.toBoc())
        XCTAssertThrowsError(try UsageTree(root: view).rootCell().toBoc())
    }

    func testOrdinaryGuardRetainsSourceAndRejectsPrunedData() throws {
        let original = try leaf(7)
        let cursor = try original.ordinarySlice()
        XCTAssertTrue(cursor.sourceCell === original)
        XCTAssertThrowsError(try original.prunedBranch().ordinarySlice())
        let arrays = CellSlice(bits: original.bits, refs: original.refs)
        XCTAssertNil(arrays.sourceCell)
    }

    func testVirtualAndUsageViewsComposeWithoutEagerVisits() throws {
        let pruned = try leaf(1).prunedBranch()
        let root = try Cell(refs: [pruned])
        let usage = UsageTree(root: root)
        let virtual = usage.rootCell().virtualized(at: 0)
        let cursor = CellSlice.parse(cell: virtual)
        XCTAssertTrue(usage.buildVisitedSet().isEmpty)
        XCTAssertTrue(cursor.sourceCell === virtual)
        XCTAssertEqual(try cursor.loadRef().hash(), try pruned.hash(0))
        XCTAssertEqual(usage.buildVisitedSet(), try Set([root.hash()]))

        let reversed = UsageTree(root: root.virtualized(at: 0))
        let reversedCursor = reversed.rootCell().parse()
        XCTAssertTrue(reversed.buildVisitedSet().isEmpty)
        _ = try reversedCursor.loadRef()
        XCTAssertEqual(reversed.buildVisitedSet(), try Set([root.hash(0)]))
    }

    func testBigPayloadReadsVisitWhileMetadataAndCursorCreationRemainLazy() throws {
        let payload = Data(repeating: 0xa5, count: 16)
        let big = try Cell(bigData: payload)
        let usage = UsageTree(root: big)
        let wrapped = usage.rootCell()
        XCTAssertEqual(try wrapped.hash(), try big.hash())
        XCTAssertEqual(wrapped.bitLength, payload.count * 8)
        _ = CellSlice.parse(cell: wrapped)
        XCTAssertTrue(usage.buildVisitedSet().isEmpty)
        XCTAssertEqual(wrapped.bigData, payload)
        XCTAssertEqual(usage.buildVisitedSet(), try Set([big.hash()]))

        let virtualUsage = UsageTree(root: big)
        let virtual = VirtualCell(cell: virtualUsage.rootCell())
        XCTAssertEqual(try virtual.hash(), try big.hash())
        XCTAssertEqual(virtual.bitLength, payload.count * 8)
        _ = virtual.parse()
        XCTAssertTrue(virtualUsage.buildVisitedSet().isEmpty)
        XCTAssertEqual(virtual.bigData, payload)
        XCTAssertEqual(virtualUsage.buildVisitedSet(), try Set([big.hash()]))

        let reversed = UsageTree(root: VirtualCell(cell: big))
        let reversedView = reversed.rootCell()
        _ = reversedView.parse()
        XCTAssertTrue(reversed.buildVisitedSet().isEmpty)
        XCTAssertEqual(reversedView.bigData, payload)
        XCTAssertEqual(reversed.buildVisitedSet(), try Set([big.hash()]))
    }
}
