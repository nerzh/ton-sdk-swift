//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 02.02.2024.
//

import Foundation

//open class Builder {
//    private var size: Int
//    private var bits: Bits
//    private var refs: [Cell]
//
//    var bytes: [UInt8] {
//        return bitsToBytes(bits)
//    }
//
//    var remainder: Int {
//        return size - bits.count
//    }
//
//    init(size: Int = 1023) {
//        self.size = size
//        self.bits = []
//        self.refs = []
//    }
//
//    mutating func storeSlice(_ slice: Slice) -> Self {
//        Builder.checkSliceType(slice)
//        let sliceBits = slice.bits
//        let sliceRefs = slice.refs
//
//        checkBitsOverflow(sliceBits.count)
//        storeBits(sliceBits)
//
//        for ref in sliceRefs {
//            storeRef(ref)
//        }
//
//        return self
//    }
//
//    mutating func storeRef(_ ref: Cell) -> Self {
//        Builder.checkRefsType([ref])
//        checkRefsOverflow(1)
//        refs.append(ref)
//
//        return self
//    }
//
//}
