import Foundation
import Testing
@testable import IBKR

@Test func factoriesSetTypeAndPrices() {
    #expect(Order.limit(.buy, quantity: 100, price: 180) == Order(action: .buy, quantity: 100, orderType: "LMT", limitPrice: 180))
    let m = Order.market(.buy, quantity: 1)
    #expect(m.orderType == "MKT" && m.limitPrice == nil && m.auxPrice == nil)
    let s = Order.stop(.sell, quantity: 100, stopPrice: 175)
    #expect(s.orderType == "STP" && s.auxPrice == 175 && s.limitPrice == nil)
    let sl = Order.stopLimit(.buy, quantity: 1, limitPrice: 181, stopPrice: 180)
    #expect(sl.orderType == "STP LMT" && sl.limitPrice == 181 && sl.auxPrice == 180)
}

@Test func bracketReversesTheChildren() {
    let b = Order.bracket(.buy, quantity: 100, limitPrice: 180, takeProfitPrice: 190, stopLossPrice: 175)
    #expect(b.parent.orderType == "LMT" && b.parent.action == .buy && b.parent.limitPrice == 180 && !b.parent.transmit)
    #expect(b.takeProfit.orderType == "LMT" && b.takeProfit.action == .sell && b.takeProfit.limitPrice == 190 && !b.takeProfit.transmit)
    #expect(b.stopLoss.orderType == "STP" && b.stopLoss.action == .sell && b.stopLoss.auxPrice == 175 && b.stopLoss.transmit)
    let s = Order.bracket(.sell, quantity: 100, limitPrice: 180, takeProfitPrice: 170, stopLossPrice: 185)
    #expect(s.takeProfit.action == .buy && s.stopLoss.action == .buy)
}

@Test func oneCancelsAllSetsGroupAndType() {
    let a = Order.limit(.buy, quantity: 1, price: 1), b = Order.stop(.sell, quantity: 2, stopPrice: 3)
    let out = Order.oneCancelsAll([a, b], group: "g", type: 1)
    var ea = a, eb = b
    ea.ocaGroup = "g"; ea.ocaType = 1; eb.ocaGroup = "g"; eb.ocaType = 1
    #expect(out == [ea, eb])
}
