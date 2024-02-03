//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 30.01.2024.
//

import Foundation
import Crypto

public extension Data {
    
    func crc16() -> UInt16 {
        let poly: UInt16 = 0x1021
        var crc: UInt16 = 0
        
        for byte in self {
            crc ^= UInt16(byte) << 8
            
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ poly : crc << 1
            }
        }
        
        return crc & 0xffff
    }
    
    func crc16BytesBE() -> Data {
        let crc = crc16()
        let crcBytes = Swift.withUnsafeBytes(of: crc.bigEndian) { Data($0) }
        return crcBytes
    }
    
    func crc32c() -> UInt32 {
        let table: [UInt32] = (0..<256).map { i in
            (0..<8).reduce(i) { crc, _ in
                (crc & 1 == 1) ? (0x82f63b78 ^ (crc >> 1)) : (crc >> 1)
            }
        }
        
        var crc: UInt32 = 0xffffffff
        for byte in self {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xffffffff
    }
    
    func crc32cBytesLE() -> Data {
        let crc = crc32c()
        var littleEndianCrc = crc.littleEndian
        return Swift.withUnsafeBytes(of: &littleEndianCrc) { Data($0) }
    }
    
    func sha256() -> String {
        let digest = SHA256.hash(data: self)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func sha512() -> String {
        let digest = SHA512.hash(data: self)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
