//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 05.02.2024.
//

import Foundation
import BigInt
import SwiftExtensionsPack

open class Serializer {
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
        public var type: Cell.CellType
        public var builder: CellBuilder
        public var refs: [BigUInt]
        
        public init(cell: Cell? = nil, type: Cell.CellType, builder: CellBuilder, refs: [BigUInt]) {
            self.cell = cell
            self.type = type
            self.builder = builder
            self.refs = refs
        }
    }

    public struct CellData {
        public var pointer: CellPointer
        public var remainder: Data
        
        public init(pointer: Serializer.CellPointer, remainder: Data) {
            self.pointer = pointer
            self.remainder = remainder
        }
    }

    public class func deserializeFift(data: String) throws -> [Cell] {
        guard !data.isEmpty else {
            throw ErrorTonSdkSwift("Can't deserialize. Empty fift hex.")
        }

        let re = try! NSRegularExpression(pattern: "(\\s*)x\\{([0-9a-zA-Z_]+)\\}\n?", options: .caseInsensitive)
        let matches = re.matches(in: data, options: [], range: NSRange(location: 0, length: data.utf16.count))
        
        guard !matches.isEmpty else {
            fatalError("Can't deserialize. Bad fift hex.")
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
    
    
    public class func deserializeHeader(bytes: Data) throws -> BocHeader {
        guard bytes.count >= 4 + 1 else {
            throw ErrorTonSdkSwift("Not enough bytes for magic prefix")
        }

        let crcbytes = bytes[0..<bytes.count - 4]
        var mutableBytes = bytes
        let prefix = mutableBytes[mutableBytes.startIndex..<mutableBytes.startIndex + 4]
        mutableBytes.removeFirst(4)
        let flagsByte = mutableBytes.removeFirst()
        
        var header = BocHeader(hasIndex: true,
                               hashCrc32: nil,
                               hasCacheBits: false,
                               flags: 0,
                               sizeBytes: Int(flagsByte),
                               offsetBytes: .init(),
                               cellsNum: .init(),
                               rootsNum: .init(),
                               absentNum: .init(),
                               totCellsSize: .init(),
                               rootList: .init(),
                               cellsData: .init())

        if prefix == REACH_BOC_MAGIC_PREFIX {
            header.hasIndex = flagsByte & 128 != 0
            header.hasCacheBits = flagsByte & 32 != 0
            header.flags = (flagsByte & 16) * 2 + (flagsByte & 8)
            header.sizeBytes = Int(flagsByte % 8)
            header.hashCrc32 = Int(flagsByte) & 64
        } else if prefix == LEAN_BOC_MAGIC_PREFIX {
            header.hashCrc32 = 0
        } else if prefix == LEAN_BOC_MAGIC_PREFIX_CRC {
            header.hashCrc32 = 1
        } else {
            throw ErrorTonSdkSwift("bad magic prefix")
        }

        guard bytes.count >= 1 + 5 * header.sizeBytes else {
            throw ErrorTonSdkSwift("not enough bytes for encoding cells counters")
        }

        let offsetBytes = mutableBytes.removeFirst()
        header.cellsNum = mutableBytes[mutableBytes.startIndex..<mutableBytes.startIndex + header.sizeBytes].toBigUInt()
        mutableBytes.removeFirst(header.sizeBytes)
        header.rootsNum = mutableBytes[mutableBytes.startIndex..<mutableBytes.startIndex + header.sizeBytes].toBigUInt()
        mutableBytes.removeFirst(header.sizeBytes)
        header.absentNum = mutableBytes[mutableBytes.startIndex..<mutableBytes.startIndex + header.sizeBytes].toBigUInt()
        mutableBytes.removeFirst(header.sizeBytes)
        header.totCellsSize = mutableBytes[mutableBytes.startIndex..<mutableBytes.startIndex + Int(offsetBytes)].toBigUInt()
        mutableBytes.removeFirst(Int(offsetBytes))
        header.offsetBytes = offsetBytes
        
        guard BigUInt(bytes.count) >= header.rootsNum * BigUInt(header.sizeBytes) else {
            throw ErrorTonSdkSwift("not enough bytes for encoding root cells hashes")
        }

        header.rootList = (0..<header.rootsNum).map { _ in
            let refIndex = mutableBytes[mutableBytes.startIndex..<mutableBytes.startIndex + header.sizeBytes].toBigUInt()
            mutableBytes.removeFirst(header.sizeBytes)
            return refIndex
        }

        if header.hasIndex {
            guard bytes.count >= BigUInt(header.offsetBytes) * header.cellsNum else {
                throw ErrorTonSdkSwift("not enough bytes for index encoding")
            }
            mutableBytes.removeFirst(Int(BigUInt(header.offsetBytes) * header.cellsNum))
        }

        guard bytes.count >= header.totCellsSize else {
            throw ErrorTonSdkSwift("not enough bytes for cells data")
        }
        
        header.cellsData = mutableBytes[mutableBytes.startIndex..<mutableBytes.startIndex + Int(header.totCellsSize)]
        mutableBytes.removeFirst(Int(header.totCellsSize))

        if header.hashCrc32 != nil && header.hashCrc32 != 0 {
            guard bytes.count >= 4 else {
                throw ErrorTonSdkSwift("not enough bytes for crc32c hashsum")
            }

            let result = crcbytes.crc32cBytesLE()

            let crc32Bytes = mutableBytes[mutableBytes.startIndex..<mutableBytes.startIndex + 4]
            mutableBytes.removeFirst(4)
            
            if !(result == crc32Bytes) {
                throw ErrorTonSdkSwift("crc32c hashsum mismatch")
            }
        }

        guard mutableBytes.isEmpty else {
            throw ErrorTonSdkSwift("too much bytes in boc serialization")
        }

        return header
    }
    
    
    public class func deserializeCell(remainder: Data, refIndexSize: Int) throws -> CellData {
        guard remainder.count >= 2 else {
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

        guard mutableRemainder.count >= 1 else {
            throw ErrorTonSdkSwift("Not enough bytes to encode cell data")
        }

        let bitsDescriptor = mutableRemainder.removeFirst()

        let isAugmented: Bool = (bitsDescriptor & 1) != 0
        let dataSize: Int = (Int(bitsDescriptor >> 1)) + (isAugmented ? 1 : 0)
        let hashesSize: Int = Int(hasHashes ? (level + 1) * 32 : 0)
        let depthSize: Int = Int(hasHashes ? (level + 1) * 2 : 0)
        
        guard mutableRemainder.count >= hashesSize + depthSize + dataSize + refIndexSize * Int(totalRefs) else {
            throw ErrorTonSdkSwift("Not enough bytes to encode cell data")
        }

        if hasHashes {
            mutableRemainder.removeFirst(hashesSize + depthSize)
        }

        let bits = if isAugmented  {
            try mutableRemainder[mutableRemainder.startIndex..<mutableRemainder.startIndex + dataSize].toBits().rollback()
        } else {
            mutableRemainder[mutableRemainder.startIndex..<mutableRemainder.startIndex + dataSize].toBits()
        }

        if isExotic && bits.count < 8 {
            throw ErrorTonSdkSwift("Not enough bytes for an exotic cell type")
        }

        let type: Cell.CellType!
        if isExotic {
            guard let unwrapedType = Cell.CellType(rawValue: Int8([Bit](bits[0..<8]).toBigInt())) else {
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

        let pointer = try CellPointer(type: type, builder: CellBuilder(size: bits.count).storeBits(bits), refs: refs)
        
        
        return CellData(pointer: pointer, remainder: mutableRemainder)
    }

    public class func deserialize(data: Data, checkMerkleProofs: Bool = false) throws -> [Cell] {
        var hasMerkleProofs = false
        var pointers: [CellPointer] = []
        let header: BocHeader = try deserializeHeader(bytes: data)
        let cellsNum = header.cellsNum
        let sizeBytes = header.sizeBytes
        let cellsData = header.cellsData
        let rootList = header.rootList

        var remainder: Data = cellsData
        for _ in 0..<cellsNum {
            let deserialized = try deserializeCell(remainder: remainder, refIndexSize: sizeBytes)
            remainder = deserialized.remainder
            pointers.append(deserialized.pointer)
        }
        

        for index in 0..<pointers.count {
            let pointerIndex = pointers.count - index - 1
            let cellBuilder = pointers[pointerIndex].builder
            let cellType = pointers[pointerIndex].type
//            print(index)

            for refIndex in pointers[pointerIndex].refs {
                let refBuilder = pointers[Int(refIndex)].builder
                let refType = pointers[Int(refIndex)].type

                if refIndex < pointerIndex {
                    throw ErrorTonSdkSwift("Topological order is broken")
                }

                if refType == .merkleProof || refType == .merkleUpdate {
                    hasMerkleProofs = true
                }

                try cellBuilder.storeRef(refBuilder.cell(refType))
            }

            if cellType == .merkleProof || cellType == .merkleUpdate {
                hasMerkleProofs = true
            }

            pointers[pointerIndex].cell = try cellBuilder.cell(cellType)
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
    
    public class func depthFirstSort(root: [Cell]) throws -> (cells: [Cell], hashmap: [String: Int]) {
        #warning("fix multiple root cells serialization")
        var stack: [CellNode] = [CellNode(cell: try Cell(refs: root), children: root.count, scanned: 0)]
        var cells: [(cell: Cell, hash: String)] = []
        var hashIndexes: [String: Int] = [:]

        /// Process tree node to ordered cells list
        func process(node: CellNode) throws {
            var node = node
            node.scanned += 1
            let ref = node.cell.refs[node.scanned]
            

            let hash = try ref.hash()
            if let index = hashIndexes[hash] {
                cells.append(cells.remove(at: index))
            } else {
                cells.append((cell: ref, hash: hash))
            }
            
            stack.append(CellNode(cell: ref, children: ref.refs.count, scanned: 0))

            hashIndexes[hash] = cells.count - 1
        }

        /// Loop through multi-tree and make depth-first search till last node
        while !stack.isEmpty {
            var current = stack[stack.count - 1]

            if current.children != current.scanned {
                try process(node: current)
            } else {
                while !stack.isEmpty, let last = stack.last, last.children == last.scanned {
                    stack.removeLast()
                    current = stack.last!
                }

                if !stack.isEmpty {
                    try process(node: current)
                }
            }
        }

        let resultCells = cells.compactMap { $0.cell }
        var hashmap: [String: Int] = [:]
        for (i, cellHashTuple) in cells.enumerated() {
            hashmap[cellHashTuple.hash] = i
        }

        return (cells: resultCells, hashmap: hashmap)
    }


    public class func breadthFirstSort(root: [Cell]) throws -> (cells: [Cell], hashmap: [String: Int]) {
        var queue = root
        var cells: [(cell: Cell, hash: String)] = try root.map { ($0, try $0.hash()) }
        var hashIndexes: [String: Int] = Dictionary(uniqueKeysWithValues: cells.enumerated().map { ($1.hash, $0) })

        // Process tree node to ordered cells list
        func process(node: Cell) throws {
            let hash = try node.hash()

            if let index = hashIndexes[hash] {
                cells.append(cells.remove(at: index))
            } else {
                cells.append((cell: node, hash: hash))
            }

            queue.append(node)
            hashIndexes[hash] = cells.count - 1
        }

        // Loop through multi-tree and make breadth-first search till last node
        while !queue.isEmpty {
            let count = queue.count

            for _ in 0..<count {
                let node = queue.removeFirst()
                try node.refs.forEach { ref in
                    try process(node: ref)
                }
            }
        }

        var hashmap: [String: Int] = [:]
        for (i, (_, hash)) in cells.enumerated() {
            hashmap[hash] = i
        }

        let resultCells = cells.map { $0.cell }

        return (resultCells, hashmap)
    }
    
    
    public class func serializeCell(cell: Cell, hashmap: [String: Int], refIndexSize: Int) throws -> [Bit] {
        let representation = cell.getRefsDescriptor() + cell.getBitsDescriptor() + cell.getAugmentedBits()
        let serialized = try cell.refs.reduce(into: representation) { acc, ref in
            if let refIndex = hashmap[try ref.hash()] {
                let bits = try (0..<refIndexSize).map { i in
                    try Bit(((refIndex >> i) & 1) == 1 ? 1 : 0)
                }
                acc.append(contentsOf: bits.reversed())
            }
        }
        return serialized
    }

    public class func serialize(root: [Cell], options: BOCOptions = .init()) throws -> Data {
        // TODO: test more than 1 root cells support
        let hasIndex = options.hasIndex ?? false
        let hasCacheBits = options.hasCacheBits ?? false
        let hashCrc32 = options.hashCrc32 ?? true
        let topologicalOrder = options.topologicalOrder ?? "breadth-first"
        let flags = options.flags ?? 0

        let sortedCells: (cells: [Cell], hashmap: [String: Int])
        if topologicalOrder == "breadth-first" {
            sortedCells = try breadthFirstSort(root: root)
        } else {
            sortedCells = try depthFirstSort(root: root)
        }

        let cellsList = sortedCells.cells
        let hashmap = sortedCells.hashmap

        let cellsNum = cellsList.count
        let size = String(cellsNum, radix: 2).count
        let sizeBytes = max(Int(ceil(Double(size) / 8)), 1)
        var cellsBits = [Bit]()
        var sizeIndex = [Int]()

        for cell in cellsList {
            let bits = try serializeCell(cell: cell, hashmap: hashmap, refIndexSize: sizeBytes * 8)
            cellsBits += bits
            sizeIndex.append(bits.count / 8)
        }

        let fullSize = cellsBits.count / 8
        let offsetBits = String(fullSize, radix: 2).count
        let offsetBytes = max(Int(ceil(Double(offsetBits) / 8)), 1)
        let builderSize = (32 + 3 + 2 + 3 + 8)
            + (cellsBits.count)
            + ((sizeBytes * 8) * 4)
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
            .storeUInt(0, sizeBytes * 8)

        if hasIndex {
            for index in 0..<cellsList.count {
                try result.storeUInt(BigUInt(sizeIndex[index]), offsetBytes * 8)
            }
        }

        let augmentedBits = try result.storeBits(cellsBits).bits.augment()
        let bytes = try augmentedBits.toBytes()

        if hashCrc32 {
            let hashsum = bytes.crc32cBytesLE()
            return bytes + hashsum
        }

        return bytes
    }
}


