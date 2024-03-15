//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 14.03.2024.
//

import Foundation
import BigInt
import SwiftExtensionsPack


public extension ToncenterApi {
    
    //MARK: resp req wrappers
    struct ToncenterApiRawRequest<T: Encodable>: Encodable {
        public var jsonrpc: String
        public var id: Int
        public var method: String
        public var params: T
    }
    
    /// "{\"ok\":true,\"result\":{\"@type\":\"ok\",\"@extra\":\"1677190769.4780862:4:0.47718457038890816\"},\"jsonrpc\":\"2.0\",\"id\":\"1\"}"
    struct ToncenterApiJsonrpcResponse<T: Decodable>: Decodable {
        public var ok: Bool
        public var result: T?
        public var jsonrpc: String?
        public var id: String?
        public var error: String?
        public var code: Int?
    }
    
    struct TransactionModel: Codable {
        public var transaction_id: TransactionId
        public var utime: Int
        public var fee: String
        public var in_msg: InMessage?
        public var out_msgs: [OutMessage]
        
        public var isIncomingTransaction: Bool {
            out_msgs.isEmpty
        }

        public struct TransactionId: Codable {
            public var hash: String
            public var lt: String
        }
        
        public struct MsgData: Codable {
            public var type: String
            public var text: String?
            public var body: String?
            
            public enum CodingKeys: String, CodingKey {
                case type = "@type"
                case text
                case body
            }
        }
        
        public struct InMessage: Codable {
            public var source: String
            public var value: String
            public var message: String
            public var msg_data: MsgData
        }

        public struct OutMessage: Codable {
            public var destination: String
            public var value: String
            public var message: String
            public var msg_data: MsgData
        }
    }
    
    struct Account: Codable {
        public var code: String
        public var data: String
        public var state: String
        public var balance: AnyValue
    }
}

