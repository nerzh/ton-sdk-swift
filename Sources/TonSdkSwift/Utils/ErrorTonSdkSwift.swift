//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 29.01.2024.
//

import Foundation
import SwiftExtensionsPack

public struct ErrorTonSdkSwift: ErrorCommon, Encodable {
    public var title: String = "\(Self.self)"
    public var reason: String = ""
    public init() {}
}
