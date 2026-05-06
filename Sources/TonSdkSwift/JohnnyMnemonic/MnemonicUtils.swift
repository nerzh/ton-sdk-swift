//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 07.03.2024.
//

import Foundation

extension TonMnemonic {
    
    public enum WordsBitsOfEntropy: UInt {
        case w12 = 12
        case w15 = 15
        case w18 = 18
        case w21 = 21
        case w24 = 24
        
        public var count: UInt {
            switch self {
            case .w12: 128
            case .w15: 160
            case .w18: 192
            case .w21: 224
            case .w24: 256
            }
        }
    }
}
