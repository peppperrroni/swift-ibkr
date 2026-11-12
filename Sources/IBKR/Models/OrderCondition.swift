import Foundation

/// One of an order's conditions (`Order.conditions`); the comment on each case is its wire type. `exchange` is
/// `ib_async`'s `exch`. The wire order of each element is in docs/protocol-178.md, «Order condition element».
public enum OrderCondition: Sendable, Equatable {
    /// How this condition joins the next one.
    public enum Conjunction: String, Sendable { case and = "a", or = "o" }

    case price(conID: Int, exchange: String, isMore: Bool, price: Decimal, triggerMethod: Int = 0,
               conjunction: Conjunction = .and)                                                              // 1
    case time(isMore: Bool, time: String, conjunction: Conjunction = .and)                                   // 3
    case margin(isMore: Bool, percent: Int, conjunction: Conjunction = .and)                                 // 4
    case execution(secType: String, exchange: String, symbol: String, conjunction: Conjunction = .and)       // 5
    case volume(conID: Int, exchange: String, isMore: Bool, volume: Int, conjunction: Conjunction = .and)    // 6
    case percentChange(conID: Int, exchange: String, isMore: Bool, changePercent: Decimal,
                       conjunction: Conjunction = .and)                                                      // 7
}
