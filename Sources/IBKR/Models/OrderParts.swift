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
