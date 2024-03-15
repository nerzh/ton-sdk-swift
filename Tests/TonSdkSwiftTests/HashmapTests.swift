import XCTest
import TonSdkSwift
import BigInt

final class HashmapTests: XCTestCase {
    func testDict() async throws {
        let options: HashmapOptions<BigUInt, BigUInt> = .init(serializers: (
            key: { k in
                try CellBuilder().storeUInt(k, 16).bits
            },
            value: { v in
                try CellBuilder().storeUInt(v, 16).cell()
            }
        ))
        let dict = try HashmapE(keySize: 16, options: options)
        try dict.set(17, 289)
        try dict.set(239, 57121)
        try dict.set(32781, 169)
        
        XCTAssertEqual(try dict.cell().hash(), "863cdf82df752f65f8386646b1e92770fd3545d726762cae82e3b9a0100c501e")
    }
}


