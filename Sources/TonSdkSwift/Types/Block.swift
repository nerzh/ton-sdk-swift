//
//  File.swift
//
//
//  Created by Oleh Hudeichuk on 17.03.2024.
//

import Foundation
import BigInt

public protocol BlockStruct {
    associatedtype BlockStructData
    var data: BlockStructData { get }
    func cell() throws -> Cell
}

public struct TickTockOptions {
    public var tick: Bit
    public var tock: Bit
    
    public init(tick: Bit, tock: Bit) {
        self.tick = tick
        self.tock = tock
    }
}

public struct SimpleLibOptions {
    public var `public`: Bit
    public var root: Cell
    
    public init(publicValue: Bit, rootValue: Cell) {
        self.public = publicValue
        self.root = rootValue
    }
}

public struct TickTock: BlockStruct {
    public var data: TickTockOptions
    private var _cell: Cell
    
    public init(options: TickTockOptions) throws {
        self.data = options
        self._cell = try CellBuilder()
            .storeBit(options.tick)
            .storeBit(options.tock)
            .cell()
    }
    
    public func cell() throws -> Cell {
        _cell
    }
    
    public static func parse(_ cs: CellSlice) throws -> TickTock {
        let tick = try cs.loadBit()
        let tock = try cs.loadBit()
        let options = TickTockOptions(tick: tick, tock: tock)
        return try TickTock(options: options)
    }
}

public struct SimpleLib: BlockStruct {
    public let data: SimpleLibOptions
    private var _cell: Cell
    
    public init(options: SimpleLibOptions) throws {
        self.data = options
        self._cell = try CellBuilder()
            .storeBit(options.public)
            .storeRef(options.root)
            .cell()
    }
    
    public func cell() throws -> Cell {
        _cell
    }
    
    public static func parse(_ cs: CellSlice) throws -> SimpleLib {
        let publicValue = try cs.loadBit()
        let rootValue = try cs.loadRef()
        let options = SimpleLibOptions(publicValue: publicValue, rootValue: rootValue)
        return try SimpleLib(options: options)
    }
}


public struct StateInitOptions {
    public var splitDepth: BigUInt?
    public var special: Cell?
    public var code: Cell?
    public var data: Cell?
    public var library: HashmapE<[Bit], SimpleLib>?
    
    public init(splitDepth: BigUInt? = nil, special: Cell? = nil, code: Cell? = nil, data: Cell? = nil, library: HashmapE<[Bit], SimpleLib>? = nil) {
        self.splitDepth = splitDepth
        self.special = special
        self.code = code
        self.data = data
        self.library = library
    }
}


public struct StateInit: BlockStruct {
    public let data: StateInitOptions
    private var _cell: Cell
    
    public init(options: StateInitOptions) throws {
        self.data = options
        
        let builder = CellBuilder()
        
        if let splitDepth = data.splitDepth {
            try builder.storeUInt(splitDepth, 5)
        } else {
            try builder.storeBit(.b0)
        }
        
        /// special
        if let special = data.special {
            try builder.storeMaybeRef(special)
        } else {
            try builder.storeBit(.b0)
        }
        /// code
        try builder.storeMaybeRef(data.code)
        try builder.storeMaybeRef(data.data)
        try builder.storeDict(data.library)
        
        self._cell = try builder.cell()
    }
    
    public func cell() throws -> Cell {
        _cell
    }
    
    public static func parse(cs: CellSlice) throws -> StateInit {
        var options = StateInitOptions()
        
        if try cs.loadBit() != Bit(0) {
            options.splitDepth = try cs.loadBigUInt(size: 5)
        }
        if try cs.loadBit() != Bit(0) {
            options.special = try TickTock.parse(cs).cell()
        }
        if try cs.loadBit() != Bit(0) {
            options.code = try cs.loadRef()
        }
        if try cs.loadBit() != Bit(0) {
            options.data = try cs.loadRef()
        }
        options.library = try HashmapE.parse(
            keySize: 256,
            slice: cs,
            options: HashmapOptions<[Bit], SimpleLib>(
                deserializers: (
                    key: { $0 },
                    value: { v in
                        try SimpleLib.parse(v.parse())
                    }
                )
            )
        )
        
        return try StateInit(options: options)
    }
}

public enum CommonMsgInfo: BlockStruct {
    case intMsgInfo(IntMsgInfo)
    case extInMsgInfo(ExtInMsgInfo)
    
    public var data: CommonMsgInfo { self }
    
    public func cell() throws -> Cell {
        switch self {
        case let .intMsgInfo(intMsgInfo):
            try CellBuilder()
                .storeBits([.b0])                           // int_msg_info$0
                .storeBit(intMsgInfo.ihrDisabled ? .b1 : .b0)       // ihr_disabled:Bool
                .storeBit(intMsgInfo.bounce ? .b1 : .b0)                      // bounce:Bool
                .storeBit(intMsgInfo.bounced ? .b1 : .b0)            // bounced:Bool
                .storeAddress(intMsgInfo.src)     // src:MsgAddressInt
                .storeAddress(intMsgInfo.dest)                    // dest:MsgAddressInt
                .storeCoins(intMsgInfo.value)                     // value: -> grams:Grams
                .storeBit(.b0)                                // value: -> other:ExtraCurrencyCollection
                .storeCoins(intMsgInfo.ihrFee)   // ihr_fee:Grams
                .storeCoins(intMsgInfo.fwdFee)   // fwd_fee:Grams
                .storeUInt(BigUInt(intMsgInfo.createdLt), 64)        // created_lt:uint64
                .storeUInt(BigUInt(intMsgInfo.createdAt), 32)        // created_at:uint32
                .cell()
            
        case let .extInMsgInfo(extInMsgInfo):
            try CellBuilder()
                .storeBits([.b1, .b0])  // ext_in_msg_info$10
                .storeAddress(extInMsgInfo.src) // src:MsgAddress
                .storeAddress(extInMsgInfo.dest) // dest:MsgAddressExt
                .storeCoins(extInMsgInfo.importFee) // ihr_fee:Grams
                .cell()
        }
    }
    
    public struct IntMsgInfo {
        public var ihrDisabled: Bool
        public var bounce: Bool
        public var bounced: Bool
        public var src: Address?
        public var dest: Address
        public var value: Coins
        public var ihrFee: Coins
        public var fwdFee: Coins
        public var createdLt: UInt64
        public var createdAt: UInt32
        
        public init(
            ihrDisabled: Bool = true,
            bounce: Bool,
            bounced: Bool = false,
            src: Address? = nil,
            dest: Address,
            value: Coins,
            ihrFee: Coins = .init(0),
            fwdFee: Coins = .init(0),
            createdLt: UInt64 = 0,
            createdAt: UInt32 = 0
        ) {
            self.ihrDisabled = ihrDisabled
            self.bounce = bounce
            self.bounced = bounced
            self.src = src
            self.dest = dest
            self.value = value
            self.ihrFee = ihrFee
            self.fwdFee = fwdFee
            self.createdLt = createdLt
            self.createdAt = createdAt
        }
    }
    
    public struct ExtInMsgInfo {
        public var src: Address?
        public var dest: Address
        public var importFee: Coins
        
        public init(
            src: Address? = nil,
            dest: Address,
            importFee: Coins = .init(0)
        ) {
            self.src = src
            self.dest = dest
            self.importFee = importFee
        }
    }
    
    public static func parse(cs: CellSlice) throws -> CommonMsgInfo {
        let first = try cs.loadBit()
        
        if first == .b1 {
            let second = try cs.loadBit()
            if second == .b1 {
                throw ErrorTonSdkSwift("CommonMsgInfo: ext_out_msg_info unimplemented")
            } else {
                let src = try cs.loadAddress()
                guard let dest = try cs.loadAddress() else {
                    throw ErrorTonSdkSwift("Destination address is required")
                }
                let importFee = try cs.loadCoins()
                let extInMsgInfo = ExtInMsgInfo(src: src, dest: dest, importFee: importFee)
                return .extInMsgInfo(extInMsgInfo)
            }
        }
        
        if first == .b0 {
            var data = try IntMsgInfo(
                ihrDisabled: cs.loadBit() == .b1,
                bounce: cs.loadBit() == .b1,
                bounced: cs.loadBit() == .b1,
                src: cs.loadAddress(),
                dest: cs.loadAddress() ?? { throw ErrorTonSdkSwift("Destination address is required") }(),
                value: cs.loadCoins()
            )
            
            // TODO: support with ExtraCurrencyCollection
            try cs.skipBits(size: 1)
            
            data.ihrFee = try cs.loadCoins()
            data.fwdFee = try cs.loadCoins()
            data.createdLt = try UInt64(cs.loadBigUInt(size: 64))
            data.createdAt = try UInt32(cs.loadBigUInt(size: 32))
            
            return CommonMsgInfo.intMsgInfo(data)
        }
        
        throw ErrorTonSdkSwift("CommonMsgInfo: invalid tag")
    }
}

public struct MessageOptions {
    public var info: CommonMsgInfo
    public var stateInit: StateInit?
    public var body: Cell?
    
    public init(info: CommonMsgInfo, stateInit: StateInit? = nil, body: Cell? = nil) {
        self.info = info
        self.stateInit = stateInit
        self.body = body
    }
}

public struct Message: BlockStruct {
    public var data: MessageOptions
    private var _cell: Cell
    
    public init(options: MessageOptions) throws {
        self.data = options
        
        let b = CellBuilder()
        try b.storeSlice(self.data.info.cell().parse())
        
        // init:(Maybe (Either StateInit ^StateInit))
        if let initOptions = self.data.stateInit {
            try b.storeBits([.b1, .b0])
            try b.storeSlice(initOptions.cell().parse())
        } else {
            try b.storeBit(.b0)
        }
        
        // body:(Either X ^X)
        if let body = self.data.body {
            if (b.bits.count + body.bits.count + 1 <= 1023) &&
               (b.refs.count + body.refs.count <= 4) {
                try b.storeBit(.b0)
                try b.storeSlice(body.parse())
            } else {
                try b.storeBit(.b1)
                try b.storeRef(body)
            }
        } else {
            try b.storeBit(.b0)
        }
        
        self._cell = try b.cell()
    }
    
    public func cell() throws -> Cell {
        _cell
    }
    
    public static func parse(cs: CellSlice) throws -> Self {
        var data = try MessageOptions(info: CommonMsgInfo.parse(cs: cs))
        
        if try cs.loadBit() == .b1 {
            let initSlice = try cs.loadBit() == .b1 ? cs.loadRef().parse() : cs
            data.stateInit = try StateInit.parse(cs: initSlice)
        }
        
        if try cs.loadBit() == .b1 {
            data.body = try cs.loadRef()
        } else {
            data.body = try CellBuilder().storeSlice(cs).cell()
        }
        
        return try Message(options: data)
    }
}


public enum OutAction: BlockStruct {
    case actionSendMsg(ActionSendMsg)
    case actionSetCode(ActionSetCode)
    
    public var data: OutAction { self }
    
    public func cell() throws -> Cell {
        switch self {
        case let .actionSendMsg(actionSendMsg):
            try CellBuilder()
                .storeUInt(0x0ec3c86d, 32)
                .storeUInt(BigUInt(actionSendMsg.mode), 8)
                .storeRef(actionSendMsg.outMsg.cell())
                .cell()
            
        case let .actionSetCode(actionSetCode):
            try CellBuilder()
                .storeUInt(0xad4de08e, 32)
                .storeRef(actionSetCode.newCode)
                .cell()
        }
    }
    
    public static func parse(cs: CellSlice) throws -> OutAction {
        let tag = try cs.loadBigUInt(size: 32)
        
        switch tag {
        case 0x0ec3c86d: // action_send_msg
            let mode = try cs.loadBigUInt(size: 8)
            let outMsg = try Message.parse(cs: cs.loadRef().parse())
            return OutAction.actionSendMsg(ActionSendMsg(mode: UInt8(mode), outMsg: outMsg))
        case 0xad4de08e: // action_set_code
            return OutAction.actionSetCode(ActionSetCode(newCode: try cs.loadRef()))
        default:
            throw ErrorTonSdkSwift("Unexpected tag")
        }
    }
    
    public struct ActionSendMsg {
        public var mode: UInt8
        public var outMsg: Message
        
        public init(mode: UInt8, outMsg: Message) {
            self.mode = mode
            self.outMsg = outMsg
        }
    }

    public struct ActionSetCode {
        public var newCode: Cell // new_code:^Cell
        
        public init(newCode: Cell) {
            self.newCode = newCode
        }
    }
}

public struct OutListOptions {
    public var action: [OutAction]
    
    public init(action: [OutAction]) {
        self.action = action
    }
}

public struct OutList: BlockStruct {
    public var data: OutListOptions
    private var _cell: Cell
    
    public init(options: OutListOptions) throws {
        self.data = options
        
        let actions = options.action
        var current = try CellBuilder().cell()
        
        for action in actions {
            current = try CellBuilder()
                .storeRef(current)
                .storeSlice(action.cell().parse())
                .cell()
        }
        
        self._cell = current
    }
    
    public func cell() throws -> Cell {
        _cell
    }
}
