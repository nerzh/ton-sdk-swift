import XCTest
import BigInt
@testable import TonSdkSwift

final class DictionaryAuditRegressionTests: XCTestCase {
    func testLegacyOptionWidthMustAgreeWithExplicitWidth() throws {
        XCTAssertNoThrow(try Hashmap<[Bit], Cell>(keySize: 8))
        XCTAssertNoThrow(try Hashmap<[Bit], Cell>(keySize: 8, options: .init(keySize: 8)))
        XCTAssertNoThrow(try HashmapE<[Bit], Cell>(keySize: 0, options: .init(keySize: 0)))
        XCTAssertThrowsError(try Hashmap<[Bit], Cell>(keySize: 8, options: .init(keySize: 7)))
        XCTAssertThrowsError(try HashmapE<[Bit], Cell>(keySize: 8, options: .init(keySize: -1)))
        let cursor = CellSlice(bits: [.b0, .b1], refs: [])
        XCTAssertThrowsError(try HashmapE<[Bit], Cell>.parse(keySize: 8, slice: cursor,
                                                          options: .init(keySize: 7)))
        XCTAssertEqual(cursor.bits, [.b0, .b1])
    }

    func testEagerEnvelopeFailuresLeaveCallerCursorUnchanged() throws {
        let value = try Cell(bits: [.b1])
        let malformed = try Cell(bits: [.b0, .b0], refs: [value])
        let pruned = try value.toPrunedBranch()
        for refs in [[], [malformed], [pruned]] {
            let cursor = CellSlice(bits: [.b1, .b0, .b1], refs: refs)
            XCTAssertThrowsError(try HashmapE<[Bit], Cell>.parse(keySize: 2, slice: cursor))
            XCTAssertEqual(cursor.bits, [.b1, .b0, .b1])
            XCTAssertEqual(cursor.refs, refs)
        }
        let empty = CellSlice(bits: [.b0, .b1], refs: [value])
        XCTAssertThrowsError(try HashmapE<[Bit], Cell>.parse(keySize: -1, slice: empty))
        XCTAssertEqual(empty.bits, [.b0, .b1])
        XCTAssertEqual(empty.refs, [value])
    }

    func testEagerRootFailureLeavesCallerCursorUnchanged() throws {
        let cursor = CellSlice(bits: [.b0, .b0], refs: [try Cell()])
        let originalRefs = cursor.refs
        XCTAssertThrowsError(try Hashmap<[Bit], Cell>.parse(keySize: 2, slice: cursor))
        XCTAssertEqual(cursor.bits, [.b0, .b0])
        XCTAssertEqual(cursor.refs, originalRefs)
    }

    func testEagerReadersRejectKnownExoticSourceBeforeReadingTag() throws {
        let leaf = try Cell(bits: [.b1])
        let exotic = try leaf.toMerkleProof()
        for eagerEnvelope in [false, true] {
            let cursor = exotic.parse()
            if eagerEnvelope {
                XCTAssertThrowsError(try HashmapE<[Bit], Cell>.parse(keySize: 0, slice: cursor))
            } else {
                XCTAssertThrowsError(try Hashmap<[Bit], Cell>.parse(keySize: 0, slice: cursor))
            }
            XCTAssertEqual(cursor.bits, exotic.bits)
            XCTAssertEqual(cursor.refs, exotic.refs)
        }
    }

    func testRawAndAugmentedMutationSequencesMatchIndependentReferenceMap() throws {
        let sum = DictionaryAugmentation<BigUInt>(empty: { 0 },
            decode: { try $0.loadBigUInt(size: 32) },
            encode: { try CellBuilder().storeUInt($0, 32).cell() }, combine: +)
        var raw = try RawHashmap(keySize: 4)
        var augmented = try HashmapAugE(keySize: 4, augmentation: sum)
        var expected = [Int: Int]()
        var state: UInt32 = 0xA31F
        for step in 0..<160 {
            state = state &* 1_664_525 &+ 1_013_904_223
            let number = Int((state >> 16) & 15)
            let operation = Int((state >> 24) & 3)
            let key = try CellBuilder().storeUInt(BigUInt(number), 4).bits
            let value = try CellBuilder().storeUInt(BigUInt(step), 16).cell().parse()
            let old = expected[number]
            let oldRaw: CellSlice?
            let oldAugmented: CellSlice?
            switch operation {
            case 0:
                oldRaw = try raw.set(key, value: value)
                oldAugmented = try augmented.set(key, value: value, extra: BigUInt(step))
                expected[number] = step
            case 1:
                oldRaw = try raw.add(key, value: value)
                oldAugmented = try augmented.add(key, value: value, extra: BigUInt(step))
                if old == nil { expected[number] = step }
            case 2:
                oldRaw = try raw.replace(key, value: value)
                oldAugmented = try augmented.replace(key, value: value, extra: BigUInt(step))
                if old != nil { expected[number] = step }
            default:
                oldRaw = try raw.remove(key)
                oldAugmented = try augmented.remove(key)
                expected[number] = nil
            }
            XCTAssertEqual(try oldRaw?.loadBigUInt(size: 16), old.map { BigUInt($0) })
            XCTAssertEqual(try oldAugmented?.loadBigUInt(size: 16), old.map { BigUInt($0) })
            XCTAssertEqual(try augmented.rootExtra(), BigUInt(expected.values.reduce(0, +)))
            try augmented.validateAugmentation()
            var entries = [Int: Int]()
            try raw.iterate { key, value in
                entries[Int(key.toBigUInt())] = Int(try value.loadBigUInt(size: 16))
                return true
            }
            XCTAssertEqual(entries, expected)
            var augmentedEntries = [Int: Int]()
            try augmented.iterate { key, value, extra in
                let actual = Int(try value.loadBigUInt(size: 16))
                XCTAssertEqual(extra, BigUInt(actual))
                augmentedEntries[Int(key.toBigUInt())] = actual
                return true
            }
            XCTAssertEqual(augmentedEntries, expected)
            let sorted = expected.keys.sorted()
            for query in 0..<16 {
                let queryKey = try CellBuilder().storeUInt(BigUInt(query), 4).bits
                for inclusive in [false, true] {
                    XCTAssertEqual(try raw.find(queryKey, inclusive: inclusive).map { Int($0.key.toBigUInt()) },
                                   sorted.first { inclusive ? $0 >= query : $0 > query })
                    XCTAssertEqual(try raw.find(queryKey, next: false, inclusive: inclusive).map { Int($0.key.toBigUInt()) },
                                   sorted.last { inclusive ? $0 <= query : $0 < query })
                }
            }
        }
    }

    func testReferenceBearingAugmentedInlineForkPreservesFollowingReference() throws {
        let marker = try Cell(bits: [.b1])
        let tail = try Cell(bits: [.b0])
        let codec = DictionaryAugmentation<BigUInt>(empty: { 0 }, decode: { cursor in
            let number = try cursor.loadBigUInt(size: 8)
            XCTAssertEqual(try cursor.loadRef(), marker)
            return number
        }, encode: { try CellBuilder().storeUInt($0, 8).storeRef(marker).cell() }, combine: +)
        var map = try HashmapAugE(keySize: 1, augmentation: codec)
        try map.set([.b0], value: CellSlice(bits: [], refs: []), extra: 2)
        try map.set([.b1], value: CellSlice(bits: [], refs: []), extra: 3)
        let builder = CellBuilder()
        try map.writeRoot(to: builder)
        let cursor = try builder.storeBit(.b1).storeRef(tail).cell().parse()
        let decoded = try HashmapAugE.readRoot(from: cursor, keySize: 1, augmentation: codec)
        XCTAssertEqual(decoded.root, map.root)
        XCTAssertEqual(try decoded.rootExtra(), 5)
        XCTAssertEqual(cursor.bits, [.b1])
        XCTAssertEqual(cursor.refs, [tail])
    }

    func testSubtreesDiffAndCombineMatchIntegerKeyReferenceMaps() throws {
        for scenario in 0..<12 {
            var first = try RawHashmap(keySize: 4)
            var second = try RawHashmap(keySize: 4)
            var expectedFirst = [Int: Int]()
            var expectedSecond = [Int: Int]()
            for number in 0..<16 {
                let key = try CellBuilder().storeUInt(BigUInt(number), 4).bits
                let value = try CellBuilder().storeUInt(BigUInt(number), 8).cell().parse()
                if (number * 7 + scenario) % 5 < 3 {
                    try first.set(key, value: value)
                    expectedFirst[number] = number
                }
                if (number * 3 + scenario) % 7 < 4 {
                    try second.set(key, value: value)
                    expectedSecond[number] = number
                }
            }
            var differences = [Int]()
            try first.scanDiff(second) { key, old, new in
                let number = Int(key.toBigUInt())
                XCTAssertEqual(try old?.loadBigUInt(size: 8), expectedFirst[number].map { BigUInt($0) })
                XCTAssertEqual(try new?.loadBigUInt(size: 8), expectedSecond[number].map { BigUInt($0) })
                differences.append(number)
                return true
            }
            XCTAssertEqual(differences, (0..<16).filter { expectedFirst[$0] != expectedSecond[$0] })
            for prefixWidth in 0...4 {
                for prefixNumber in 0..<(1 << prefixWidth) {
                    let prefix = try CellBuilder().storeUInt(BigUInt(prefixNumber), prefixWidth).bits
                    for strip in [false, true] {
                        let subtree = try first.subtree(prefix: prefix, strippingPrefix: strip)
                        let suffixWidth = 4 - prefixWidth
                        var actual = [Int: Int]()
                        try subtree.iterate { key, value in
                            actual[Int(key.toBigUInt())] = Int(try value.loadBigUInt(size: 8))
                            return true
                        }
                        var expected = [Int: Int]()
                        for (key, value) in expectedFirst where key >> suffixWidth == prefixNumber {
                            expected[strip ? key & ((1 << suffixWidth) - 1) : key] = value
                        }
                        XCTAssertEqual(actual, expected)
                        XCTAssertEqual(subtree.keySize, strip ? suffixWidth : 4)
                    }
                }
            }
            try first.combine(second)
            var combined = [Int: Int]()
            try first.iterate { key, value in
                combined[Int(key.toBigUInt())] = Int(try value.loadBigUInt(size: 8))
                return true
            }
            XCTAssertEqual(combined, expectedFirst.merging(expectedSecond) { old, _ in old })
        }
    }

    func testPrefixMutationSequencesMatchIndependentStringPrefixCode() throws {
        var map = try PfxHashmapE(keySize: 4)
        var expected = [String: Int]()
        var state: UInt32 = 0xEDC1
        for step in 0..<96 {
            state = state &* 1_664_525 &+ 1_013_904_223
            let width = Int((state >> 16) % 5)
            let number = Int((state >> 21) & UInt32((1 << width) - 1))
            let operation = Int((state >> 27) & 3)
            let key = try CellBuilder().storeUInt(BigUInt(number), width).bits
            let stringKey = key.map { String($0.rawValue) }.joined()
            let value = try CellBuilder().storeUInt(BigUInt(step), 8).cell().parse()
            let old = expected[stringKey]
            let collision = expected.keys.contains {
                $0 != stringKey && ($0.hasPrefix(stringKey) || stringKey.hasPrefix($0))
            }
            let original = map.root
            let previous: CellSlice?
            switch operation {
            case 0 where collision:
                XCTAssertThrowsError(try map.set(key, value: value))
                XCTAssertTrue(map.root === original)
                continue
            case 1 where collision:
                XCTAssertThrowsError(try map.add(key, value: value))
                XCTAssertTrue(map.root === original)
                continue
            case 0:
                previous = try map.set(key, value: value)
                expected[stringKey] = step
            case 1:
                previous = try map.add(key, value: value)
                if old == nil { expected[stringKey] = step }
            case 2:
                previous = try map.replace(key, value: value)
                if old != nil { expected[stringKey] = step }
            default:
                previous = try map.remove(key)
                expected[stringKey] = nil
            }
            XCTAssertEqual(try previous?.loadBigUInt(size: 8), old.map { BigUInt($0) })
            var actual = [String: Int]()
            try map.iterate { key, value in
                actual[key.map { String($0.rawValue) }.joined()] = Int(try value.loadBigUInt(size: 8))
                return true
            }
            XCTAssertEqual(actual, expected)
            for query in 0..<32 {
                let queryBits = try CellBuilder().storeUInt(BigUInt(query), 5).bits
                let queryText = queryBits.map { String($0.rawValue) }.joined()
                let expectedMatch = expected.keys.first { queryText.hasPrefix($0) }
                let match = try map.prefixMatch(queryBits)
                XCTAssertEqual(match?.key.map { String($0.rawValue) }.joined(), expectedMatch)
                if let match, let expectedMatch {
                    XCTAssertEqual(match.remainder.count, 5 - expectedMatch.count)
                    XCTAssertEqual(try match.value.loadBigUInt(size: 8), BigUInt(expected[expectedMatch]!))
                }
            }
        }
    }
}
