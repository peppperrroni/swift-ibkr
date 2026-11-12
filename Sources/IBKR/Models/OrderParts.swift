import Foundation

/// One `tag=value` pair of an order's options (`orderMiscOptions`).
public struct TagValue: Sendable, Equatable, Hashable {
    /// The option's name.
    public var tag: String
    /// The option's value.
    public var value: String

    /// A pair of these.
    public init(tag: String, value: String) { self.tag = tag; self.value = value }
}

/// An order's soft-dollar tier; `value` is `ib_async`'s `val`.
public struct SoftDollarTier: Sendable, Equatable {
    /// The tier's name.
    public var name: String
    /// The tier's value.
    public var value: String
    /// The tier's name as IB displays it.
    public var displayName: String

    /// A tier of these; all empty by default, which is no tier.
    public init(name: String = "", value: String = "", displayName: String = "") {
        self.name = name; self.value = value; self.displayName = displayName
    }
}

/// One leg of a `BAG` contract (`Contract.comboLegs`).
public struct ComboLeg: Sendable, Equatable, Hashable {
    /// The leg contract's id.
    public var conID: Int
    /// The leg's share of the combo.
    public var ratio: Int
    /// Whether the combo buys or sells this leg.
    public var action: OrderAction
    /// The exchange the leg routes to.
    public var exchange: String
    /// `0` same as the parent, `1` open, `2` close, `3` unknown (`ib_async`'s `ComboLeg.openClose`).
    public var openClose: Int
    /// ib_async's `ComboLeg.shortSaleSlot`, sent in placeOrder with the leg.
    public var shortSaleSlot: Int
    /// ib_async's `ComboLeg.designatedLocation`, sent in placeOrder with the leg.
    public var designatedLocation: String
    /// ib_async's `ComboLeg.exemptCode`, sent in placeOrder with the leg; `-1` is the default.
    public var exemptCode: Int

    /// A leg of these values.
    public init(conID: Int, ratio: Int, action: OrderAction, exchange: String, openClose: Int = 0,
                shortSaleSlot: Int = 0, designatedLocation: String = "", exemptCode: Int = -1) {
        self.conID = conID; self.ratio = ratio; self.action = action; self.exchange = exchange
        self.openClose = openClose; self.shortSaleSlot = shortSaleSlot
        self.designatedLocation = designatedLocation; self.exemptCode = exemptCode
    }
}

/// A `BAG` order's price for the leg at the same position (`Order.orderComboLegs`).
public struct OrderComboLeg: Sendable, Equatable {
    /// The leg's price; `nil` goes out as `""`.
    public var price: Decimal?

    /// A price for one leg.
    public init(price: Decimal?) { self.price = price }
}

/// A `PEG BEST` order's `competeAgainstBestOffset`; `upToMid` is the wire's `Infinite`.
public enum CompeteOffset: Sendable, Equatable {
    /// A fixed offset from the best price.
    case offset(Decimal)
    /// Up to the midpoint (wire `Infinite`).
    case upToMid
}

/// The hedge contract of a delta-neutral order (`Contract.deltaNeutralContract`).
public struct DeltaNeutralContract: Sendable, Equatable, Hashable {
    /// The hedge contract's id.
    public var conID: Int
    /// The hedge contract's delta.
    public var delta: Decimal
    /// The hedge contract's price.
    public var price: Decimal

    /// A hedge contract of these values.
    public init(conID: Int, delta: Decimal, price: Decimal) {
        self.conID = conID; self.delta = delta; self.price = price
    }
}
