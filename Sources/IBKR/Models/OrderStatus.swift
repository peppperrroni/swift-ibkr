import Foundation

/// Open set: IB adds statuses, unknown ones are kept as they came.
public struct OrderStatus: RawRepresentable, Sendable, Hashable, Encodable {
    /// IB's status text, as it came.
    public var rawValue: String
    /// The status with IB's text `rawValue`, known or not.
    public init(rawValue: String) { self.rawValue = rawValue }

    /// IB's `ApiPending` status.
    public static let apiPending = OrderStatus(rawValue: "ApiPending")
    /// IB's `PendingSubmit` status.
    public static let pendingSubmit = OrderStatus(rawValue: "PendingSubmit")
    /// IB's `PendingCancel` status.
    public static let pendingCancel = OrderStatus(rawValue: "PendingCancel")
    /// IB's `PreSubmitted` status.
    public static let preSubmitted = OrderStatus(rawValue: "PreSubmitted")
    /// IB's `Submitted` status.
    public static let submitted = OrderStatus(rawValue: "Submitted")
    /// IB's `ApiCancelled` status.
    public static let apiCancelled = OrderStatus(rawValue: "ApiCancelled")
    /// IB's `Cancelled` status.
    public static let cancelled = OrderStatus(rawValue: "Cancelled")
    /// IB's `Filled` status.
    public static let filled = OrderStatus(rawValue: "Filled")
    /// IB's `Inactive` status.
    public static let inactive = OrderStatus(rawValue: "Inactive")

    /// Whether the order is over: cancelled (by IB or the API), filled or inactive.
    public var isFinal: Bool { self == .cancelled || self == .apiCancelled || self == .filled || self == .inactive }
}

/// IB's orderStatus message (in 3): where an order stands and what has filled.
public struct OrderStatusMessage: Sendable, Equatable, Encodable {
    /// The order's id.
    public var orderID: Int
    /// The order's status.
    public var status: OrderStatus
    /// Shares or contracts filled so far.
    public var filled: Decimal
    /// Shares or contracts still open.
    public var remaining: Decimal
    /// The average price of the fills so far; `nil` before the first.
    public var averageFillPrice: Decimal?
    /// IB's permanent id for the order.
    public var permID: Int
    /// The parent order's id, `0` for none.
    public var parentID: Int
    /// The price of the latest fill; `nil` before the first.
    public var lastFillPrice: Decimal?
    /// The client id that placed the order.
    public var clientID: Int
    /// Why IB holds the order, such as `locate`; empty when it does not.
    public var whyHeld: String
    /// ib_async's `mktCapPrice`; `nil` when IB sends none.
    public var marketCapPrice: Decimal?

    /// A message with these values; the prices default to `nil`.
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
