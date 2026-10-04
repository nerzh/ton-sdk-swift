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
    
    public init(options: TickTockOptions) throws {
        self.data = options
    }
    
    public func cell() throws -> Cell {
        try CellBuilder().storeBit(data.tick).storeBit(data.tock).cell()
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

    public init(options: StateInitOptions) throws {
        self.data = options
        _ = try cell()
    }

    /// The legacy Cell adapter for special accepts exactly an inline TickTock.
    public func cell() throws -> Cell {
        if let library = data.library {
            guard library.keySize == 256 else {
                throw ErrorTonSdkSwift("StateInit library requires 256-bit keys")
            }
            for value in library.hashmap.values {
                guard value.type == .ordinary, value.bits.count == 1, value.refs.count == 1 else {
                    throw ErrorTonSdkSwift("StateInit library values must contain one public bit and one root reference")
                }
            }
        }
        let builder = CellBuilder()
        if let splitDepth = data.splitDepth {
            try builder.storeBit(.b1).storeUInt(splitDepth, 5)
        } else {
            try builder.storeBit(.b0)
        }
        if let special = data.special {
            guard special.type == .ordinary, special.bits.count == 2, special.refs.isEmpty else {
                throw ErrorTonSdkSwift("StateInit special must be an ordinary two-bit TickTock without references")
            }
            try builder.storeBit(.b1).storeBits(special.bits)
        } else {
            try builder.storeBit(.b0)
        }
        try builder.storeMaybeRef(data.code).storeMaybeRef(data.data).storeDict(data.library)
        return try builder.cell()
    }

    public static func parse(cs: CellSlice) throws -> StateInit {
        var options = StateInitOptions()
        if try cs.loadBit() == .b1 { options.splitDepth = try cs.loadBigUInt(size: 5) }
        if try cs.loadBit() == .b1 { options.special = try TickTock.parse(cs).cell() }
        options.code = try cs.loadMaybeRef()
        options.data = try cs.loadMaybeRef()
        options.library = try HashmapE.parse(keySize: 256, slice: cs, options:
            HashmapOptions<[Bit], SimpleLib>(serializers: (key: { $0 }, value: { try $0.cell() }),
                deserializers: (key: { $0 }, value: { try SimpleLib.parse($0.parse()) })))
        return try StateInit(options: options)
    }
}

extension StateInitOptions {
    /// Typed alternative to the Cell-based special field. No reference is emitted.
    public init(splitDepth: BigUInt? = nil, tickTock: TickTock, code: Cell? = nil,
                data: Cell? = nil, library: HashmapE<[Bit], SimpleLib>? = nil) throws {
        self.init(splitDepth: splitDepth, special: try tickTock.cell(), code: code, data: data, library: library)
    }
}

public enum CommonMsgInfo: BlockStruct {
    case intMsgInfo(IntMsgInfo)
    case extInMsgInfo(ExtInMsgInfo)
    
    public var data: CommonMsgInfo { self }
    
    public func cell() throws -> Cell {
        switch self {
        case let .intMsgInfo(intMsgInfo):
            return try CellBuilder()
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
            guard extInMsgInfo.src == nil else { throw ErrorTonSdkSwift("Inbound source must be external") }
            return try CellBuilder()
                .storeBits([.b1, .b0])  // ext_in_msg_info$10
                .storeAddress(extInMsgInfo.src) // src:MsgAddressExt (addr_none)
                .storeAddress(extInMsgInfo.dest) // dest:MsgAddressInt
                .storeCoins(extInMsgInfo.importFee) // import_fee:Grams
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
                guard src == nil else { throw ErrorTonSdkSwift("Inbound source must be external") }
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

            guard try cs.loadBit() == .b0 else {
                throw ErrorTonSdkSwift("Extra currencies are not supported by CommonMsgInfo")
            }

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

/// Placement preferences for the two Either fields of Message.
public struct MessagePlacement: Equatable {
    public var stateInitByReference: Bool
    public var bodyByReference: Bool

    public init(stateInitByReference: Bool, bodyByReference: Bool) {
        self.stateInitByReference = stateInitByReference
        self.bodyByReference = bodyByReference
    }
}

public struct Message: BlockStruct {
    public var data: MessageOptions
    /// A decoded layout is preferred when it still fits; edits may cause repacking.
    public private(set) var placement: MessagePlacement?
    private var parsedHeader: Cell?
    private var normalizedHeader: Cell?

    public init(options: MessageOptions) throws {
        self.data = options
        self.placement = nil
        self.parsedHeader = nil
        self.normalizedHeader = nil
        _ = try cell()
    }

    /// Serialization always reads current data, including mutable dictionaries.
    public func cell() throws -> Cell {
        let builder = CellBuilder()
        try store(to: builder)
        return try builder.cell()
    }

    public func cell(placement: MessagePlacement) throws -> Cell {
        let builder = CellBuilder()
        try store(to: builder, placement: placement)
        return try builder.cell()
    }

    /// Appends atomically, including existing builder bits/references in packing.
    /// Explicit placement must fit; a remembered decoded placement may fall back.
    @discardableResult
    public func store(to builder: CellBuilder, placement explicit: MessagePlacement? = nil) throws -> CellBuilder {
        let currentHeader = try data.info.cell()
        let header = currentHeader == normalizedHeader ? (parsedHeader ?? currentHeader) : currentHeader
        let state = try data.stateInit?.cell()
        let body = data.body
        var choices: [MessagePlacement] = []
        if let explicit { choices = [explicit] }
        else {
            if let placement { choices.append(placement) }
            for stateRef in [false, true] {
                for bodyRef in [false, true] {
                    choices.append(.init(stateInitByReference: stateRef, bodyByReference: bodyRef))
                }
            }
        }
        let limit = min(1023, builder.size)
        guard limit >= 0, builder.bits.count <= limit, builder.refs.count <= 4 else {
            throw ErrorTonSdkSwift("Message destination builder already exceeds cell capacity")
        }
        for choice in choices {
            if let body, body.type != .ordinary && !choice.bodyByReference { continue }
            let bitCount = header.bits.count + (state == nil ? 2 : 3)
                + (choice.stateInitByReference ? 0 : state?.bits.count ?? 0)
                + (choice.bodyByReference ? 0 : body?.bits.count ?? 0)
            let refCount = header.refs.count
                + (state == nil ? 0 : choice.stateInitByReference ? 1 : state!.refs.count)
                + (body == nil ? (choice.bodyByReference ? 1 : 0) : choice.bodyByReference ? 1 : body!.refs.count)
            guard bitCount <= limit - builder.bits.count, refCount <= 4 - builder.refs.count else { continue }
            let output = try CellBuilder().storeSlice(header.parse()).storeBit(state == nil ? .b0 : .b1)
            if let state {
                try output.storeBit(choice.stateInitByReference ? .b1 : .b0)
                if choice.stateInitByReference { try output.storeRef(state) }
                else { try output.storeSlice(state.parse()) }
            }
            try output.storeBit(choice.bodyByReference ? .b1 : .b0)
            if choice.bodyByReference { try output.storeRef(body ?? CellBuilder().cell()) }
            else if let body { try output.storeSlice(body.parse()) }
            return try builder.storeSlice(output.cell().parse())
        }
        throw ErrorTonSdkSwift("Message does not fit the destination builder with the requested placement")
    }

    public static func parse(cs: CellSlice) throws -> Self {
        let originalBits = cs.bits, originalRefs = cs.refs
        var data = try MessageOptions(info: CommonMsgInfo.parse(cs: cs))
        let header = try Cell(bits: Array(originalBits.prefix(originalBits.count - cs.bits.count)),
                              refs: Array(originalRefs.prefix(originalRefs.count - cs.refs.count)))
        var stateRef = false
        if try cs.loadBit() == .b1 {
            stateRef = try cs.loadBit() == .b1
            let stateSlice: CellSlice
            if stateRef {
                let stateCell = try cs.loadRef()
                guard stateCell.type == .ordinary else {
                    throw ErrorTonSdkSwift("Referenced StateInit must be an ordinary cell")
                }
                stateSlice = stateCell.parse()
            } else { stateSlice = cs }
            data.stateInit = try StateInit.parse(cs: stateSlice)
            if stateRef && (!stateSlice.bits.isEmpty || !stateSlice.refs.isEmpty) {
                throw ErrorTonSdkSwift("Referenced StateInit contains trailing data")
            }
        }
        let bodyRef = try cs.loadBit() == .b1
        if bodyRef { data.body = try cs.loadRef() }
        else { data.body = try CellBuilder().storeSlice(cs).cell() }
        // Avoid validating via automatic packing before the original layout is available.
        return try Self(parsed: data, placement: .init(stateInitByReference: stateRef, bodyByReference: bodyRef), header: header)
    }

    private init(parsed data: MessageOptions, placement: MessagePlacement, header: Cell) throws {
        self.data = data
        self.placement = placement
        self.parsedHeader = header
        self.normalizedHeader = try data.info.cell()
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
