import XCTest
@testable import TonSdkSwift
import BigInt

final class BitsTests: XCTestCase {
    func testAugment() async throws {
        let bits: Bits = .init([1,0,1,1,1])
        XCTAssertEqual(bits.augment(), Bits([1,0,1,1,1,1,0,0]))
    }
    
    func testRollback() async throws {
        let bits: Bits = .init([1,0,1,1,1,1,0,0])
        XCTAssertEqual(try bits.rollback(), Bits([1,0,1,1,1]))
    }
    
    func testToBigInt() async throws {
        let bits: Bits = .init([1,1,0,0,0,0,1,0,1,0,0,1])
        XCTAssertEqual(bits.toBigInt(), -983)
    }
    
    func testToBigUInt() async throws {
        let bits: Bits = .init([1,1,0,0,0,0,1,0,1,0,0,1])
        XCTAssertEqual(bits.toBigUInt(), 3113)
    }
}
