import XCTest
import TonSdkSwift
import BigInt

final class BitsTests: XCTestCase {
    func testAugment() async throws {
        let bits: [Bit] = .init([1,0,1,1,1])
        XCTAssertEqual(bits.augment(), [Bit]([1,0,1,1,1,1,0,0]))
    }
    
    func testRollback() async throws {
        let bits: [Bit] = .init([1,0,1,1,1,1,0,0])
        XCTAssertEqual(try bits.rollback(), [Bit]([1,0,1,1,1]))
    }
    
    func testToBigInt() async throws {
        let bits: [Bit] = .init([1,1,0,0,0,0,1,0,1,0,0,1])
        XCTAssertEqual(bits.toBigInt(), -983)
    }
    
    func testToBigUInt() async throws {
        let bits: [Bit] = .init([1,1,0,0,0,0,1,0,1,0,0,1])
        XCTAssertEqual(bits.toBigUInt(), 3113)
    }
}


