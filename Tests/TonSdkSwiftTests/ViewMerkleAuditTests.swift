import BigInt
import Foundation
import SwiftExtensionsPack
import TonSdkSwift
import XCTest

final class ViewMerkleAuditTests: XCTestCase {
    func testInheritedCursorAndReferenceAccessHonorSubclassViews() throws {
        let leaf = try Cell(refs: [CellBuilder().storeUInt(1, 8).cell()])
        let branch = try leaf.prunedBranch()
        let root = try Cell(bits: [.b1], refs: [branch])
        let view = InheritedCursorView(root)
        XCTAssertNotEqual(try branch.hash(), try leaf.hash())
        XCTAssertNotEqual(try root.hash(0), try root.hash())
        XCTAssertNotEqual(root.depth(0), root.depth())
        XCTAssertEqual(try view.hash(), try root.hash(0))
        XCTAssertEqual(view.depth(), root.depth(0))
        XCTAssertEqual(try view.refs[0].hash(), try leaf.hash())

        // This view overrides the cell read hooks but deliberately inherits
        // parse/reference. Those inherited methods must use the overridden refs.
        for cursor in [view.parse(), CellSlice.parse(cell: view), Cell(wrapping: view).parse()] {
            XCTAssertTrue(cursor.sourceCell === view)
            XCTAssertEqual(cursor.initialBitCount, 1)
            XCTAssertEqual(cursor.initialRefCount, 1)
            XCTAssertEqual(cursor.consumedBits, 0)
            XCTAssertEqual(cursor.consumedRefs, 0)
            XCTAssertEqual(try cursor.loadBit(), .b1)
            let reference = try cursor.loadRef()
            XCTAssertTrue(reference.isVirtualized)
            XCTAssertEqual(try reference.hash(), try leaf.hash())
            XCTAssertEqual(cursor.consumedBits, 1)
            XCTAssertEqual(cursor.consumedRefs, 1)
        }
        XCTAssertEqual(try view.reference(at: 0).hash(), try leaf.hash())
        XCTAssertEqual(try Cell(wrapping: view).reference(at: 0).hash(), try leaf.hash())
        XCTAssertThrowsError(try view.reference(at: -1))
        XCTAssertThrowsError(try view.reference(at: 1))
    }

    func testPlainWrapperPreservesVirtualAndUsageViews() throws {
        let leaf = try CellBuilder().storeUInt(1, 8).cell()
        let root = try Cell(refs: [leaf.prunedBranch()])
        let virtual = root.virtualized(at: 0)
        let wrapped = Cell(wrapping: virtual)
        XCTAssertTrue(wrapped.isVirtualized)
        XCTAssertEqual(wrapped.mask.value, virtual.mask.value)
        XCTAssertEqual(try wrapped.hash(), try virtual.hash())
        XCTAssertEqual(wrapped.depth(), virtual.depth())
        XCTAssertThrowsError(try wrapped.toBoc())

        let usage = UsageTree(root: root)
        let trackedWrapper = Cell(wrapping: usage.rootCell())
        let cursor = trackedWrapper.parse()
        XCTAssertEqual(try trackedWrapper.hash(), try root.hash())
        XCTAssertTrue(usage.buildVisitedSet().isEmpty)
        _ = try cursor.loadRef()
        XCTAssertEqual(usage.buildVisitedSet(), try Set([root.hash()]))

        let composedUsage = UsageTree(root: root)
        let composed = Cell(wrapping: composedUsage.rootCell()).virtualized(at: 0)
        let composedCursor = composed.parse()
        XCTAssertTrue(composedUsage.buildVisitedSet().isEmpty)
        XCTAssertTrue(composedCursor.sourceCell === composed)
        XCTAssertEqual(try composedCursor.loadRef().hash(), try leaf.hash())
        XCTAssertEqual(composedUsage.buildVisitedSet(), try Set([root.hash()]))
    }

    func testNestedUsageViewsPreserveBothTrackersAndLazyCursorCreation() throws {
        let leaf = try CellBuilder().storeUInt(1, 8).cell()
        let root = try CellBuilder().storeUInt(2, 8).storeRef(leaf.prunedBranch()).cell()
        for virtualize in [false, true] {
            let first = UsageTree(root: root)
            let firstRoot = first.rootCell()
            let view = virtualize ? firstRoot.virtualized(at: 0) : firstRoot
            let second = UsageTree(root: view)
            let cursor = second.rootCell().parse()
            XCTAssertTrue(first.buildVisitedSet().isEmpty)
            XCTAssertTrue(second.buildVisitedSet().isEmpty)
            XCTAssertEqual(try cursor.loadBigUInt(size: 8), 2)
            XCTAssertEqual(first.buildVisitedSet(), try Set([root.hash()]))
            XCTAssertEqual(second.buildVisitedSet(), try Set([view.hash()]))
        }
    }

    func testExplicitlyUsingOwnWrappedViewDoesNotRetainUsageTree() throws {
        let leaf = try CellBuilder().storeUInt(1, 8).cell()
        let root = try Cell(refs: [leaf.prunedBranch()])
        for virtualize in [false, true] {
            weak var observed: UsageTree?
            var retainedView: Cell?
            do {
                let usage = UsageTree(root: root)
                observed = usage
                let view = usage.rootCell()
                let wrapped = virtualize ? view.virtualized(at: 0) : Cell(wrapping: view)
                retainedView = wrapped
                _ = usage.useCell(wrapped)
                XCTAssertNotNil(observed)
            }
            XCTAssertNil(observed)
            let readable = try XCTUnwrap(retainedView)
            XCTAssertEqual(try readable.hash(), try root.hash(virtualize ? 0 : 3))
            XCTAssertEqual(try readable.parse().loadRef().type, .prunedBranch)
        }
    }

    func testUsageCursorConsumptionMetadataDoesNotVisitCells() throws {
        let left = try CellBuilder().storeUInt(1, 8).cell()
        let right = try CellBuilder().storeUInt(2, 8).cell()
        let root = try CellBuilder().storeUInt(3, 8).storeRefs([left, right]).cell()
        let usage = UsageTree(root: root)
        let cursor = usage.rootCell().parse()
        XCTAssertEqual(cursor.consumedBits, 0)
        XCTAssertEqual(cursor.consumedRefs, 0)
        XCTAssertTrue(usage.buildVisitedSet().isEmpty)

        let onLoad = UsageTree(root: root, visitOnLoad: true)
        let onLoadCursor = onLoad.rootCell().parse()
        _ = try onLoadCursor.loadRef()
        XCTAssertEqual(onLoadCursor.consumedRefs, 1)
        XCTAssertEqual(onLoadCursor.consumedBits, 0)
        XCTAssertEqual(onLoad.buildVisitedSet(), try Set([root.hash(), left.hash()]))
    }

    // A replacement at Merkle level one must preserve level zero as well. Its
    // level-one hash alone does not authenticate the lower hashes stored in a
    // pruned branch. This corresponds to TON MerkleUpdate.cpp::compare_cells.
    func testNestedUpdateRejectsForgedLowerHashAndDepth() throws {
        let leaf = try CellBuilder().storeUInt(1, 8).cell()
        let shared = try Cell(refs: [leaf.prunedBranch()])
        let old = try MerkleProof(proof: shared).cell()
        let branch = try shared.prunedBranch(merkleDepth: 1)
        XCTAssertEqual(branch.mask.value, 3)

        for changedBit in [16, 16 + 2 * 256 + 15] {
            var bits = branch.bits
            bits[changedBit] = bits[changedBit] == .b0 ? .b1 : .b0
            let forged = try Cell(bits: bits, type: .prunedBranch)
            XCTAssertEqual(try forged.hash(1), try shared.hash(1))
            XCTAssertEqual(forged.depth(1), shared.depth(1))
            let new = try MerkleProof(proof: forged).cell()
            let update = try MerkleUpdate(old: old, new: new)
            XCTAssertThrowsError(try update.check())
            XCTAssertThrowsError(try update.apply(to: old))
        }
    }

    func testNestedUpdateWithMatchingLowerCommitmentsStillApplies() throws {
        let leaf = try CellBuilder().storeUInt(1, 8).cell()
        let shared = try Cell(refs: [leaf.prunedBranch()])
        let old = try MerkleProof(proof: shared).cell()
        let new = try MerkleProof(proof: shared.prunedBranch(merkleDepth: 1)).cell()
        let update = try MerkleUpdate(old: old, new: new)
        try update.check()
        let applied = try update.apply(to: old)
        XCTAssertTrue(applied.refs[0] === shared)
        XCTAssertEqual(try applied.hash(0), try new.hash(0))
        XCTAssertNoThrow(try MerkleProof(cell: applied))
    }

    func testNestedUpdateRejectsReplacementWithDifferentAppliedMask() throws {
        let leaf = try CellBuilder().storeUInt(1, 8).cell()
        let old = try MerkleProof(proof: leaf).cell()
        let builder = try CellBuilder().storeUInt(1, 8).storeUInt(3, 8)
            .storeBytes(leaf.hash().hexToBytes()).storeBytes(leaf.hash().hexToBytes())
            .storeUInt(0, 16).storeUInt(0, 16)
        let incompatible = try builder.cell(.prunedBranch)
        for level in UInt32(0)...1 {
            XCTAssertEqual(try leaf.hash(level), try incompatible.hash(level))
            XCTAssertEqual(leaf.depth(level), incompatible.depth(level))
        }
        let new = try MerkleProof(proof: incompatible).cell()
        let update = try MerkleUpdate(old: old, new: new)
        XCTAssertThrowsError(try update.check())
        XCTAssertThrowsError(try update.apply(to: old))
    }

    func testApplyRejectsOldProofWhoseLowerCommitmentDiffersFromOldRoot() throws {
        let leaf = try CellBuilder().storeUInt(1, 8).cell()
        let shared = try Cell(refs: [leaf.prunedBranch()])
        let oldRoot = try MerkleProof(proof: shared).cell()
        var bits = try shared.prunedBranch(merkleDepth: 1).bits
        bits[16] = bits[16] == .b0 ? .b1 : .b0
        let forged = try Cell(bits: bits, type: .prunedBranch)
        let forgedOld = try Cell(bits: oldRoot.bits, refs: [forged], type: .merkleProof,
                                 checkMerkleMetadata: false)
        XCTAssertEqual(try forgedOld.hash(0), try oldRoot.hash(0))
        XCTAssertEqual(forgedOld.depth(0), oldRoot.depth(0))
        XCTAssertThrowsError(try MerkleProof(cell: forgedOld))
        let new = try CellBuilder().storeUInt(2, 8).cell()
        let update = try MerkleUpdate(old: forgedOld, new: new)
        XCTAssertThrowsError(try update.apply(to: oldRoot))
    }
}

/// A consumer-defined view using only the public cell read hooks. Keeping parse
/// and reference inherited exercises the subclass contract used by SDK adapters.
private final class InheritedCursorView: Cell {
    private let source: Cell

    init(_ source: Cell) {
        self.source = source
        super.init(wrapping: source)
    }

    override var refs: [Cell] { source.refs.map { $0.virtualized(at: 0) } }
    override var mask: Mask { source.mask.apply(level: 0) }
    override var isVirtualized: Bool { true }
}
