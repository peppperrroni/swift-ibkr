import Foundation

/// One `tag=value` pair of an order's options (`orderMiscOptions`).
public struct TagValue: Sendable, Equatable, Hashable {
    public var tag: String
    public var value: String

    public init(tag: String, value: String) { self.tag = tag; self.value = value }
}

/// `value` is `ib_async`'s `val`.
public struct SoftDollarTier: Sendable, Equatable {
    public var name, value, displayName: String

    public init(name: String = "", value: String = "", displayName: String = "") {
        self.name = name; self.value = value; self.displayName = displayName
    }
}

/// One leg of a `BAG` contract (`Contract.comboLegs`).
public struct ComboLeg: Sendable, Equatable, Hashable {
    public var conID: Int
    public var ratio: Int
    public var action: OrderAction
    public var exchange: String
    public var openClose: Int
    public var shortSaleSlot: Int
    public var designatedLocation: String
    public var exemptCode: Int

    public init(conID: Int, ratio: Int, action: OrderAction, exchange: String, openClose: Int = 0,
                shortSaleSlot: Int = 0, designatedLocation: String = "", exemptCode: Int = -1) {
        self.conID = conID; self.ratio = ratio; self.action = action; self.exchange = exchange
        self.openClose = openClose; self.shortSaleSlot = shortSaleSlot
        self.designatedLocation = designatedLocation; self.exemptCode = exemptCode
    }
}

/// A `BAG` order's price for the leg at the same position (`Order.orderComboLegs`).
public struct OrderComboLeg: Sendable, Equatable {
    public var price: Decimal?

    public init(price: Decimal?) { self.price = price }
}

/// A `PEG BEST` order's `competeAgainstBestOffset`; `upToMid` is the wire's `Infinite`.
public enum CompeteOffset: Sendable, Equatable { case offset(Decimal), upToMid }

/// The hedge contract of a delta-neutral order (`Contract.deltaNeutralContract`).
public struct DeltaNeutralContract: Sendable, Equatable, Hashable {
    public var conID: Int
    public var delta: Decimal
    public var price: Decimal

    public init(conID: Int, delta: Decimal, price: Decimal) { self.conID = conID; self.delta = delta; self.price = price }
}
