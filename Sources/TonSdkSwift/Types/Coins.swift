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
    public let decimals: Int
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
        self.decimals = decimals
    }
    
    public init(nanoValue: any UnsignedInteger, decimals: Int) {
        self._nanoValue = .init(nanoValue)
        self.decimals = decimals
    }
    
    public init(nanoValue: String, decimals: Int) throws {
        guard let nanoTokens: BigInt = .init(nanoValue) else {
            throw ErrorTonSdkSwift("Convert string \(nanoValue) to BigInt failed")
        }
        self._nanoValue = nanoTokens
        self.decimals = decimals
    }
    
    public init(nanoValue: any BinaryFloatingPoint, decimals: Int) {
        self._nanoValue = .init(nanoValue)
        self.decimals = decimals
    }
    
    
    
    public var toFloatString: String {
        let balanceCount = String(self.nanoValue).count
        let different = balanceCount - decimals
        var floatString = ""
        if different <= 0 {
            floatString = "0."
            for _ in 0..<different * -1 {
                floatString.append("0")
            }
            floatString.append(String(self.nanoValue))
        } else {
            var counter = different
            for char in String(self.nanoValue) {
                if counter == 0 {
                    floatString.append(".")
                }
                floatString.append(char)
                counter -= 1
            }
        }

        return floatString == "0" ? floatString : floatString.replace(#"(\.|)0+$"#, "")
    }
}



extension Coins: Equatable, Comparable, Hashable {
    
    public static func < (lhs: Coins, rhs: Coins) -> Bool {
        lhs._nanoValue < rhs._nanoValue
    }
    
    public static func <<= <RHS>(lhs: inout Coins, rhs: RHS) where RHS : BinaryInteger {
        lhs._nanoValue <<= rhs
    }
    
    public static func >>= <RHS>(lhs: inout Coins, rhs: RHS) where RHS : BinaryInteger {
        lhs._nanoValue >>= rhs
    }
    
    public static func /= (lhs: inout Coins, rhs: Coins) {
        lhs._nanoValue /= rhs.nanoValue
    }
    
    public static func *= (lhs: inout Coins, rhs: Coins) {
        lhs._nanoValue *= rhs.nanoValue
    }
    
    public static func %= (lhs: inout Coins, rhs: Coins) {
        lhs._nanoValue %= rhs.nanoValue
    }
    
    public static func &= (lhs: inout Coins, rhs: Coins) {
        lhs._nanoValue &= rhs.nanoValue
    }
    
    public static func |= (lhs: inout Coins, rhs: Coins) {
        lhs._nanoValue |= rhs.nanoValue
    }
    
    public static func ^= (lhs: inout Coins, rhs: Coins) {
        lhs._nanoValue ^= rhs.nanoValue
    }
    
    prefix public static func ~ (x: Coins) -> Coins {
        .init(nanoValue: ~x.nanoValue, decimals: x.decimals)
    }
    
    public static func * (lhs: Coins, rhs: Coins) -> Coins {
        .init(nanoValue: lhs.nanoValue * rhs.nanoValue, decimals: lhs.decimals)
    }
    
    public static func + (lhs: Coins, rhs: Coins) -> Coins {
        .init(nanoValue: lhs.nanoValue + rhs.nanoValue, decimals: lhs.decimals)
    }
    
    public static func - (lhs: Coins, rhs: Coins) -> Coins {
       .init(nanoValue: lhs.nanoValue - rhs.nanoValue, decimals: lhs.decimals)
    }
    
    public static func / (lhs: Coins, rhs: Coins) -> Coins {
        .init(nanoValue: lhs.nanoValue / rhs.nanoValue, decimals: lhs.decimals)
    }
    
    public static func % (lhs: Coins, rhs: Coins) -> Coins {
        .init(nanoValue: lhs.nanoValue % rhs.nanoValue, decimals: lhs.decimals)
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
        if decimals < 0 { throw ErrorTonSdkSwift("toNanoCrystals: negative decimals \(decimals)") }
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
        
        let coins = try Coins(nanoValue: result, decimals: decimals)
//        if coins.nanoValue > BigInt("340282366920938463463374607431768211455") {
//            throw ErrorTonSdkSwift("toNanoCrystals: value \(coins) > UInt128.max 340282366920938463463374607431768211455")
//        }
        return coins
    }
}


