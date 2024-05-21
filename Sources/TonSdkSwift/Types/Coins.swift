//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 01.02.2024.
//

import Foundation
import BigInt
import SwiftExtensionsPack


public struct Coins {
    
    private static let DEFAULT_DECIMALS: Int = 9
    private var _nanoValue: BigInt
    private var _decimals: Int
    public var decimals: Int { _decimals }
    public var nanoValue: BigInt { _nanoValue }
    public var coinsValue: Double {
        Double(toFloatString)!
    }
    
    /// COINS
    public init(_ coinsValue: any BinaryFloatingPoint) {
        self.init(coinsValue: coinsValue, decimals: Self.DEFAULT_DECIMALS)
    }
    
    public init(_ coinsValue: Decimal) {
        self.init(coinsValue: coinsValue, decimals: Self.DEFAULT_DECIMALS)
    }
    
    public init(_ coinsValue: any SignedInteger) {
        self.init(coinsValue: coinsValue, decimals: Self.DEFAULT_DECIMALS)
    }
    
    public init(_ coinsValue: any UnsignedInteger) {
        self.init(coinsValue: coinsValue, decimals: Self.DEFAULT_DECIMALS)
    }
    
    public init(coinsValue: any BinaryFloatingPoint, decimals: Int) {
        if let coinsValue = coinsValue as? Double {
            let stringValue = coinsValue.toString()
            self = stringValue.toCoins(decimals: decimals)
        } else if let coinsValue = coinsValue as? Float {
            let stringValue = coinsValue.toString()
            self = stringValue.toCoins(decimals: decimals)
        } else {
            fatalError("Unsupported float type")
        }
    }
    
    public init(coinsValue: Decimal, decimals: Int) {
        let stringValue = "\(coinsValue)"
        self = stringValue.toCoins(decimals: decimals)
    }
    
    public init(coinsValue: any SignedInteger, decimals: Int) {
        self = "\(coinsValue)".toCoins(decimals: decimals)
    }
    
    public init(coinsValue: any UnsignedInteger, decimals: Int) {
        self = "\(coinsValue)".toCoins(decimals: decimals)
    }
    
    
    /// NANO COINS
    public init(nanoValue: any SignedInteger) {
        self.init(nanoValue: nanoValue, decimals: Self.DEFAULT_DECIMALS)
    }
    
    public init(nanoValue: any UnsignedInteger) {
        self.init(nanoValue: nanoValue, decimals: Self.DEFAULT_DECIMALS)
    }
    
    public init(nanoValue: String) throws {
        try self.init(nanoValue: nanoValue, decimals: Self.DEFAULT_DECIMALS)
    }
    
    public init(nanoValue: any BinaryFloatingPoint) {
        self.init(nanoValue: nanoValue, decimals: Self.DEFAULT_DECIMALS)
    }
    
    public init(nanoValue: any SignedInteger, decimals: Int) {
        self._nanoValue = .init(nanoValue)
        self._decimals = decimals
    }
    
    public init(nanoValue: any UnsignedInteger, decimals: Int) {
        self._nanoValue = .init(nanoValue)
        self._decimals = decimals
    }
    
    public init(nanoValue: String, decimals: Int) throws {
        guard let nanoTokens: BigInt = .init(nanoValue) else {
            throw ErrorTonSdkSwift("Convert string \(nanoValue) to BigInt failed")
        }
        self._nanoValue = nanoTokens
        self._decimals = decimals
    }
    
    public init(nanoValue: any BinaryFloatingPoint, decimals: Int) {
        self._nanoValue = .init(nanoValue)
        self._decimals = decimals
    }
    
    
    
    public var toFloatString: String {
        let balanceCount = String(self.nanoValue).count
        let different = balanceCount - decimals
        var floatString = ""
        var isFloat: Bool = false
        if different <= 0 {
            floatString = "0."
            isFloat = true
            for _ in 0..<different * -1 {
                floatString.append("0")
            }
            floatString.append(String(self.nanoValue))
        } else {
            var counter = different
            for char in String(self.nanoValue) {
                if counter == 0 {
                    floatString.append(".")
                    isFloat = true
                }
                floatString.append(char)
                counter -= 1
            }
        }

        if isFloat {
            floatString = floatString.replace(#"(\.+|0+|\.0+)$"#, "")
        }
        return floatString
    }
    
    public mutating func updateDecimals(to: Int) {
        self = toDecimals(to)
    }
    
    public func toDecimals(_ to: Int) -> Self {
        var nanoValue: BigInt
        if decimals > to {
            nanoValue = self.nanoValue / BigInt(10**(decimals - Int(to)))
        } else {
            nanoValue = self.nanoValue * BigInt(10**(abs(decimals - Int(to))))
        }
        return .init(nanoValue: nanoValue, decimals: to)
    }
}



extension Coins: Equatable, Comparable, Hashable {
    
    public static func == (lhs: Coins, rhs: Coins) -> Bool {
        if lhs.decimals > rhs.decimals {
            return lhs.nanoValue == rhs.toDecimals(lhs.decimals).nanoValue
        } else {
            return lhs.toDecimals(rhs.decimals).nanoValue == rhs.nanoValue
        }
    }
    
    public static func < (lhs: Coins, rhs: Coins) -> Bool {
        if lhs.decimals > rhs.decimals {
            return lhs.nanoValue < rhs.toDecimals(lhs.decimals).nanoValue
        } else {
            return lhs.toDecimals(rhs.decimals).nanoValue < rhs.nanoValue
        }
    }
    
    public static func += (lhs: inout Coins, rhs: Coins) {
        let result = lhs + rhs
        lhs._nanoValue = result.nanoValue
        lhs._decimals = result.decimals
    }
    
    public static func -= (lhs: inout Coins, rhs: Coins) {
        let result = lhs - rhs
        lhs._nanoValue = result.nanoValue
        lhs._decimals = result.decimals
    }
    
    public static func /= (lhs: inout Coins, rhs: Coins) {
        let result = lhs / rhs
        lhs._nanoValue = result.nanoValue
        lhs._decimals = result.decimals
    }
    
    public static func *= (lhs: inout Coins, rhs: Coins) {
        let result = lhs * rhs
        lhs._nanoValue = result.nanoValue
        lhs._decimals = result.decimals
    }
    
    public static func %= (lhs: inout Coins, rhs: Coins) {
        let result = lhs % rhs
        lhs._nanoValue = result.nanoValue
        lhs._decimals = result.decimals
    }
    
#warning("Add additional operators")
//    public static func &= (lhs: inout Coins, rhs: Coins) {
//        lhs._nanoValue &= rhs.nanoValue
//    }
//    
//    public static func |= (lhs: inout Coins, rhs: Coins) {
//        lhs._nanoValue |= rhs.nanoValue
//    }
//    
//    public static func ^= (lhs: inout Coins, rhs: Coins) {
//        lhs._nanoValue ^= rhs.nanoValue
//    }
//    
//    prefix public static func ~ (x: Coins) -> Coins {
//        .init(nanoValue: ~x.nanoValue, decimals: x.decimals)
//    }
//
//    public static func <<= <RHS>(lhs: inout Coins, rhs: RHS) where RHS : BinaryInteger {
//        lhs._nanoValue <<= rhs
//    }
//
//    public static func >>= <RHS>(lhs: inout Coins, rhs: RHS) where RHS : BinaryInteger {
//        lhs._nanoValue >>= rhs
//    }

    public static func * (lhs: Coins, rhs: Coins) -> Coins {
        if lhs.decimals > rhs.decimals {
            return .init(nanoValue: (lhs.nanoValue * rhs.nanoValue) / BigInt(10**(rhs.decimals)), decimals: lhs.decimals)
        } else {
            return .init(nanoValue: (lhs.nanoValue * rhs.nanoValue) / BigInt(10**(lhs.decimals)), decimals: rhs.decimals)
        }
    }
    
    public static func + (lhs: Coins, rhs: Coins) -> Coins {
        if lhs.decimals > rhs.decimals {
            return .init(nanoValue: lhs.nanoValue + rhs.toDecimals(lhs.decimals).nanoValue, decimals: lhs.decimals)
        } else {
            return .init(nanoValue: lhs.toDecimals(rhs.decimals).nanoValue + rhs.nanoValue, decimals: rhs.decimals)
        }
    }
    
    public static func - (lhs: Coins, rhs: Coins) -> Coins {
        if lhs.decimals > rhs.decimals {
            return .init(nanoValue: lhs.nanoValue - rhs.toDecimals(lhs.decimals).nanoValue, decimals: lhs.decimals)
        } else {
            return .init(nanoValue: lhs.toDecimals(rhs.decimals).nanoValue - rhs.nanoValue, decimals: rhs.decimals)
        }
    }
    
    public static func / (lhs: Coins, rhs: Coins) -> Coins {
        if lhs.decimals > rhs.decimals {
            return .init(coinsValue: lhs.nanoValue / rhs.toDecimals(lhs.decimals).nanoValue, decimals: lhs.decimals)
        } else {
            return .init(coinsValue: lhs.toDecimals(rhs.decimals).nanoValue / rhs.nanoValue, decimals: rhs.decimals)
        }
    }
    
    public static func % (lhs: Coins, rhs: Coins) -> Coins {
        if lhs.decimals > rhs.decimals {
            return .init(nanoValue: lhs.nanoValue % rhs.toDecimals(lhs.decimals).nanoValue, decimals: lhs.decimals)
        } else {
            return .init(nanoValue: lhs.toDecimals(rhs.decimals).nanoValue % rhs.nanoValue, decimals: rhs.decimals)
        }
    }
}



public extension String {
    
    var isValidCoinsAmount: Bool {
        self[(#"(^\d+$|(^\d+\.\d+$))"#)]
    }
    
    var toCoins: Coins {
        toCoins(decimals: 9)
    }
    
    func toCoins(decimals: Int) -> Coins {
        do {
            return try toCoinsThrowing(decimals: decimals)
        } catch {
            fatalError(String.init(reflecting: error))
        }
    }
    
    func toCoinsThrowing(decimals: Int) throws -> Coins {
        if decimals < 0 { throw ErrorTonSdkSwift("toCoinsThrowing: negative decimals \(decimals)") }
        let balance: String = self.replace(#","#, ".").replace(#"\.$"#, "")
        
        var result: String = ""
        let match: [Int: String] = balance.regexp(#"(\d+)\.(\d+)"#)
        let isFloat: Bool = match[2] != nil
        if isFloat {
            if
                let integer: String = match[1],
                let float: String = match[2]?.replace(#"0+$"#, "")
            {
                var temp: String = ""
                var counter = decimals
                for char in float {
                    if counter == 0 {
                        temp.append(".")
                    }
                    counter -= 1
                    temp.append(char)
                }
                if counter < 0 {
                    temp = temp.replace(#"\.\d*$"#, "")
                }
                if counter > 0 {
                    for _ in 0..<counter {
                        temp.append("0")
                    }
                }
                if let int = BigInt(integer), int > 0 {
                    temp = "\(integer)\(temp)"
                }
                result = temp
            }
        } else {
            result.append(balance.replace(#"^0+"#, ""))
            for _ in 0..<decimals {
                result.append("0")
            }
        }
        
        result = result.isEmpty ? "0" : result
        
        let coins = try Coins(nanoValue: result, decimals: decimals)
        return coins
    }
}


