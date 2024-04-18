//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 14.03.2024.
//

import Foundation
import SwiftNetLayer
import SwiftExtensionsPack

open class ToncenterApi: SNLResource {
    
    public init(apiKey: String, domain: String = "toncenter.com/api/v2", `protocol`: SNLProtocolType, requestLimit: UInt = 5, timeRangeLimitSecond: UInt = 1) {
        super.init(protocol: `protocol`,
                   domain: domain,
                   defaultHeaders: [
                        "Content-Type": "application/json",
                        "X-API-Key": apiKey
                   ],
                   requestPerSecondOptions: .init(.init(requestLimit: requestLimit, timeRangeLimitSecond: timeRangeLimitSecond))
        )
    }
    
    public init(url: String, apiKey: String = "", requestLimit: UInt = 5, timeRangeLimitSecond: UInt = 1) throws {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stringProtocol = url.regexp(#"^(http.)"#)[1] else {
            throw ErrorTonSdkSwift("URL should have protocol http or https")
        }
        guard let domain = url.regexp(#"\:\/\/([\s\S]+)$"#)[1] else {
            throw ErrorTonSdkSwift("URL should have domain. Example: https://example.com")
        }
        let `protocol`: SNLProtocolType = stringProtocol == "https" ? .https : .http
        
        super.init(protocol: `protocol`,
                   domain: domain,
                   defaultHeaders: [
                        "Content-Type": "application/json",
                        "X-API-Key": apiKey
                   ],
                   requestPerSecondOptions: .init(.init(requestLimit: requestLimit, timeRangeLimitSecond: timeRangeLimitSecond))
        )
    }
}



public extension ToncenterApi {
    
    func jsonRpc() -> ToncenterApiJsonRPCTarget {
        ToncenterApiJsonRPCTarget(resource: self, path: "/jsonRPC")
    }
}


public extension ToncenterApi {
    
    class func getJsonBody(id: Int = 1, jsonrpc: String = "2.0", method: String, params: [String: Any?]) -> String {
        let model: ToncenterApi.ToncenterApiRawRequest<AnyValue> = .init(jsonrpc: jsonrpc,
                                                                         id: id,
                                                                         method: method,
                                                                         params: (params.compactMapValues { $0 }).toAnyValue())
        let jsonData = try! JSONEncoder().encode(model)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        return jsonString
    }
}

