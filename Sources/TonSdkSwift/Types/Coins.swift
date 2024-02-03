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
    private var amount: BigInt
    let decimals: Int
    
    private init(nanoValue: any SignedInteger, decimals: Int) {
        self.amount = .init(nanoValue)
        self.decimals = decimals
    }
    
    public init(nanoValue: String, decimals: Int) throws {
        guard let nanoTokens: BigInt = .init(nanoValue) else {
            throw ErrorTonSdkSwift("Convert string \(nanoValue) to BigInt failed")
        }
        self.amount = nanoTokens
        self.decimals = decimals
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
    
    var toFloatString: String {
        let balanceCount = String(self).count
        let different = balanceCount - decimals
        var floatString = ""
        if different <= 0 {
            floatString = "0."
            for _ in 0..<different * -1 {
                floatString.append("0")
            }
            floatString.append(String(self))
        } else {
            var counter = different
            for char in String(self) {
                if counter == 0 {
                    floatString.append(".")
                }
                floatString.append(char)
                counter -= 1
            }
        }

        return floatString.replace(#"(\.|)0+$"#, "")
    }
}



extension Coins: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) {
        self.init(value)
    }
}



extension Coins: SignedInteger {
    
    public var magnitude: BigUInt {
        amount.magnitude
    }
    
    public var words: BigInt.Words {
        amount.words
    }
    
    public var bitWidth: Int {
        amount.bitWidth
    }
    
    public var trailingZeroBitCount: Int {
        amount.trailingZeroBitCount
    }
    
    public init<T>(truncatingIfNeeded source: T) where T : BinaryInteger {
        self.amount = BigInt(source)
        self.decimals = Self.DEFAULT_DECIMALS
    }
    
    public init<T>(clamping source: T) where T : BinaryInteger {
        self.amount = BigInt(source)
        self.decimals = Self.DEFAULT_DECIMALS
    }
    
    public init<T>(_ source: T) where T : BinaryInteger {
        self.amount = BigInt(source)
        self.decimals = Self.DEFAULT_DECIMALS
    }
    
    public init?<T>(exactly source: T) where T : BinaryInteger {
        self.amount = BigInt(source)
        self.decimals = Self.DEFAULT_DECIMALS
    }
    
    public init?<T>(exactly source: T) where T : BinaryFloatingPoint {
        self.amount = BigInt(source)
        self.decimals = Self.DEFAULT_DECIMALS
    }
    
    public init<T>(_ source: T) where T : BinaryFloatingPoint {
        self.amount = BigInt(source)
        self.decimals = Self.DEFAULT_DECIMALS
    }
    
    public static func <<= <RHS>(lhs: inout Coins, rhs: RHS) where RHS : BinaryInteger {
        lhs.amount <<= rhs
    }
    
    public static func >>= <RHS>(lhs: inout Coins, rhs: RHS) where RHS : BinaryInteger {
        lhs.amount >>= rhs
    }
    
    public static func /= (lhs: inout Coins, rhs: Coins) {
        lhs.amount /= rhs.amount
    }
    
    public static func *= (lhs: inout Coins, rhs: Coins) {
        lhs.amount *= rhs.amount
    }
    
    public static func %= (lhs: inout Coins, rhs: Coins) {
        lhs.amount %= rhs.amount
    }
    
    public static func &= (lhs: inout Coins, rhs: Coins) {
        lhs.amount &= rhs.amount
    }
    
    public static func |= (lhs: inout Coins, rhs: Coins) {
        lhs.amount |= rhs.amount
    }
    
    public static func ^= (lhs: inout Coins, rhs: Coins) {
        lhs.amount ^= rhs.amount
    }
    
    prefix public static func ~ (x: Coins) -> Coins {
        .init(~x.amount)
    }
    
    public static func * (lhs: Coins, rhs: Coins) -> Coins {
        .init(lhs.amount * rhs.amount)
    }
    
    public static func + (lhs: Coins, rhs: Coins) -> Coins {
        .init(lhs.amount + rhs.amount)
    }
    
    public static func - (lhs: Coins, rhs: Coins) -> Coins {
        .init(lhs.amount - rhs.amount)
    }
    
    public static func / (lhs: Coins, rhs: Coins) -> Coins {
        .init(lhs.amount / rhs.amount)
    }
    
    public static func % (lhs: Coins, rhs: Coins) -> Coins {
        .init(lhs.amount % rhs.amount)
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
        if coins > BigInt("340282366920938463463374607431768211455") {
            throw ErrorTonSdkSwift("toNanoCrystals: value \(coins) > UInt128.max 340282366920938463463374607431768211455")
        }
        return coins
    }
}
