import Foundation

/// A parent with its take-profit and stop-loss; place it with `IBClient.placeBracket`.
public struct BracketOrder: Sendable, Equatable {
    public var parent, takeProfit, stopLoss: Order
    public init(parent: Order, takeProfit: Order, stopLoss: Order) {
        self.parent = parent; self.takeProfit = takeProfit; self.stopLoss = stopLoss
    }
}

extension Order {
    public static func market(_ action: OrderAction, quantity: Decimal) -> Order {
        Order(action: action, quantity: quantity, orderType: "MKT")
    }

    public static func limit(_ action: OrderAction, quantity: Decimal, price: Decimal) -> Order {
        Order(action: action, quantity: quantity, orderType: "LMT", limitPrice: price)
    }

    public static func stop(_ action: OrderAction, quantity: Decimal, stopPrice: Decimal) -> Order {
        Order(action: action, quantity: quantity, orderType: "STP", auxPrice: stopPrice)
    }

    public static func stopLimit(_ action: OrderAction, quantity: Decimal, limitPrice: Decimal, stopPrice: Decimal) -> Order {
        Order(action: action, quantity: quantity, orderType: "STP LMT", limitPrice: limitPrice, auxPrice: stopPrice)
    }

    /// A limit entry with a take-profit limit and a stop-loss on the reverse side. Only the stop-loss transmits;
    /// `placeBracket` links the children to the parent.
    public static func bracket(_ action: OrderAction, quantity: Decimal, limitPrice: Decimal,
                               takeProfitPrice: Decimal, stopLossPrice: Decimal) -> BracketOrder {
        let reverse: OrderAction = action == .buy ? .sell : .buy
        var parent = limit(action, quantity: quantity, price: limitPrice)
        var profit = limit(reverse, quantity: quantity, price: takeProfitPrice)
        let stopLoss = stop(reverse, quantity: quantity, stopPrice: stopLossPrice)
        parent.transmit = false; profit.transmit = false
        return BracketOrder(parent: parent, takeProfit: profit, stopLoss: stopLoss)
    }

    /// The orders with `ocaGroup` and `ocaType` set: IB cancels (or reduces) the rest when one fills.
    public static func oneCancelsAll(_ orders: [Order], group: String, type: Int) -> [Order] {
        orders.map { var o = $0; o.ocaGroup = group; o.ocaType = type; return o }
    }
}
