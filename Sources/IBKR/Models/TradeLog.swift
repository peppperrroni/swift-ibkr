import Foundation

/// One step of an order's history in `OrderSnapshot.log` (`ib_async`'s `TradeLogEntry`): a status the client set
/// or IB reported, a modification, a fill, or an error IB sent for the order.
public struct TradeLogEntry: Sendable, Equatable, Encodable {
    /// When the client recorded it.
    public var time: Date
    /// The order's status after this step.
    public var status: OrderStatus
    /// `""` for a status change; `"Modify"`, `"Modified"`, `"Fill <shares>@<price>"`, or IB's error text.
    public var message: String
    /// IB's error code for an error entry; `nil` otherwise.
    public var errorCode: Int?

    /// An entry with these values; the message defaults to `""` and the error code to `nil`.
    public init(time: Date, status: OrderStatus, message: String = "", errorCode: Int? = nil) {
        self.time = time
        self.status = status
        self.message = message
        self.errorCode = errorCode
    }
}

/// What this client did to one of its orders, from `IBClient.orderEvents()` (`ib_async`'s `orderModifyEvent`
/// and `cancelOrderEvent`). The same snapshot also goes to `orders()`.
public enum OrderEvent: Sendable, Equatable, Encodable {
    /// `modifyOrder` re-sent a known, unfinished order; the snapshot's log ends with `"Modify"`.
    case modified(OrderSnapshot)
    /// `cancelOrder` asked IB to cancel a known, unfinished order; the snapshot is `.pendingCancel`, or `.cancelled`
    /// for a `.pendingSubmit` order sent with `transmit` off.
    case cancelRequested(OrderSnapshot)
}
