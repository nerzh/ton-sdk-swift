//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 04.02.2024.
//

import Foundation
import XCTest
import TonSdkSwift
import BigInt
import SwiftExtensionsPack

final class CoinsTests: XCTestCase {
    
    func testCins() async throws {
        var coins: Coins = .init(10)
        XCTAssertEqual(coins.nanoValue, 10_000_000_000)
        
        coins = .init(13)
        XCTAssertEqual(coins.nanoValue, 13_000_000_000)
        
        coins = .init(13.2)
        XCTAssertEqual(coins.nanoValue, 13_200_000_000)
        
        coins = .init(0.2)
        XCTAssertEqual(coins.nanoValue, 200_000_000)
        
        coins = .init(coinsValue: 1, decimals: 2)
        XCTAssertEqual(coins.nanoValue, 100)
        XCTAssertEqual(coins.coinsValue, 1)
        XCTAssertEqual(coins.toFloatString, "1")
        
        coins = .init(coinsValue: 0.1, decimals: 2)
        XCTAssertEqual(coins.nanoValue, 10)
        XCTAssertEqual(coins.coinsValue, 0.1)
        XCTAssertEqual(coins.toFloatString, "0.1")
        
        coins = .init(coinsValue: Decimal(0), decimals: 0)
        XCTAssertEqual(coins.nanoValue, 0)
        XCTAssertEqual(coins.coinsValue, 0)
        XCTAssertEqual(coins.toFloatString, "0")
        
        coins = try .init(nanoValue: "50000000000", decimals: 0)
        XCTAssertEqual(coins.toFloatString, "50000000000")
        XCTAssertEqual(coins.nanoValue, 50_000_000_000)
        XCTAssertEqual(coins.coinsValue, 50_000_000_000)
        
        
        coins = .init(coinsValue: Decimal(50_000_000_000), decimals: 0)
        XCTAssertEqual(coins.nanoValue, 50_000_000_000)
        XCTAssertEqual(coins.coinsValue, 50_000_000_000)
        XCTAssertEqual(coins.toFloatString, "50000000000")
        
        coins = Coins(coinsValue: 2, decimals: 5) * Coins(coinsValue: 2, decimals: 10)
        XCTAssertEqual(coins.nanoValue, 4_0000000000)
        XCTAssertEqual(coins.coinsValue, 4)
        XCTAssertEqual(coins.toFloatString, "4")
        
        coins = Coins(coinsValue: 2, decimals: 10) * Coins(coinsValue: 2, decimals: 5)
        XCTAssertEqual(coins.nanoValue, 4_0000000000)
        XCTAssertEqual(coins.coinsValue, 4)
        XCTAssertEqual(coins.toFloatString, "4")
        
        coins = Coins(coinsValue: 2, decimals: 10) + Coins(coinsValue: 2, decimals: 5)
        XCTAssertEqual(coins.nanoValue, 4_0000000000)
        XCTAssertEqual(coins.coinsValue, 4)
        XCTAssertEqual(coins.toFloatString, "4")
        
        coins = Coins(coinsValue: 6, decimals: 5) / Coins(coinsValue: 2, decimals: 10)
        XCTAssertEqual(coins.nanoValue, 3_0000000000)
        XCTAssertEqual(coins.coinsValue, 3)
        XCTAssertEqual(coins.toFloatString, "3")
        
        coins = Coins(coinsValue: 71, decimals: 10) % Coins(coinsValue: 3, decimals: 5)
        XCTAssertEqual(coins.nanoValue, 2_0000000000)
        XCTAssertEqual(coins.coinsValue, 2)
        XCTAssertEqual(coins.toFloatString, "2")
        
        /// <>==
        XCTAssertTrue(Coins(coinsValue: 2, decimals: 10) == Coins(coinsValue: 2, decimals: 2))
        XCTAssertTrue(Coins(coinsValue: 1, decimals: 10) < Coins(coinsValue: 2, decimals: 2))
        XCTAssertTrue(Coins(coinsValue: 3, decimals: 1) >= Coins(coinsValue: 1, decimals: 15))
    }
}
