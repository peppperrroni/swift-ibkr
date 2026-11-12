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

    // The rest of the placeOrder rows, in row order (docs/protocol-178.md).
    public var openClose = "O"                                   // 24
    public var origin = 0                                        // 25
    public var blockOrder = false, sweepToFill = false           // 29-30
    public var displaySize = 0, triggerMethod = 0                // 31-32
    public var hidden = false                                    // 34
    public var discretionaryAmt: Decimal = 0                     // 36
    public var goodAfterTime = "", goodTillDate = ""             // 37-38
    public var faGroup = "", faMethod = "", faPercentage = ""    // 39-41
    public var modelCode = ""                                    // 42
    public var shortSaleSlot = 0, designatedLocation = "", exemptCode = -1   // 43-45
    public var rule80A = "", settlingFirm = ""                   // 47-48
    public var allOrNone = false                                 // 49
    public var minQty: Int?                                      // 50
    public var percentOffset: Decimal?                           // 51
    public var auctionStrategy = 0                               // 55
    public var startingPrice, stockRefPrice, delta, stockRangeLower, stockRangeUpper: Decimal?   // 56-60
    public var overridePercentageConstraints = false             // 61
    /// Sent only when `orderType` starts with `VOL`: IB back-fills it into live orders and then rejects their modification.
    public var volatility: Decimal?                              // 62
    public var volatilityType: Int?                              // 63
    public var continuousUpdate = false                          // 66
    public var referencePriceType: Int?                          // 67
    public var trailStopPrice, trailingPercent: Decimal?         // 68-69
    public var scaleInitLevelSize, scaleSubsLevelSize: Int?      // 70-71
    public var scaleTable = "", activeStartTime = "", activeStopTime = ""   // 73-75
    public var optOutSmartRouting = false                        // 77
    public var clearingAccount = "", clearingIntent = ""         // 78-79
    public var notHeld = false                                   // 80
    public var algoID = ""                                       // 83
    public var whatIf = false                                    // 84
    public var orderMiscOptions: [TagValue] = []                 // 85
    public var solicited = false, randomizeSize = false, randomizePrice = false   // 86-88
    public var adjustedOrderType = ""                            // 90
    public var triggerPrice, limitPriceOffset, adjustedStopPrice, adjustedStopLimitPrice, adjustedTrailingAmount: Decimal?  // 91-95
    public var adjustableTrailingUnit = 0                        // 96
    public var extOperator = ""                                  // 97
    public var softDollarTier = SoftDollarTier()                 // 98-99 name, value
    public var cashQty: Decimal?                                 // 100
    public var mifid2DecisionMaker = "", mifid2DecisionAlgo = "", mifid2ExecutionTrader = "", mifid2ExecutionAlgo = ""  // 101-104
    public var dontUseAutoPriceForHedge = false, isOmsContainer = false
    public var discretionaryUpToLimitPrice = false, usePriceMgmtAlgo = false   // 105-108
    public var duration: Int?, postToAts: Int?                   // 109-110
    public var autoCancelParent = false                          // 111
    public var advancedErrorOverride = "", manualOrderTime = ""  // 112-113

    // Decoded only, never sent: openOrder's, then completedOrder's.
    public var basisPoints: Decimal?, basisPointsType: Int?
    public var autoCancelDate = "", refFuturesConID: Int?, shareholder = ""
    public var imbalanceOnly = false, routeMarketableToBbo = false, parentPermID: Int?

    public init(action: OrderAction, quantity: Decimal, orderType: String,
                limitPrice: Decimal? = nil, auxPrice: Decimal? = nil, tif: String = "DAY") {
        self.action = action; totalQuantity = quantity; self.orderType = orderType
        self.limitPrice = limitPrice; self.auxPrice = auxPrice; self.tif = tif
        outsideRTH = false; parentID = 0; transmit = true
        ocaGroup = ""; ocaType = 0; orderRef = ""; account = ""
    }
}
