//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 04.02.2024.
//

import Foundation
import XCTest
@testable import TonSdkSwift
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
    }
}
