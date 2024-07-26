# TON-SDK-SWIFT

Swift SDK for interaction with TON (The Open Network) blockchain

| OS | Result |
| ----------- | ----------- |
| MacOS | ✅ |
| Linux | ✅ |
| iOS | ✅ |
| Windows | ✅ |

## Installation

Install ton-sdk-swift:

- `.package(url: "https://github.com/nerzh/ton-sdk-swift", .upToNextMajor(from: "1.0.0")),`

# ⚠️ TON-SDK-SWIFT-SMC
###### ⚠️ You might also find it beneficial to make use of the [TON-SDK-SWIFT-SMC](https://github.com/nerzh/ton-sdk-swift-smc) package, which implements basic wrappers for TON smart contracts (please be aware that ton-sdk-ruby-smc is distributed under the LGPL-3.0 license).

# Example

```swift
import XCTest
import TonSdkSwift

final class ExampleTests: XCTestCase {
    
    func testExample() async throws {
        /// Init address from string
        let addr = try Address(address: "EQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqB2N")
        /// Init and fill the builder
        let b = CellBuilder()
        try b.storeUInt(200, 30)
        try b.storeAddress(addr)
        try b.storeCoins(Coins(0.0001))
        
        /// End builder and serialize to boc
        let bytes = try Boc.serialize(root: [b.cell()])
        let base64 = bytes.toBase64()
        
        print("boc in base64 format:", base64)
        
        /// Deserialize base64 boc
        let cell = try Boc.deserialize(data: base64.base64ToBytes()).first
        
        /// Parse cell into slice
        let cs = cell?.parse()
        
        /// Load and print values
        XCTAssertEqual(try cs?.loadBigUInt(size: 30), 200)
        XCTAssertEqual(try cs?.loadAddress()?.toString(), "UQCD39VS5jcptHL8vMjEXrzGaRcCVYto7HUn4bpAOg8xqEBI")
        XCTAssertEqual(try cs?.loadCoins(), Coins(0.0001))
    }
}
```

## License

MIT

## Mentions

I would like to thank [cryshado](https://github.com/cryshado) for their valuable advice and help in developing this library.
