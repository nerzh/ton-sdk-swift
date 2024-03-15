//
//  File 2.swift
//  
//
//  Created by Oleh Hudeichuk on 14.03.2024.
//

import Foundation
import SwiftNetLayer
import SwiftExtensionsPack

public final class ToncenterApiJsonRPCTarget: SNLTarget {
    
    public func send(boc: String) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue> {
        let json: String = ToncenterApi.getJsonBody(method: "sendBoc",
                                                    params: ["boc": boc])
        return try await makeExecutor(target: self,
                                      resource: resource,
                                      method: .post,
                                      requestParams: params,
                                      body: json.data(using: .utf8)
        ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue>.self)
    }
    
    public func getAddressInformation(
        address: String
    ) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<ToncenterApi.Account> {
        let json: String = ToncenterApi.getJsonBody(method: "getAddressInformation",
                                                    params: [
                                                        "address": address
                                                    ])
        return try await makeExecutor(target: self,
                                      resource: resource,
                                      method: .post,
                                      requestParams: params,
                                      body: json.data(using: .utf8)
        ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<ToncenterApi.Account>.self)
    }
    
    public func getTransactions(
        address: String,
        limit: UInt? = nil,
        lt: String? = nil,
        to_lt: String? = nil,
        hash: String? = nil,
        archival: Bool = true
    ) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<[ToncenterApi.TransactionModel]> {
        let json: String = ToncenterApi.getJsonBody(method: "getTransactions",
                                                    params: [
                                                        "address": address,
                                                        "limit": limit,
                                                        "lt": lt,
                                                        "hash": hash,
                                                        "to_lt": to_lt,
                                                        "archival": archival
                                                    ])
        return try await makeExecutor(target: self,
                                      resource: resource,
                                      method: .post,
                                      requestParams: params,
                                      body: json.data(using: .utf8)
        ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<[ToncenterApi.TransactionModel]>.self)
    }
    
    public func getExtendedAddressInformation(address: String) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue> {
        let json: String = ToncenterApi.getJsonBody(method: "getExtendedAddressInformation",
                                                    params: ["address": address])
        return try await makeExecutor(target: self,
                                      resource: resource,
                                      method: .post,
                                      requestParams: params,
                                      body: json.data(using: .utf8)
        ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue>.self)
    }
    
    public func getAddressBalance(address: String) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue> {
        let json: String = ToncenterApi.getJsonBody(method: "getAddressBalance",
                                                    params: ["address": address])
        return try await makeExecutor(target: self,
                                      resource: resource,
                                      method: .post,
                                      requestParams: params,
                                      body: json.data(using: .utf8)
        ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue>.self)
    }
    
    public func getAddressState(address: String) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue> {
        let json: String = ToncenterApi.getJsonBody(method: "getAddressState",
                                                    params: ["address": address])
        return try await makeExecutor(target: self,
                                      resource: resource,
                                      method: .post,
                                      requestParams: params,
                                      body: json.data(using: .utf8)
        ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue>.self)
    }
    
    public func getTokenData(address: String) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue> {
        let json: String = ToncenterApi.getJsonBody(method: "getTokenData",
                                                    params: ["address": address])
        return try await makeExecutor(target: self,
                                      resource: resource,
                                      method: .post,
                                      requestParams: params,
                                      body: json.data(using: .utf8)
        ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue>.self)
    }
    
    public func runGetMethod(address: String, method: String, stack: [[String]]) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue> {
        let json: String = ToncenterApi.getJsonBody(method: "runGetMethod",
                                                    params: ["address": address, "method": method, "stack": stack])
        return try await makeExecutor(target: self,
                                      resource: resource,
                                      method: .post,
                                      requestParams: params,
                                      body: json.data(using: .utf8)
        ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue>.self)
    }
    
    public func estimateFee(
        address: String,
        body: String,
        initCode: String,
        initData: String,
        ignoreChksig: Bool
    ) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue> {
        let json: String = ToncenterApi.getJsonBody(method: "estimateFee",
                                                    params: [
                                                        "address": address,
                                                        "body": body,
                                                        "init_code": initCode,
                                                        "init_data": initData,
                                                        "ignore_chksig": ignoreChksig
                                                    ])
        return try await makeExecutor(target: self,
                                      resource: resource,
                                      method: .post,
                                      requestParams: params,
                                      body: json.data(using: .utf8)
        ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue>.self)
    }
}

