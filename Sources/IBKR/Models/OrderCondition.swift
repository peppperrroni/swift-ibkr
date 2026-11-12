import Foundation

/// One of an order's conditions (`Order.conditions`); the comment on each case is its wire type. `exchange` is
/// `ib_async`'s `exch`. The wire order of each element is in docs/protocol-178.md, «Order condition element».
public enum OrderCondition: Sendable, Equatable {
    /// How this condition joins the next one.
    public enum Conjunction: String, Sendable {
        /// Both this condition and the next must hold (wire `a`).
        case and = "a"
        /// Either this condition or the next must hold (wire `o`).
        case or = "o"
    }

    /// A price condition: the last price of contract `conID` is above (`isMore`) or below `price`.
    case price(conID: Int, exchange: String, isMore: Bool, price: Decimal, triggerMethod: Int = 0,
               conjunction: Conjunction = .and)                                                              // 1
    /// A time condition: the time is after (`isMore`) or before `time`, in IB's format.
    case time(isMore: Bool, time: String, conjunction: Conjunction = .and)                                   // 3
    /// A margin condition: the margin cushion is above (`isMore`) or below `percent`.
    case margin(isMore: Bool, percent: Int, conjunction: Conjunction = .and)                                 // 4
    /// An execution condition: an order for `symbol` of `secType` fills on `exchange`.
    case execution(secType: String, exchange: String, symbol: String, conjunction: Conjunction = .and)       // 5
    /// A volume condition: the volume of contract `conID` is above (`isMore`) or below `volume`.
    case volume(conID: Int, exchange: String, isMore: Bool, volume: Int, conjunction: Conjunction = .and)    // 6
    /// A percent-change condition: contract `conID` has moved by more (`isMore`) or less than `changePercent` percent.
    case percentChange(conID: Int, exchange: String, isMore: Bool, changePercent: Decimal,
                       conjunction: Conjunction = .and)                                                      // 7
}
