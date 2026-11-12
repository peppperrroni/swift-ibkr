import Foundation

/// Open set: IB adds statuses, unknown ones are kept as they came.
public struct OrderStatus: RawRepresentable, Sendable, Hashable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let apiPending = OrderStatus(rawValue: "ApiPending")
    public static let pendingSubmit = OrderStatus(rawValue: "PendingSubmit")
    public static let pendingCancel = OrderStatus(rawValue: "PendingCancel")
    public static let preSubmitted = OrderStatus(rawValue: "PreSubmitted")
    public static let submitted = OrderStatus(rawValue: "Submitted")
    public static let apiCancelled = OrderStatus(rawValue: "ApiCancelled")
    public static let cancelled = OrderStatus(rawValue: "Cancelled")
    public static let filled = OrderStatus(rawValue: "Filled")
    public static let inactive = OrderStatus(rawValue: "Inactive")

    public var isFinal: Bool { self == .cancelled || self == .apiCancelled || self == .filled || self == .inactive }
}

public struct OrderStatusMessage: Sendable, Equatable {
    public var orderID: Int
    public var status: OrderStatus
    public var filled: Decimal
    public var remaining: Decimal
    public var averageFillPrice: Decimal?
    public var permID: Int
    public var parentID: Int
    public var lastFillPrice: Decimal?
    public var clientID: Int
    public var whyHeld: String
    public var marketCapPrice: Decimal?

    public init(
        orderID: Int,
        status: OrderStatus,
        filled: Decimal,
        remaining: Decimal,
        averageFillPrice: Decimal? = nil,
        permID: Int,
        parentID: Int,
        lastFillPrice: Decimal? = nil,
        clientID: Int,
        whyHeld: String,
        marketCapPrice: Decimal? = nil
    ) {
        self.orderID = orderID
        self.status = status
        self.filled = filled
        self.remaining = remaining
        self.averageFillPrice = averageFillPrice
        self.permID = permID
        self.parentID = parentID
        self.lastFillPrice = lastFillPrice
        self.clientID = clientID
        self.whyHeld = whyHeld
        self.marketCapPrice = marketCapPrice
    }
}
