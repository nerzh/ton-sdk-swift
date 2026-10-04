//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 05.02.2024.
//

import Foundation
import BigInt
import SwiftExtensionsPack

open class Boc {
    static let REACH_BOC_MAGIC_PREFIX = "B5EE9C72".hexToBytesUnsafe()
    static let LEAN_BOC_MAGIC_PREFIX = "68FF65F3".hexToBytesUnsafe()
    static let LEAN_BOC_MAGIC_PREFIX_CRC = "ACC3A728".hexToBytesUnsafe()

    public struct BOCOptions {
        public var hasIndex: Bool?
        public var hashCrc32: Bool?
        public var hasCacheBits: Bool?
        public var topologicalOrder: String?
        public var flags: Int?
        
        public init(hasIndex: Bool? = nil, hashCrc32: Bool? = nil, hasCacheBits: Bool? = nil, topologicalOrder: String? = nil, flags: Int? = nil) {
            self.hasIndex = hasIndex
            self.hashCrc32 = hashCrc32
            self.hasCacheBits = hasCacheBits
            self.topologicalOrder = topologicalOrder
            self.flags = flags
        }
    }

    public struct BocHeader {
        public var hasIndex: Bool
        public var hashCrc32: Int?
        public var hasCacheBits: Bool
        public var flags: UInt8
        public var sizeBytes: Int
        public var offsetBytes: UInt8
        public var cellsNum: BigUInt
        public var rootsNum: BigUInt
        public var absentNum: BigUInt
        public var totCellsSize: BigUInt
        public var rootList: [BigUInt]
        public var cellsData: Data
        /// Cumulative cell ends, excluding cache flag bits.
        public var indexOffsets: [Int] = []
        
        public init(hasIndex: Bool, hashCrc32: Int? = nil, hasCacheBits: Bool, flags: UInt8, sizeBytes: Int, offsetBytes: UInt8, cellsNum: BigUInt, rootsNum: BigUInt, absentNum: BigUInt, totCellsSize: BigUInt, rootList: [BigUInt], cellsData: Data) {
            self.hasIndex = hasIndex
            self.hashCrc32 = hashCrc32
            self.hasCacheBits = hasCacheBits
            self.flags = flags
            self.sizeBytes = sizeBytes
            self.offsetBytes = offsetBytes
            self.cellsNum = cellsNum
            self.rootsNum = rootsNum
            self.absentNum = absentNum
            self.totCellsSize = totCellsSize
            self.rootList = rootList
            self.cellsData = cellsData
        }
    }

    public struct CellNode {
        public var cell: Cell
        public var children: Int
        public var scanned: Int
        
        public init(cell: Cell, children: Int, scanned: Int) {
            self.cell = cell
            self.children = children
            self.scanned = scanned
        }
    }

    public struct BuilderNode {
        public var builder: CellBuilder
        public var indent: Int
        
        public init(builder: CellBuilder, indent: Int) {
            self.builder = builder
            self.indent = indent
        }
    }

    public struct CellPointer {
        public var cell: Cell?
        public var type: CellType
        public var builder: CellBuilder
        public var refs: [BigUInt]
        public var declaredMask: UInt32?
        public var storedHashes: [String] = []
        public var storedDepths: [BigUInt] = []
        
        public init(cell: Cell? = nil, type: CellType, builder: CellBuilder, refs: [BigUInt]) {
            self.cell = cell
            self.type = type
            self.builder = builder
            self.refs = refs
        }
    }

    public struct CellData {
        public var pointer: CellPointer
        public var remainder: Data
        
        public init(pointer: Boc.CellPointer, remainder: Data) {
            self.pointer = pointer
            self.remainder = remainder
        }
    }

    public static func deserializeFift(data: String) throws -> [Cell] {
        guard !data.isEmpty else {
            throw ErrorTonSdkSwift("Can't deserialize. Empty fift hex.")
        }

        let re = try! NSRegularExpression(pattern: "(\\s*)x\\{([0-9a-zA-Z_]+)\\}\n?", options: .caseInsensitive)
        let matches = re.matches(in: data, options: [], range: NSRange(location: 0, length: data.utf16.count))
        
        guard !matches.isEmpty else {
            throw ErrorTonSdkSwift("Can't deserialize. Bad fift hex.")
        }

        if matches.count == 1 {
            return [try Cell(bits: try parseFiftHex((data as NSString).substring(with: matches[0].range(at: 2))))]
        }

        var stack: [BuilderNode] = []

        for (i, match) in matches.enumerated() {
            let spaces = (data as NSString).substring(with: match.range(at: 1))
            let fift = (data as NSString).substring(with: match.range(at: 2))
            let isLast = i == matches.count - 1
            let indent = spaces.count
            let bits = try parseFiftHex(fift)
            let builder = try CellBuilder().storeBits(bits)

            while !stack.isEmpty && !isLastNested(stack: stack, indent: indent) {
                let b = stack.popLast()!.builder
                try stack[stack.endIndex - 1].builder.storeRef(try b.cell())
            }

            if isLast {
                try stack[stack.endIndex - 1].builder.storeRef(try builder.cell())
            } else {
                stack.append(BuilderNode(builder: builder, indent: indent))
            }
        }

        return try stack.map { try $0.builder.cell() }
    }
    
    private class func isLastNested(stack: [BuilderNode], indent: Int) -> Bool {
        let lastStackIndent = stack.last!.indent
        return lastStackIndent != 0 && lastStackIndent >= indent
    }
    
    private class func parseFiftHex(_ fift: String) throws -> [Bit] {
        if fift == "_" {
            return []
        }
        
        let bits = try fift
            .map { $0 == "_" ? String($0) : String($0).hexToBits().join("") }
            .joined()
            .replacingOccurrences(of: "1[0]*_$", with: "", options: .regularExpression)
            .map { try Bit(Int(String($0)) ?? 0) }
        
        return bits
    }
    
    
    public static func deserializeHeader(bytes: Data) throws -> BocHeader {
        let input = Array(bytes)
        var cursor = 0
        func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, count <= input.count - cursor else { throw ErrorTonSdkSwift("Truncated BOC") }
            defer { cursor += count }
            return Array(input[cursor..<cursor + count])
        }
        func number(_ count: Int) throws -> Int {
            let value = try take(count).reduce(BigUInt(0)) { ($0 << 8) | BigUInt($1) }
            guard let result = Int(exactly: value) else { throw ErrorTonSdkSwift("BOC counter overflow") }
            return result
        }
        let magic = try Data(take(4))
        let generic = magic == REACH_BOC_MAGIC_PREFIX
        guard generic || magic == LEAN_BOC_MAGIC_PREFIX || magic == LEAN_BOC_MAGIC_PREFIX_CRC else {
            throw ErrorTonSdkSwift("bad magic prefix")
        }
        let flag = try number(1)
        let size = generic ? flag & 7 : flag
        let offset = try number(1)
        let indexed = !generic || flag & 128 != 0
        let crc = generic ? flag & 64 != 0 : magic == LEAN_BOC_MAGIC_PREFIX_CRC
        let cache = generic && flag & 32 != 0
        guard (1...4).contains(size), (1...8).contains(offset), !cache || indexed, !generic || flag & 24 == 0 else {
            throw ErrorTonSdkSwift("Invalid BOC widths or cache flags")
        }
        let cells = try number(size), roots = try number(size), absent = try number(size)
        let total = try number(offset)
        guard cells > 0, cells <= input.count / 2, roots > 0, roots <= 1024, roots <= cells, absent == 0,
              generic || roots == 1 else { throw ErrorTonSdkSwift("Invalid BOC counters") }
        var rootList: [BigUInt] = []
        if generic {
            for _ in 0..<roots {
                let index = try number(size)
                guard index < cells else { throw ErrorTonSdkSwift("Invalid BOC root index") }
                rootList.append(BigUInt(index))
            }
        } else { rootList = [0] }
        var indexOffsets: [Int] = []
        if indexed {
            guard cells <= (input.count - cursor) / offset else { throw ErrorTonSdkSwift("Truncated BOC index") }
            var previous = 0
            for _ in 0..<cells {
                let encoded = try number(offset)
                let end = cache ? encoded >> 1 : encoded
                if end <= previous || end > total { throw ErrorTonSdkSwift("Invalid BOC index offset") }
                indexOffsets.append(end)
                previous = end
            }
            if previous != total { throw ErrorTonSdkSwift("BOC index does not cover cell data") }
        }
        let data = try Data(take(total))
        if crc {
            let computed = Data(input[..<cursor]).crc32cBytesLE()
            guard try Data(take(4)) == computed else { throw ErrorTonSdkSwift("crc32c hashsum mismatch") }
        }
        guard cursor == input.count else { throw ErrorTonSdkSwift("too much bytes in boc serialization") }
        var header = BocHeader(hasIndex: indexed, hashCrc32: crc ? 1 : 0, hasCacheBits: cache,
                         flags: UInt8(generic ? (flag >> 3) & 3 : 0), sizeBytes: size, offsetBytes: UInt8(offset),
                         cellsNum: BigUInt(cells), rootsNum: BigUInt(roots), absentNum: BigUInt(absent),
                         totCellsSize: BigUInt(total), rootList: rootList, cellsData: data)
        header.indexOffsets = indexOffsets
        return header
    }

    public static func deserializeCell(remainder: Data, refIndexSize: Int) throws -> CellData {
        guard (1...4).contains(refIndexSize) else { throw ErrorTonSdkSwift("Invalid reference width") }
        if remainder.count < 2 {
            throw ErrorTonSdkSwift("Not enough bytes to encode cell descriptors")
        }

        var mutableRemainder = remainder
        let refsDescriptor = mutableRemainder.removeFirst()

        let level = refsDescriptor >> 5
        let totalRefs = refsDescriptor & 7
        let hasHashes = (refsDescriptor & 16) != 0
        let isExotic = (refsDescriptor & 8) != 0
        let isAbsent = totalRefs == 7 && hasHashes

        if isAbsent {
            throw ErrorTonSdkSwift("Can't deserialize absent cell")
        }

        if totalRefs > 4 {
            throw ErrorTonSdkSwift("Cell can't have more than 4 refs \(totalRefs)")
        }

        let bitsDescriptor = mutableRemainder.removeFirst()

        let isAugmented: Bool = (bitsDescriptor & 1) != 0
        let dataSize: Int = (Int(bitsDescriptor >> 1)) + (isAugmented ? 1 : 0)
        let hashCount = level.nonzeroBitCount + 1
        let hashesSize: Int = hasHashes ? hashCount * 32 : 0
        let depthSize: Int = hasHashes ? hashCount * 2 : 0
        
        let requiredBytes = hashesSize + depthSize + dataSize + refIndexSize * Int(totalRefs)
        
        if  mutableRemainder.count < requiredBytes {
            throw ErrorTonSdkSwift("Not enough bytes to encode cell data")
        }

        var storedHashes: [String] = [], storedDepths: [BigUInt] = []
        if hasHashes {
            for _ in 0..<hashCount {
                storedHashes.append(try Data(mutableRemainder.prefix(32)).toHex())
                mutableRemainder.removeFirst(32)
            }
            for _ in 0..<hashCount {
                storedDepths.append(Data(mutableRemainder.prefix(2)).toBigUInt())
                mutableRemainder.removeFirst(2)
            }
        }
        if isAugmented {
            guard dataSize > 0, mutableRemainder[mutableRemainder.startIndex + dataSize - 1] & 0x7f != 0 else {
                throw ErrorTonSdkSwift("Invalid cell completion tag")
            }
        }

        let bits = if isAugmented  {
            try mutableRemainder[mutableRemainder.startIndex..<mutableRemainder.startIndex + dataSize].toBits().rollback()
        } else {
            mutableRemainder[mutableRemainder.startIndex..<mutableRemainder.startIndex + dataSize].toBits()
        }
        mutableRemainder.removeFirst(dataSize)

        if isExotic && bits.count < 8 {
            throw ErrorTonSdkSwift("Not enough bytes for an exotic cell type")
        }

        let type: CellType!
        if isExotic {
            guard let unwrapedType = CellType(rawValue: Int8([Bit](bits[0..<8]).toBigInt())) else {
                throw ErrorTonSdkSwift("Unknown cell type")
            }
            type = unwrapedType
        } else {
            type = .ordinary
        }

        if isExotic && type == .ordinary {
            throw ErrorTonSdkSwift("An exotic cell can't be of ordinary type")
        }

        let refs = (0..<Int(totalRefs)).map { _ in
            let refBytes = mutableRemainder[mutableRemainder.startIndex..<mutableRemainder.startIndex + refIndexSize]
            mutableRemainder.removeFirst(refIndexSize)
            return refBytes.toBigUInt()
        }

        var pointer = try CellPointer(type: type, builder: CellBuilder(size: bits.count).storeBits(bits), refs: refs)
        pointer.declaredMask = UInt32(level)
        pointer.storedHashes = storedHashes
        pointer.storedDepths = storedDepths
        
        
        return CellData(pointer: pointer, remainder: mutableRemainder)
    }

    /// Decodes TON cells, validating CRC, indexes, stored hashes/depths and Merkle metadata.
    /// `checkMerkleProofs` requires a Merkle record, but does not authenticate its root.
    /// `maxDepth` can further restrict TON's construction limit of 1024.
    public static func deserialize(data: Data, checkMerkleProofs: Bool = false,
                                   maxDepth: UInt16 = 1024) throws -> [Cell] {
        var hasMerkleProofs = false
        var pointers: [CellPointer] = []
        let header: BocHeader = try deserializeHeader(bytes: data)
        let cellsNum: BigUInt = header.cellsNum
        let sizeBytes: Int = header.sizeBytes
        let cellsData: Data = header.cellsData
        let rootList: [BigUInt] = header.rootList
        
        var remainder: Data = cellsData
        for cellIndex in 0..<Int(cellsNum) {
            let expectedEnd = header.hasIndex ? header.indexOffsets[cellIndex] : nil
            let deserialized: CellData = try deserializeCell(remainder: remainder, refIndexSize: sizeBytes)
            remainder = deserialized.remainder
            pointers.append(deserialized.pointer)
            if let expectedEnd, cellsData.count - remainder.count != expectedEnd { throw ErrorTonSdkSwift("BOC index cell boundary mismatch") }
        }
        
        guard remainder.isEmpty else { throw ErrorTonSdkSwift("Unused BOC cell data") }
        for pointerIndex in pointers.indices.reversed() {
            let cellBuilder = pointers[pointerIndex].builder
            let cellType = pointers[pointerIndex].type
            for refIndex in pointers[pointerIndex].refs {
                guard let index = Int(exactly: refIndex), index > pointerIndex, index < pointers.count,
                      let child = pointers[index].cell else { throw ErrorTonSdkSwift("Invalid BOC reference or topological order") }
                try cellBuilder.storeRef(child)
            }
            hasMerkleProofs = hasMerkleProofs || cellType == .merkleProof || cellType == .merkleUpdate
            pointers[pointerIndex].cell = try Cell(bits: cellBuilder.bits, refs: cellBuilder.refs, type: cellType)
            let cell = pointers[pointerIndex].cell!
            guard cell.mask.value == pointers[pointerIndex].declaredMask else { throw ErrorTonSdkSwift("Cell level mask mismatch") }
            guard (0...3).allSatisfy({ cell.depth(UInt32($0)) <= maxDepth }) else { throw ErrorTonSdkSwift("Cell exceeds maximum BOC depth") }
            if !pointers[pointerIndex].storedHashes.isEmpty {
                let levels = (0...cell.mask.level).filter { cell.mask.isSignificant(level: $0) }
                for (index, level) in levels.enumerated() {
                    guard try cell.hash(level).lowercased() == pointers[pointerIndex].storedHashes[index].lowercased(),
                          cell.depth(level) == pointers[pointerIndex].storedDepths[index] else {
                        throw ErrorTonSdkSwift("Stored cell hash or depth mismatch")
                    }
                }
            }
        }

        if checkMerkleProofs && !hasMerkleProofs {
            throw ErrorTonSdkSwift("BOC does not contain Merkle Proofs")
        }

        return try rootList.map {
            let index = Int($0)
            if index >= pointers.count { throw ErrorTonSdkSwift("Out of Range Pointers") }
            guard let cell = pointers[index].cell else {
                throw ErrorTonSdkSwift("Cell not found")
            }
            return cell
        }
    }
    
    public static func depthFirstSort(root: [Cell]) throws -> (cells: [Cell], hashmap: [String: Int]) {
        var seen = Set<String>()
        var postorder: [Cell] = []
        for cell in root {
            var stack: [(Cell, Bool)] = [(cell, false)]
            while let (current, post) = stack.popLast() {
                if post { postorder.append(current); continue }
                guard seen.insert(try current.hash().lowercased()).inserted else { continue }
                stack.append((current, true))
                for child in current.refs.reversed() { stack.append((child, false)) }
            }
        }
        let cells = Array(postorder.reversed())
        var hashmap: [String: Int] = [:]
        for (index, cell) in cells.enumerated() { hashmap[try cell.hash().lowercased()] = index }
        return (cells, hashmap)
    }

    /// Breadth-first topological order. A shared child is queued only after all
    /// its parents, so every serialized reference still points forward.
    public static func breadthFirstSort(root: [Cell]) throws -> (cells: [Cell], hashmap: [String: Int]) {
        let graph = try depthFirstSort(root: root)
        var incoming = Array(repeating: 0, count: graph.cells.count)
        let children = try graph.cells.map { cell in
            try cell.refs.map { child in
                guard let index = graph.hashmap[try child.hash().lowercased()] else {
                    throw ErrorTonSdkSwift("Missing BOC child")
                }
                incoming[index] += 1
                return index
            }
        }
        var queue = [Int]()
        var queuedRoots = Set<Int>()
        for cell in root {
            guard let index = graph.hashmap[try cell.hash().lowercased()] else {
                throw ErrorTonSdkSwift("Missing BOC root")
            }
            if incoming[index] == 0, queuedRoots.insert(index).inserted { queue.append(index) }
        }
        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            for child in children[index] {
                incoming[child] -= 1
                if incoming[child] == 0 { queue.append(child) }
            }
        }
        guard queue.count == graph.cells.count else { throw ErrorTonSdkSwift("Invalid BOC graph cycle") }
        let cells = queue.map { graph.cells[$0] }
        var hashmap = [String: Int]()
        for (index, cell) in cells.enumerated() { hashmap[try cell.hash().lowercased()] = index }
        return (cells, hashmap)
    }

    public static func serializeCell(cell: Cell, hashmap: [String: Int], refIndexSize: Int) throws -> [Bit] {
        guard (1...32).contains(refIndexSize) else { throw ErrorTonSdkSwift("Invalid cell serialization width") }
        let representation = cell.getRefsDescriptor() + cell.getBitsDescriptor() + cell.getAugmentedBits()
        let serialized = try cell.refs.reduce(into: representation) { acc, ref in
            if let refIndex = hashmap[try ref.hash().lowercased()] {
                guard refIndex >= 0, refIndex < (Int(1) << refIndexSize) else { throw ErrorTonSdkSwift("Reference index does not fit its width") }
                let bits = try (0..<refIndexSize).map { i in
                    try Bit(((refIndex >> i) & 1) == 1 ? 1 : 0)
                }
                acc.append(contentsOf: bits.reversed())
            } else { throw ErrorTonSdkSwift("Missing BOC child") }
        }
        return serialized
    }

    public static func serialize(root: [Cell], options: BOCOptions = .init()) throws -> Data {
        let hasIndex = options.hasIndex ?? false
        let hasCacheBits = options.hasCacheBits ?? false
        let hashCrc32 = options.hashCrc32 ?? true
        let topologicalOrder = options.topologicalOrder ?? "breadth-first"
        let flags = options.flags ?? 0

        guard !root.isEmpty, root.count <= 1024, flags == 0, !hasCacheBits || hasIndex,
              ["breadth-first", "depth-first"].contains(topologicalOrder) else {
            throw ErrorTonSdkSwift("Invalid BOC roots or flags")
        }

        let sortedCells: (cells: [Cell], hashmap: [String: Int])
        if topologicalOrder == "breadth-first" {
            sortedCells = try breadthFirstSort(root: root)
        } else {
            sortedCells = try depthFirstSort(root: root)
        }

        guard try Set(root.map { try $0.hash().lowercased() }).count == root.count else {
            throw ErrorTonSdkSwift("Duplicate BOC roots")
        }
        let cellsList = sortedCells.cells
        let hashmap = sortedCells.hashmap
        let cellsNum = cellsList.count
        let size = String(cellsNum, radix: 2).count
        let sizeBytes = max(Int(ceil(Double(size) / 8)), 1)
        var cellsData = Data()
        var sizeIndex = [Int]()
        for cell in cellsList {
            cellsData.append(try serializeCell(cell: cell, hashmap: hashmap, refIndexSize: sizeBytes * 8).toBytes())
            sizeIndex.append(cellsData.count)
        }
        let fullSize = cellsData.count
        let offsetBits = String(hasCacheBits ? fullSize * 2 : fullSize, radix: 2).count
        let offsetBytes = max(Int(ceil(Double(offsetBits) / 8)), 1)
        let builderSize = (32 + 3 + 2 + 3 + 8)
            + ((sizeBytes * 8) * (3 + root.count))
            + (offsetBytes * 8)
            + (hasIndex ? (cellsList.count * (offsetBytes * 8)) : 0)

        let result = CellBuilder(size: builderSize)
        try result.storeBytes(REACH_BOC_MAGIC_PREFIX)
            .storeBit(hasIndex ? .b1 : .b0)
            .storeBit(hashCrc32 ? .b1 : .b0)
            .storeBit(hasCacheBits ? .b1 : .b0)
            .storeUInt(BigUInt(flags), 2)
            .storeUInt(BigUInt(sizeBytes), 3)
            .storeUInt(BigUInt(offsetBytes), 8)
            .storeUInt(BigUInt(cellsNum), sizeBytes * 8)
            .storeUInt(BigUInt(root.count), sizeBytes * 8)
            .storeUInt(0, sizeBytes * 8)
            .storeUInt(BigUInt(fullSize), offsetBytes * 8)

        for cell in root {
            guard let index = hashmap[try cell.hash().lowercased()] else { throw ErrorTonSdkSwift("Missing BOC root") }
            try result.storeUInt(BigUInt(index), sizeBytes * 8)
        }

        if hasIndex {
            for index in 0..<cellsList.count {
                try result.storeUInt(BigUInt(hasCacheBits ? sizeIndex[index] * 2 : sizeIndex[index]), offsetBytes * 8)
            }
        }

        let bytes = try result.bits.toBytes() + cellsData

        if hashCrc32 {
            let hashsum = bytes.crc32cBytesLE()
            return bytes + hashsum
        }

        return bytes
    }
}

