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

final class CellBuilderTests: XCTestCase {
    func testHash() async throws {
        let builer: CellBuilder = .init()
        XCTAssertEqual(try builer.cell().hash(), "96a296d224f285c67bee93c30f8a309157f0daa35dc5b87e410b78630a09cfc7")
    }
    
    func testUInt() async throws {
        var builer: CellBuilder = .init()
        try builer.storeUInt(200, 30)
        XCTAssertEqual(try builer.cell().hash(), "e6a7bd4728b8b6267951833bed536c2e203ba91445a94905f358961cc685fbc2")
        
        builer = .init()
        try builer.storeUInt(BigUInt(powl(2, 30)) - 1, 30)
        XCTAssertEqual(try builer.cell().hash(), "20423e02436d18957feb0c7b303561df0d4061256f27cc51ef6595f03a3fab1d")
        
        builer = .init()
        XCTAssertThrowsError(try builer.storeUInt(BigUInt(powl(2, 30)), 30))
        
        builer = .init()
        try builer.storeUInt(0, 30)
        XCTAssertEqual(try builer.cell().hash(), "f41a95995fccb3bf442ae56e28cdf165a87290de141db9ec028b2af28846c0ea")
        
        builer = .init()
        try builer.storeUInt(BigUInt(powl(2, 1023)) - 1, 1023)
        XCTAssertEqual(try builer.cell().hash(), "82970d4664b7683c3d14d49b1f9ff34966128170301a7becc27af1adbe6a31c9")
    }
    
    func testInt() async throws {
        var builer: CellBuilder = .init()
        try builer.storeInt(-1, 8)
        XCTAssertEqual(try builer.cell().hash(), "81f3b92f222078b1606cfc3eebfee22216cc40ac99e6524b00fbaa933a6bcd47")
        
        builer = .init()
        try builer.storeInt(BigInt(-2 ** 31), 32)
        XCTAssertEqual(try builer.cell().hash(), "fc0483d2794fdfcf966ed72ff8a05edd06dce073f181ffa7dda71d80ac3119de")
        
        builer = .init()
        XCTAssertThrowsError(try builer.storeInt(BigInt(-2 ** 31 - 1), 32))
        
        builer = .init()
        XCTAssertThrowsError(try builer.storeInt(BigInt(2 ** 31), 32))
        
        builer = .init()
        try builer.storeInt(BigInt(2 ** 31 - 1), 32)
        XCTAssertEqual(try builer.cell().hash(), "dfd15d01ae93bac2ac4f4637ac40b957cda2f5036fe1c702b7fe3bd529be8063")
    }
    
    func testVarInt() async throws {
        let builer: CellBuilder = .init()
        try builer.storeVarInt(0, 8)
        XCTAssertEqual(try builer.cell().hash(), "eb58904b617945cdf4f33042169c462cd36cf1772a2229f06171fd899e920b7f")
    }
    
    func testVarUInt() async throws {
        var builer: CellBuilder = .init()
        try builer.storeVarUInt("1329227995784915872903807060280344575", 16)
        XCTAssertEqual(try builer.cell().hash(), "07d470f83cea8b41383aab0113b84f4be3842bc6ec0c46d84664a647d5550dc9")
        
        builer = .init()
        XCTAssertThrowsError(try builer.storeVarUInt("1329227995784915872903807060280344576", 16))
    }
    
    func testCoins() async throws {
        var builer: CellBuilder = .init()
        try builer.storeCoins(.init(0))
        XCTAssertEqual(try builer.cell().hash(), "5331fed036518120c7f345726537745c5929b8ea1fa37b99b2bb58f702671541")
        
        builer = CellBuilder.init()
        try builer.storeCoins(.init(13))
        XCTAssertEqual(try builer.cell().hash(), "f331a2b0952843b5323d24096759f6bc27d87f060b27ef8c54175d278a437400")
        
        builer = .init()
        let doubleCoins = BigInt(Double(2) ** Double(120)) - 1 /// you must to use BigInt for this number
        let coins: Coins = .init(nanoValue: doubleCoins)
        try builer.storeCoins(coins)
        XCTAssertEqual(try builer.cell().hash(), "07d470f83cea8b41383aab0113b84f4be3842bc6ec0c46d84664a647d5550dc9")
        
        builer = .init()
        XCTAssertThrowsError(try builer.storeCoins(.init(nanoValue: BigInt(Double(2) ** Double(120)))))
    }
    
    func testRefs() async throws {
        var builer: CellBuilder = .init()
        try builer.storeUInt(40, 32)
        let builer2: CellBuilder = .init()
        try builer2.storeUInt(20, 32)
        try builer2.storeRef(builer.cell())
        let builer3: CellBuilder = .init()
        try builer3.storeUInt(30, 32)
        let builer4: CellBuilder = .init()
        let builer5: CellBuilder = .init()
        try builer5.storeUInt(10, 32)
        try builer5.storeRef(builer2.cell())
        try builer5.storeRef(builer3.cell())
        try builer5.storeRef(builer4.cell())
        XCTAssertEqual(try builer5.cell().hash(), "e72f05f1692dbf5ef676ff754286a96d022ddc4583dfa9e92637b9aaa14b5a18")
        
        builer = CellBuilder.init()
        try builer.storeRef(CellBuilder().cell())
        try builer.storeRef(CellBuilder().cell())
        try builer.storeRef(CellBuilder().cell())
        try builer.storeRef(CellBuilder().cell())
        XCTAssertEqual(try builer.cell().hash(), "2a6109474805b984fe2125a54016161fc8c819fc010905d0c2e7067cf23f8980")
        
        builer = CellBuilder.init()
        try builer.storeRefs([CellBuilder().cell(), CellBuilder().cell()])
        XCTAssertEqual(try builer.cell().hash(), "f25bd30a545897dac24c1a3283e197788964eb16a46efcc509b2024c42c7f213")
        
        builer = CellBuilder.init()
        try builer.storeMaybeRef(CellBuilder().cell())
        XCTAssertEqual(try builer.cell().hash(), "9770d42f6d781e048a432b849b56d5329de4667b37cfb918429a23f90cb9884b")
        
        builer = CellBuilder.init()
        try builer.storeRef(CellBuilder().cell())
        try builer.storeRef(CellBuilder().cell())
        try builer.storeRef(CellBuilder().cell())
        try builer.storeRef(CellBuilder().cell())
        XCTAssertThrowsError(try builer.storeRef(CellBuilder().cell()))
    }
    
    func testAddress() async throws {
        let builer: CellBuilder = .init()
        try builer.storeAddress(.init(address: "0:93c5a151850b16de3cb2d87782674bc5efe23e6793d343aa096384aafd70812c"))
        XCTAssertEqual(try builer.cell().hash(), "2104ffbf59587630833903fd8c9bbb26a84d6c08ba9d55b74e55acff6b9b269e")
    }
    
    func testBytes() async throws {
        var builer: CellBuilder = .init()
        try builer.storeBytes(.init([0, 1, 7, 255]))
        XCTAssertEqual(try builer.cell().hash(), "049453e2b528b2f7750fd76eb015660b30eb294c69958a9aa3cf55a0db08718a")
        
        builer = CellBuilder.init()
        try builer.storeBytes(.init(repeating: 0, count: 127))
        XCTAssertEqual(try builer.cell().hash(), "0ebcf79f9d50dad8e07a7840a9928fe8c5dad0fb506155bcba8d2902a632f130")
        
        builer = CellBuilder.init()
        XCTAssertThrowsError(try builer.storeBytes(.init(repeating: 0, count: 128)))
    }
    
    func testString() async throws {
        var builer: CellBuilder = .init()
        try builer.storeString("Hello")
        XCTAssertEqual(try builer.cell().hash(), "bb1cba91be1e73057ed9eadc8484d50bdfa70e14bad6065b82a88fd68929d243")
        
        builer = CellBuilder.init()
        try builer.storeString("")
        XCTAssertEqual(try builer.cell().hash(), "96a296d224f285c67bee93c30f8a309157f0daa35dc5b87e410b78630a09cfc7")
        
        builer = CellBuilder.init()
        XCTAssertThrowsError(try builer.storeString(String(repeating: "1", count: 128)))
    }
    
    #warning("ADD TESTS FOR DICT")
}
