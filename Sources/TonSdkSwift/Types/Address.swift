//
//  File.swift
//
//
//  Created by Oleh Hudeichuk on 30.01.2024.
//

import Foundation

public struct Address: Equatable {
    
    public enum AddressType: String {
        case base64
        case raw
    }
    
    public typealias ParsedREsult = (bounceable: Bool, testOnly: Bool, workchain: Int8, hash: Data, type: AddressType)
    
    static let FLAG_BOUNCEABLE: UInt8 = 0x11
    static let FLAG_NON_BOUNCEABLE: UInt8 = 0x51
    static let FLAG_TEST_ONLY: UInt8 = 0x80
    
    public var hash: Data
    public var workchain: Int8
    public var bounceable: Bool
    public var testOnly: Bool
    public var type: AddressType
    
    public init(address: String,
                workchain: Int8? = nil,
                bounceable: Bool? = nil,
                testOnly: Bool? = nil,
                hash: Data? = nil
    ) throws {
        let isEncoded = Address.isEncoded(address)
        let isRaw = Address.isRaw(address)
        
        let result: ParsedREsult = if isEncoded {
            try Address.parseEncoded(address)
        } else if isRaw {
            try Address.parseRaw(address)
        } else {
            throw ErrorTonSdkSwift("Address: can't parse address. Unknown type.")
        }
        
        self.workchain = workchain ?? result.workchain
        self.bounceable = bounceable ?? result.bounceable
        self.testOnly = testOnly ?? result.testOnly
        self.hash = hash ?? result.hash
        self.type = result.type
    }
    
    public static func == (lhs: Address, rhs: Address) -> Bool {
        lhs.hash == rhs.hash && lhs.workchain == rhs.workchain
    }
    
    public static func isValid(_ address: String) -> Bool {
        do {
            _ = try Address(address: address)
            return true
        } catch {
            return false
        }
    }
    
    private static func isEncoded(_ address: String) -> Bool {
        address[#"^([a-zA-Z0-9_-]{48}|[a-zA-Z0-9\/\+]{48})$"#]
    }
    
    private static func isRaw(_ address: String) -> Bool {
        address[#"^-?[0-9]:[a-zA-Z0-9]{64}$"#]
    }
    
    private static func encodeTag(bounceable: Bool = false, testOnly: Bool = false) -> UInt8 {
        let tag: UInt8 = bounceable ? FLAG_BOUNCEABLE : FLAG_NON_BOUNCEABLE
        return testOnly ? (tag | FLAG_TEST_ONLY) : tag
    }
    
    private static func decodeTag(tag: UInt8) -> (bounceable: Bool, testOnly: Bool) {
        let testOnly = (tag & FLAG_TEST_ONLY) != 0
        
        let bounceable: Bool = if testOnly {
            (tag ^ FLAG_TEST_ONLY) == FLAG_BOUNCEABLE
        } else {
            tag == FLAG_BOUNCEABLE
        }
        
        return (bounceable: bounceable, testOnly: testOnly)
    }
    
    private static func parseEncoded(_ value: String) throws -> ParsedREsult {
        let base64: String = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let data = try base64.base64ToBytes()
        
        let address = data[0..<34]
        let checksum = data[34..<36]
        
        if address.crc16BytesBE() != checksum {
            throw ErrorTonSdkSwift("Address not equal to checksum")
        }
        
        let buffer = address[0..<2]
        let hash = address[2..<34]
        let tag = buffer[0]
        let workchain = Int8(bitPattern: buffer[1])
        
        let decodedTag = Address.decodeTag(tag: tag)
        let bounceable: Bool = decodedTag.bounceable
        let testOnly: Bool = decodedTag.testOnly
        
        return (bounceable: bounceable, testOnly: testOnly, workchain: workchain, hash: hash, type: .base64)
    }
    
    private static func parseRaw(_ address: String) throws -> ParsedREsult {
        let data = address.split(separator: ":")
        guard
            data.count == 2,
            let workchain = Int8(data[0]),
            data[1].count == 64
        else {
            throw ErrorTonSdkSwift("Bad Raw address: \(address)")
        }
        let hex: String = .init(data[1])
        
        let hash: Data = try hex.hexToBytes()
        
        return (bounceable: false, testOnly: false, workchain: workchain, hash: hash, type: .raw)
    }
    
    public func toString(
        type: AddressType = .base64,
        workchain: Int8? = nil,
        bounceable: Bool? = nil,
        testOnly: Bool? = nil,
        urlSafe: Bool = true
    ) -> String {
        let workchain = workchain ?? self.workchain
        let bounceable = bounceable ?? self.bounceable
        let testOnly = testOnly ?? self.testOnly
        
        switch type {
        case .raw:
            return "\(workchain):\(hash.toHex())".lowercased()
        case .base64:
            let tag: UInt8 = Address.encodeTag(bounceable: bounceable, testOnly: testOnly)
            var address = Data([tag])
            address.append(contentsOf: [UInt8(Int(workchain) & 0xff)])
            address.append(hash)
            let checksum: Data = address.crc16BytesBE()
            let base64: String = (address + checksum).toBase64()
            if urlSafe {
                return base64.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
            } else {
                return base64.replacingOccurrences(of: "_", with: "/").replacingOccurrences(of: "-", with: "+")
            }
        }
    }
}
