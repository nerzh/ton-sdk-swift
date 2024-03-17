//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 07.03.2024.
//

import Foundation

public extension TonMnemonic {
    
    enum WordsBitsOfEntropy: UInt {
        case w12 = 128
        case w15 = 160
        case w18 = 192
        case w21 = 224
        case w24 = 256
        
        public var count: UInt {
            switch self {
            case .w12: 12
            case .w15: 15
            case .w18: 18
            case .w21: 21
            case .w24: 24
            }
        }
        
        public static func get(by wordsCount: UInt) throws -> Self {
            switch wordsCount {
            case 12:
                return .w12
            case 15:
                return .w15
            case 18:
                return .w18
            case 21:
                return .w21
            case 24:
                return .w24
            default:
                throw ErrorTonSdkSwift("Unknown words size: \(wordsCount)")
            }
        }
    }
}
