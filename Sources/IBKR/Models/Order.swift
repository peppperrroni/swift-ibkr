import Foundation

public enum OrderAction: String, Sendable { case buy = "BUY", sell = "SELL", shortSell = "SSHORT" }

public struct Order: Sendable, Equatable {
    public var action: OrderAction
    public var totalQuantity: Decimal
    public var orderType: String
    public var limitPrice: Decimal?
    public var auxPrice: Decimal?
    public var tif: String
    public var outsideRTH: Bool
    public var parentID: Int
    public var transmit: Bool
    public var ocaGroup: String
    public var ocaType: Int
    public var orderRef: String
    public var account: String

    public init(action: OrderAction, quantity: Decimal, orderType: String,
                limitPrice: Decimal? = nil, auxPrice: Decimal? = nil, tif: String = "DAY") {
        self.action = action; totalQuantity = quantity; self.orderType = orderType
        self.limitPrice = limitPrice; self.auxPrice = auxPrice; self.tif = tif
        outsideRTH = false; parentID = 0; transmit = true
        ocaGroup = ""; ocaType = 0; orderRef = ""; account = ""
    }
}
