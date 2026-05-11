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
    
    public func send(boc: String, debug: Bool = false) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue> {
        do {
            let json: String = ToncenterApi.getJsonBody(method: "sendBoc",
                                                        params: ["boc": boc])
            return try await makeExecutor(target: self,
                                          resource: resource,
                                          method: .post,
                                          requestParams: params,
                                          body: json.data(using: .utf8)
            ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue>.self, debug: debug)
        } catch {
            throw ErrorTonSdkSwift(error)
        }
    }
    
    public func getAddressInformation(
        address: String,
        debug: Bool = false
    ) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<ToncenterApi.Account> {
        do {
            let json: String = ToncenterApi.getJsonBody(method: "getAddressInformation",
                                                        params: [
                                                            "address": address
                                                        ])
            return try await makeExecutor(target: self,
                                          resource: resource,
                                          method: .post,
                                          requestParams: params,
                                          body: json.data(using: .utf8)
            ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<ToncenterApi.Account>.self, debug: debug)
        } catch {
            throw ErrorTonSdkSwift(error)
        }
    }
    
    public func getTransactions(
        address: String,
        limit: UInt? = nil,
        lt: String? = nil,
        to_lt: String? = nil,
        hash: String? = nil,
        archival: Bool = true,
        debug: Bool = false
    ) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<[ToncenterApi.TransactionModel]> {
        do {
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
            ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<[ToncenterApi.TransactionModel]>.self, debug: debug)
        } catch {
            throw ErrorTonSdkSwift(error)
        }
    }
    
    public func getExtendedAddressInformation(address: String, debug: Bool = false) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue> {
        do {
            let json: String = ToncenterApi.getJsonBody(method: "getExtendedAddressInformation",
                                                        params: ["address": address])
            return try await makeExecutor(target: self,
                                          resource: resource,
                                          method: .post,
                                          requestParams: params,
                                          body: json.data(using: .utf8)
            ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue>.self, debug: debug)
        } catch {
            throw ErrorTonSdkSwift(error)
        }
    }
    
    public func getAddressBalance(address: String, debug: Bool = false) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue> {
        do {
            let json: String = ToncenterApi.getJsonBody(method: "getAddressBalance",
                                                        params: ["address": address])
            return try await makeExecutor(target: self,
                                          resource: resource,
                                          method: .post,
                                          requestParams: params,
                                          body: json.data(using: .utf8)
            ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue>.self, debug: debug)
        } catch {
            throw ErrorTonSdkSwift(error)
        }
    }
    
    public func getAddressState(address: String, debug: Bool = false) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue> {
        do {
            let json: String = ToncenterApi.getJsonBody(method: "getAddressState",
                                                        params: ["address": address])
            return try await makeExecutor(target: self,
                                          resource: resource,
                                          method: .post,
                                          requestParams: params,
                                          body: json.data(using: .utf8)
            ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue>.self, debug: debug)
        } catch {
            throw ErrorTonSdkSwift(error)
        }
    }
    
    public func getTokenData(address: String, debug: Bool = false) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue> {
        do {
            let json: String = ToncenterApi.getJsonBody(method: "getTokenData",
                                                        params: ["address": address])
            return try await makeExecutor(target: self,
                                          resource: resource,
                                          method: .post,
                                          requestParams: params,
                                          body: json.data(using: .utf8)
            ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue>.self, debug: debug)
        } catch {
            throw ErrorTonSdkSwift(error)
        }
    }
    
    public func runGetMethod(
        address: String, method: String, stack: [[String]], debug: Bool = false
    ) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue> {
        do {
            let json: String = ToncenterApi.getJsonBody(method: "runGetMethod",
                                                        params: ["address": address, "method": method, "stack": stack])
            return try await makeExecutor(target: self,
                                          resource: resource,
                                          method: .post,
                                          requestParams: params,
                                          body: json.data(using: .utf8)
            ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue>.self, debug: debug)
        } catch {
            throw ErrorTonSdkSwift(error)
        }
    }
    
    public func estimateFee(
        address: String,
        body: String,
        initCode: String,
        initData: String,
        ignoreChksig: Bool,
        debug: Bool = false
    ) async throws -> ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue> {
        do {
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
            ).execute(model: ToncenterApi.ToncenterApiJsonrpcResponse<AnyValue>.self, debug: debug)
        } catch {
            throw ErrorTonSdkSwift(error)
        }
    }
}

