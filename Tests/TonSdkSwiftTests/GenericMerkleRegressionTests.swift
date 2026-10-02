import BigInt
import Foundation
import TonSdkSwift
import XCTest

final class GenericMerkleRegressionTests: XCTestCase {
    private func cell(_ bytes: [UInt8], refs: [Cell] = [], compatibility: CellCompatibility = .ton) throws -> Cell {
        try CellBuilder().storeBytes(Data(bytes)).storeRefs(refs).cell(compatibility: compatibility)
    }

    func testProofSelectionAndUsageTreePreserveTrustedHash() throws {
        let left = try cell([1]), right = try cell([2])
        let root = try cell([3], refs: [left, right])
        let usage = UsageTree(root: root)
        let cursor = usage.rootCell().parse()
        _ = try cursor.loadRef().parse().loadBit()
        let proof = try MerkleProof.create(root: root, usageTree: usage)
        XCTAssertEqual(proof.proof.refs[0].type, .ordinary)
        XCTAssertEqual(proof.proof.refs[1].type, .prunedBranch)
        XCTAssertEqual(try proof.virtualRoot().hash(), try root.hash())
        try proof.check(expectedHash: root.hash().uppercased())
        XCTAssertThrowsError(try proof.check(expectedHash: String(repeating: "0", count: 64)))
        XCTAssertThrowsError(try MerkleProof.create(root: root, isInclude: { _ in false }))
        let whole = try MerkleProof.create(root: root, isInclude: { _ in false }, isIncludeSubtree: { _ in true })
        XCTAssertTrue(whole.proof === root)
        let restored = try MerkleProof(cell: Boc.deserialize(data: proof.cell().toBoc())[0])
        XCTAssertEqual(restored, proof)
    }

    func testPruningUsesMerkleContextForSharedDAG() throws {
        let leaf = try cell([1])
        let inside = try cell([2], refs: [leaf])
        let record = try MerkleProof(proof: inside).cell()
        let root = try cell([3], refs: [inside, record])
        let included = try Set([root.hash(), inside.hash(), record.hash()])
        let proof = try MerkleProof.create(root: root, isInclude: included.contains)
        let outerBranch = proof.proof.refs[0].refs[0]
        let innerBranch = proof.proof.refs[1].refs[0].refs[0]
        XCTAssertEqual(outerBranch.mask.value, 1)
        XCTAssertEqual(innerBranch.mask.value, 2)
        XCTAssertEqual(try proof.proof.hash(0), try root.hash())
        XCTAssertThrowsError(try leaf.prunedBranch(merkleDepth: 3))
        XCTAssertThrowsError(try leaf.prunedBranch(merkleDepth: UInt32.max))
    }

    func testTypedReadersRejectTamperedMetadataWithoutConsumingCursor() throws {
        let leaf = try cell([1])
        let proof = try MerkleProof(proof: leaf).cell()
        var corrupt = proof.bits
        corrupt[8] = corrupt[8] == .b0 ? .b1 : .b0
        let unchecked = try Cell(bits: corrupt, refs: proof.refs, type: .merkleProof, checkMerkleMetadata: false)
        let cursor = unchecked.parse()
        XCTAssertThrowsError(try MerkleProof.read(from: cursor))
        XCTAssertEqual(cursor.consumedBits, 0)
        XCTAssertEqual(cursor.consumedRefs, 0)
        XCTAssertThrowsError(try MerkleProof.read(from: CellSlice(bits: proof.bits, refs: proof.refs)))
        let shifted = proof.parse()
        _ = try shifted.loadBit()
        XCTAssertThrowsError(try MerkleProof.read(from: shifted))
        let valid = proof.parse()
        XCTAssertEqual(try MerkleProof.read(from: valid).hash, try leaf.hash())
        XCTAssertTrue(valid.bits.isEmpty && valid.refs.isEmpty)

        let update = try MerkleUpdate(old: leaf, new: cell([2])).cell()
        var changed = update.bits
        changed[520] = changed[520] == .b0 ? .b1 : .b0
        let badUpdate = try Cell(bits: changed, refs: update.refs, type: .merkleUpdate, checkMerkleMetadata: false)
        XCTAssertThrowsError(try MerkleUpdate(cell: badUpdate))
        let consumedRef = update.parse()
        _ = try consumedRef.loadRef()
        XCTAssertThrowsError(try MerkleUpdate.read(from: consumedRef))
        let validUpdate = update.parse()
        XCTAssertEqual(try MerkleUpdate.read(from: validUpdate).oldHash, try leaf.hash())
        XCTAssertTrue(validUpdate.bits.isEmpty && validUpdate.refs.isEmpty)
    }

    func testUpdatesReuseSharedCellsAndSupportFactoriesAndMetrics() throws {
        let shared = try cell([1])
        let old = try cell([2], refs: [shared, cell([3])])
        let new = try cell([4], refs: [shared, shared, cell([5])])
        let update = try MerkleUpdate.create(old: old, new: new)
        try update.check()
        XCTAssertEqual(update.new.refs[0].type, .prunedBranch)
        XCTAssertTrue(update.new.refs[0] === update.new.refs[1])
        let factory = RecordingFactory()
        let applied = try update.apply(to: old, factory: factory)
        XCTAssertEqual(try applied.cell.hash(), try new.hash())
        XCTAssertTrue(applied.cell.refs[0] === shared)
        XCTAssertTrue(applied.cell.refs[0] === applied.cell.refs[1])
        XCTAssertEqual(applied.metrics.loadedOldCells, 3)
        XCTAssertEqual(applied.metrics.createdCells, factory.calls)
        XCTAssertGreaterThan(factory.calls, 0)
        let decoded = try MerkleUpdate(cell: Boc.deserialize(data: update.cell().toBoc())[0])
        XCTAssertEqual(try decoded.apply(to: old).hash(), try new.hash())
        let noReuse = try MerkleUpdate.create(old: old, new: new, isReusableOld: { _ in false })
        XCTAssertTrue(noReuse.new === new)
        XCTAssertEqual(try noReuse.apply(to: old).hash(), try new.hash())
    }

    func testUnchangedAndEntirelyDifferentUpdateRoots() throws {
        let old = try cell([1], refs: [cell([2])])
        let unchanged = try MerkleUpdate.create(old: old, new: old)
        XCTAssertTrue(try unchanged.apply(to: old) === old)
        let different = try cell([3])
        XCTAssertEqual(try MerkleUpdate.create(old: old, new: different).apply(to: old).hash(), try different.hash())
        XCTAssertThrowsError(try unchanged.apply(to: different))
    }

    func testUnavailableBranchesAndInvalidFactoryAreRejected() throws {
        let old = try cell([1])
        let missing = try cell([2]).prunedBranch()
        let invalid = try MerkleUpdate(old: old, new: cell([3], refs: [missing]))
        XCTAssertThrowsError(try invalid.check())
        let factory = RecordingFactory()
        XCTAssertThrowsError(try invalid.apply(to: old, factory: factory))
        XCTAssertEqual(factory.calls, 0)
        let valid = try MerkleUpdate.create(old: old, new: cell([4]))
        XCTAssertThrowsError(try valid.apply(to: old, factory: InvalidFactory()))
        // A factory must not substitute a pruned view with the same level-zero hash.
        XCTAssertThrowsError(try valid.apply(to: old, factory: PruningFactory()))
    }

    func testNestedMerkleUpdateAndSameCellAtDifferentLevels() throws {
        let shared = try cell([1])
        let oldProof = try MerkleProof(proof: cell([2], refs: [shared])).cell()
        let newProof = try MerkleProof(proof: cell([3], refs: [shared])).cell()
        let old = try cell([4], refs: [shared, oldProof])
        let new = try cell([5], refs: [shared, newProof])
        let update = try MerkleUpdate.create(old: old, new: new)
        try update.check()
        XCTAssertEqual(try update.apply(to: old).hash(), try new.hash())
    }

    func testAvailableCompleteCellWinsOverItsPrunedCommitment() throws {
        let shared = try cell([1])
        let branch = try shared.prunedBranch()
        let new = try cell([3], refs: [shared])
        for references in [[shared, branch], [branch, shared]] {
            let old = try cell([2], refs: references)
            let update = try MerkleUpdate.create(old: old, new: new)
            let result = try update.apply(to: old)
            XCTAssertEqual(try result.hash(), try new.hash())
            XCTAssertTrue(result.refs[0] === shared)
        }
    }

    private func nestedProof(compatibility: CellCompatibility) throws -> Cell {
        func make(_ value: UInt8, _ refs: [Cell] = [], root: Bool = false) throws -> Cell {
            try cell(root ? [value] : [value, value, value], refs: refs, compatibility: compatibility)
        }
        let c1 = try make(1), c2 = try make(2)
        let c3 = try make(3, [c1]), c4 = try make(4, [c2])
        let c5 = try make(5, [c1, c2]), c6 = try make(6, [c3, c4])
        let root = try make(1, [c5, c6], root: true)
        let selected = try Set([root, c1, c2, c3, c4, c6].map { try $0.hash() })
        let first = try MerkleProof.create(root: root, isInclude: selected.contains).cell()
        let a = first.refs[0], b = a.refs[1], c = b.refs[0]
        let nestedSelection = try Set([first, a, b, c].map { try $0.hash() })
        return try MerkleProof.create(root: first, isInclude: nestedSelection.contains).cell()
    }

    // TON expectations were calculated independently with Python hashlib from fixed
    // byte preimages: gapped c/b descriptors are 0x41/0x42, a uses 0x62, and the
    // inner proof uses 0x29. No SDK hash or pruning function generated these constants.
    // Specification: ton-blockchain/ton crypto/vm/cells/DataCell.cpp::compute_hash.
    func testLiteralTONNestedProofPreservesTONGappedHashConvention() throws {
        let result = try nestedProof(compatibility: .ton)
        let inner = result.refs[0], a = inner.refs[0], b = a.refs[1], c = b.refs[0]
        XCTAssertEqual(try c.hash(0), "093fed1748edf1bbb14e25dbbae22e8015c021831ccdc9e2427e145e24aac8c1")
        XCTAssertEqual(try c.hash(2), "56cd433ccab3cd18856603fa03545e378b17240091a4fd7298ee606e66236fd1")
        XCTAssertEqual(try b.hash(2), "2e1b30963bb7103c60acec765e34508ed87418c955f5c6d14027a239c1b9e149")
        XCTAssertEqual(try a.hash(0), "6b663d94d562c0682bd6a8be41c639b6e52f87c20ef5776795e4ad7fdbcf0461")
        XCTAssertEqual(try a.hash(1), "69b89defd3511d324ba0045d5e367328767d9e7879eefee2997eb6d324f7bb26")
        XCTAssertEqual(try a.hash(2), "16634b4c49e97f424a7f60f1bee8595b4ea29cbfb3e577b5350cb4715b84b72f")
        XCTAssertEqual(try inner.hash(0), "fc5004bc31fd26d8fe7c1bafc45490fa28d5ea7a0dc52e8079317fff57bbbba8")
        XCTAssertEqual(try inner.hash(1), "b96f77b1eb0ac1437789c8d178abbaa664b676bd674b1355e0c16197eda23168")
        XCTAssertEqual(try result.hash(), "52b5a66e0f36b84b84dfe5546a535bab0989f59734b0784182dc3246d6583cf6")
        XCTAssertEqual(try MerkleProof(cell: result).virtualRoot().hash(), try inner.hash(0))
    }

    // Literal fixture data from ever_block 1.11.22 test_inner_merkle_proof,
    // commit 6dfe9b396ec2d411ef7487e16a9b4651091674d3. The snapshot's gapped-mask
    // descriptor convention is explicitly Everscale; it is not a TON oracle.
    func testLiteralEverscaleNestedProofTree() throws {
        let result = try nestedProof(compatibility: .everscale)
        let nodes = [result, result.refs[0], result.refs[0].refs[0],
                     result.refs[0].refs[0].refs[0], result.refs[0].refs[0].refs[1],
                     result.refs[0].refs[0].refs[1].refs[0],
                     result.refs[0].refs[0].refs[1].refs[0].refs[0],
                     result.refs[0].refs[0].refs[1].refs[1]]
        let masks: [UInt32] = [0, 1, 3, 3, 2, 2, 2, 2]
        let sizes = [280, 280, 8, 560, 24, 24, 288, 288]
        let refCounts = [1, 1, 2, 0, 2, 1, 0, 0]
        let payloads = [
            "03fc5004bc31fd26d8fe7c1bafc45490fa28d5ea7a0dc52e8079317fff57bbbba80004",
            "036b663d94d562c0682bd6a8be41c639b6e52f87c20ef5776795e4ad7fdbcf04610003", "01",
            "010348a9bccff3f4284647e46cef7422ab53f73e51f96ca1b61e56a7dbd70f57f91b9cc5685a89369c2eab2d5d1ae7d5075539dda819dfa60559869d3b1eee53d40000010000",
            "060606", "030303",
            "010278b55d6113eba6bc4ae107b4442afa416b6bc9709b3146657e358e68fa994c340000",
            "0102b82404f6e84b041b25e452b30da10f01437dfd34efbba8b5772e4bc427df01df0001",
        ]
        let hashes = [
            ["e4ae22ed3e06bd796b5bd450c6843669b9eba4c1a1d3d9f6725bbeef4536e271"],
            ["fc5004bc31fd26d8fe7c1bafc45490fa28d5ea7a0dc52e8079317fff57bbbba8", "b05852923a85880d85a6fe6769241e0a529200b61829b1aeeb5b584233d1fbff"],
            ["6b663d94d562c0682bd6a8be41c639b6e52f87c20ef5776795e4ad7fdbcf0461", "69b89defd3511d324ba0045d5e367328767d9e7879eefee2997eb6d324f7bb26", "61d3e69357372022d099e3b2926bb7692d1cc0461912a2ca3e57a7a880dc2f6d"],
            ["48a9bccff3f4284647e46cef7422ab53f73e51f96ca1b61e56a7dbd70f57f91b", "9cc5685a89369c2eab2d5d1ae7d5075539dda819dfa60559869d3b1eee53d400", "75886b76cecf4242e0fb1579905b1b68e9e8d4c5802f8799910cfac9a66c8363"],
            ["874b71a722fcf50bed19d9635177d6ca5482b560cdd62bed6c6ff8f1e61efe68", "8b86e04f03cb3ac31dff013eef8c39d9e8c729bb0f73deff96f34115110751d0"],
            ["093fed1748edf1bbb14e25dbbae22e8015c021831ccdc9e2427e145e24aac8c1", "cba811a64f95abacf23fa29a98d99399d849ff7c8522cbb2d140f917988c1ae2"],
            ["78b55d6113eba6bc4ae107b4442afa416b6bc9709b3146657e358e68fa994c34", "99cca996c8108a2288327990fe93e19e5c8c1d80c942645f1b5f8d9a967b8a1f"],
            ["b82404f6e84b041b25e452b30da10f01437dfd34efbba8b5772e4bc427df01df", "76e25eb9c2e42ba849c900812b41b31bd3fa9f7588468f75a7c3d8fa3b766dce"],
        ]
        let depths: [[BigUInt]] = [[5], [4, 4], [3, 3, 3], [1, 0, 0], [2, 2], [1, 1], [0, 0], [1, 0]]
        for (index, node) in nodes.enumerated() {
            XCTAssertEqual(node.mask.value, masks[index], "node \(index)")
            XCTAssertEqual(node.bits.count, sizes[index], "node \(index)")
            XCTAssertEqual(node.refs.count, refCounts[index], "node \(index)")
            XCTAssertEqual(try node.bits.toHex().lowercased(), payloads[index], "node \(index)")
            let levels = (0...node.mask.level).filter { node.mask.isSignificant(level: $0) }
            XCTAssertEqual(try levels.map { try node.hash($0) }, hashes[index], "node \(index)")
            XCTAssertEqual(levels.map { node.depth($0) }, depths[index], "node \(index)")
        }
    }
}

private final class RecordingFactory: MerkleCellFactory {
    var calls = 0
    func rebuild(_ template: Cell, references: [Cell]) throws -> Cell {
        calls += 1
        return try DefaultMerkleCellFactory().rebuild(template, references: references)
    }
}

private struct InvalidFactory: MerkleCellFactory {
    func rebuild(_ template: Cell, references: [Cell]) throws -> Cell { try Cell() }
}

private struct PruningFactory: MerkleCellFactory {
    func rebuild(_ template: Cell, references: [Cell]) throws -> Cell { try template.prunedBranch() }
}
