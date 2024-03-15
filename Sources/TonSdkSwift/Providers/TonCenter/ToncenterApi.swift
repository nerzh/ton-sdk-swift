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
    
    public init(apiKey: String, requestPerSecond: UInt = 5, domain: String = "toncenter.com/api/v2", `protocol`: SNLProtocolType) {
        super.init(protocol: `protocol`,
                   domain: domain,
                   defaultHeaders: [
                        "Content-Type": "application/json",
                        "X-API-Key": apiKey
                   ],
                   requestPerSecondOptions: .init(.init(requestPerSecond: requestPerSecond))
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

