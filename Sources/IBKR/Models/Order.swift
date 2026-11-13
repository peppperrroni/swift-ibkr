import Foundation

/// What an option exercise request does (`exerciseOptions`'s action): IB's wire value.
public enum ExerciseAction: Int, Sendable, Encodable {
    /// Exercise the option (wire `1`).
    case exercise = 1
    /// Let the option lapse (wire `2`).
    case lapse = 2
}

/// An order's side, as IB's wire text.
public enum OrderAction: String, Sendable, Encodable {
    /// Buy (wire `BUY`).
    case buy = "BUY"
    /// Sell (wire `SELL`).
    case sell = "SELL"
    /// Sell short (wire `SSHORT`).
    case shortSell = "SSHORT"
}

/// An order as placeOrder (out 3) sends it and openOrder (in 5) / completedOrder (in 101) decode it. Each property
/// is the `ib_async` `Order` attribute of the same name; prices are `Decimal?`, and `nil` goes out as `""`.
public struct Order: Sendable, Equatable, Encodable {
    /// `BUY`, `SELL` or `SSHORT` (placeOrder row 16).
    public var action: OrderAction
    /// Shares or contracts (row 17).
    public var totalQuantity: Decimal
    /// IB's order type text, such as `LMT` or `MKT` (row 18); a string, not an enum, so new types need no release.
    public var orderType: String
    /// The limit price, `lmtPrice` in `ib_async` (row 19).
    public var limitPrice: Decimal?
    /// The stop price of a `STP` order, the trailing amount of a `TRAIL` one, and so on (row 20).
    public var auxPrice: Decimal?
    /// IB's time-in-force text, such as `DAY` or `GTC` (row 21).
    public var tif: String
    /// Whether the order may fill outside regular trading hours, `outsideRth` in `ib_async` (row 33).
    public var outsideRTH: Bool
    /// The parent order's id for a child order, `parentId` in `ib_async` (row 28); `0` for none.
    public var parentID: Int
    /// Whether to transmit the order now (row 27); `false` stages it for a later transmit.
    public var transmit: Bool
    /// The One-Cancels-All group the order belongs to (row 22).
    public var ocaGroup: String
    /// ib_async's `Order.ocaType`, sent in placeOrder (row 46): what IB does to the rest of the group on a fill.
    public var ocaType: Int
    /// A caller's tag for the order (row 26).
    public var orderRef: String
    /// The account the order is for (row 23).
    public var account: String

    // The rest of the placeOrder rows, in row order (docs/protocol-178.md).
    /// `"O"` open or `"C"` close (row 24); `ib_async`'s default, where IB's own client sends `""`.
    public var openClose = "O"
    /// ib_async's `Order.origin`, sent in placeOrder (row 25): `0` customer, `1` firm.
    public var origin = 0
    /// ib_async's `Order.blockOrder`, sent in placeOrder (row 29).
    public var blockOrder = false
    /// ib_async's `Order.sweepToFill`, sent in placeOrder (row 30).
    public var sweepToFill = false
    /// The visible size of an iceberg order, ib_async's `Order.displaySize` (row 31).
    public var displaySize = 0
    /// ib_async's `Order.triggerMethod`, sent in placeOrder (row 32).
    public var triggerMethod = 0
    /// Whether the order is hidden from the book, ib_async's `Order.hidden` (row 34).
    public var hidden = false
    /// Sent only when the contract's `secType` is `BAG`, after row 34: the price of each leg.
    public var orderComboLegs: [OrderComboLeg] = []
    /// Sent only when the contract's `secType` is `BAG`, after row 34.
    public var smartComboRoutingParams: [TagValue] = []
    /// ib_async's `Order.discretionaryAmt`, sent in placeOrder (row 36).
    public var discretionaryAmt: Decimal = 0
    /// Start working the order after this time, IB's text (row 37).
    public var goodAfterTime = ""
    /// Cancel the order at this time, IB's text (row 38).
    public var goodTillDate = ""
    /// The Financial Advisor allocation group (row 39).
    public var faGroup = ""
    /// The Financial Advisor allocation method (row 40).
    public var faMethod = ""
    /// The Financial Advisor allocation percentage (row 41).
    public var faPercentage = ""
    /// The model portfolio code (row 42).
    public var modelCode = ""
    /// ib_async's `Order.shortSaleSlot`, sent in placeOrder (row 43).
    public var shortSaleSlot = 0
    /// Where to borrow shares for a short sale, `designatedLocation` in `ib_async` (row 44).
    public var designatedLocation = ""
    /// ib_async's `Order.exemptCode`, sent in placeOrder (row 45); `-1` is the default.
    public var exemptCode = -1
    /// ib_async's `Order.rule80A`, sent in placeOrder (row 47).
    public var rule80A = ""
    /// ib_async's `Order.settlingFirm`, sent in placeOrder (row 48).
    public var settlingFirm = ""
    /// Fill the whole quantity or none (row 49).
    public var allOrNone = false
    /// The smallest acceptable fill (row 50).
    public var minQty: Int?
    /// ib_async's `Order.percentOffset`, sent in placeOrder (row 51).
    public var percentOffset: Decimal?
    /// IB's deprecated `eTradeOnly` (placeOrder row 52); `nil` sends `0`, and `0` decodes to `nil`.
    public var eTradeOnly: Bool? = nil
    /// IB's deprecated `firmQuoteOnly` (row 53); `nil` sends `0`, and `0` decodes to `nil`.
    public var firmQuoteOnly: Bool? = nil
    /// IB's deprecated `nbboPriceCap` (row 54); `nil` sends `""`.
    public var nbboPriceCap: Decimal? = nil
    /// ib_async's `Order.auctionStrategy`, sent in placeOrder (row 55).
    public var auctionStrategy = 0
    /// ib_async's `Order.startingPrice`, sent in placeOrder (row 56).
    public var startingPrice: Decimal?
    /// ib_async's `Order.stockRefPrice`, sent in placeOrder (row 57).
    public var stockRefPrice: Decimal?
    /// ib_async's `Order.delta`, sent in placeOrder (row 58).
    public var delta: Decimal?
    /// ib_async's `Order.stockRangeLower`, sent in placeOrder (row 59).
    public var stockRangeLower: Decimal?
    /// ib_async's `Order.stockRangeUpper`, sent in placeOrder (row 60).
    public var stockRangeUpper: Decimal?
    /// ib_async's `Order.overridePercentageConstraints`, sent in placeOrder (row 61).
    public var overridePercentageConstraints = false
    /// Sent only when `orderType` starts with `VOL`: IB back-fills it into live orders and then rejects their
    /// modification.
    public var volatility: Decimal?
    /// ib_async's `Order.volatilityType`, sent in placeOrder (row 63).
    public var volatilityType: Int?
    /// ib_async's `Order.deltaNeutralOrderType`, sent in placeOrder (row 64); the 8 fields after row 65 go out
    /// only when it is set.
    public var deltaNeutralOrderType = ""
    /// ib_async's `Order.deltaNeutralAuxPrice`, sent in placeOrder (row 65).
    public var deltaNeutralAuxPrice: Decimal?
    // The 8 after row 65, sent only when deltaNeutralOrderType is set. completedOrder carries only conID,
    // shortSale, shortSaleSlot and designatedLocation.
    /// ib_async's `Order.deltaNeutralConId`, sent in placeOrder after row 65.
    public var deltaNeutralConID = 0
    /// ib_async's `Order.deltaNeutralSettlingFirm`, sent in placeOrder after row 65.
    public var deltaNeutralSettlingFirm = ""
    /// ib_async's `Order.deltaNeutralClearingAccount`, sent in placeOrder after row 65.
    public var deltaNeutralClearingAccount = ""
    /// ib_async's `Order.deltaNeutralClearingIntent`, sent in placeOrder after row 65.
    public var deltaNeutralClearingIntent = ""
    /// ib_async's `Order.deltaNeutralOpenClose`, sent in placeOrder after row 65.
    public var deltaNeutralOpenClose = ""
    /// ib_async's `Order.deltaNeutralShortSale`, sent in placeOrder after row 65.
    public var deltaNeutralShortSale = false
    /// ib_async's `Order.deltaNeutralShortSaleSlot`, sent in placeOrder after row 65.
    public var deltaNeutralShortSaleSlot = 0
    /// ib_async's `Order.deltaNeutralDesignatedLocation`, sent in placeOrder after row 65.
    public var deltaNeutralDesignatedLocation = ""
    /// ib_async's `Order.continuousUpdate`, sent in placeOrder (row 66).
    public var continuousUpdate = false
    /// ib_async's `Order.referencePriceType`, sent in placeOrder (row 67).
    public var referencePriceType: Int?
    /// ib_async's `Order.trailStopPrice`, sent in placeOrder (row 68): the stop price a trailing stop starts from.
    public var trailStopPrice: Decimal?
    /// A trailing stop's offset in percent, ib_async's `Order.trailingPercent` (row 69).
    public var trailingPercent: Decimal?
    /// A scale order's initial component size, ib_async's `Order.scaleInitLevelSize` (row 70).
    public var scaleInitLevelSize: Int?
    /// A scale order's subsequent component size, ib_async's `Order.scaleSubsLevelSize` (row 71).
    public var scaleSubsLevelSize: Int?
    /// A scale order's price increment (row 72); the 7 fields after it go out only when it is above 0.
    public var scalePriceIncrement: Decimal?
    // The 7 after row 72, sent only when scalePriceIncrement > 0.
    /// ib_async's `Order.scalePriceAdjustValue`, sent in placeOrder after row 72.
    public var scalePriceAdjustValue: Decimal?
    /// ib_async's `Order.scalePriceAdjustInterval`, sent in placeOrder after row 72.
    public var scalePriceAdjustInterval: Int?
    /// ib_async's `Order.scaleProfitOffset`, sent in placeOrder after row 72.
    public var scaleProfitOffset: Decimal?
    /// ib_async's `Order.scaleAutoReset`, sent in placeOrder after row 72.
    public var scaleAutoReset = false
    /// ib_async's `Order.scaleInitPosition`, sent in placeOrder after row 72.
    public var scaleInitPosition: Int?
    /// ib_async's `Order.scaleInitFillQty`, sent in placeOrder after row 72.
    public var scaleInitFillQty: Int?
    /// ib_async's `Order.scaleRandomPercent`, sent in placeOrder after row 72.
    public var scaleRandomPercent = false
    /// ib_async's `Order.scaleTable`, sent in placeOrder (row 73).
    public var scaleTable = ""
    /// When the order becomes active, IB's text (row 74).
    public var activeStartTime = ""
    /// When the order stops being active, IB's text (row 75).
    public var activeStopTime = ""
    /// ib_async's `Order.hedgeType`, sent in placeOrder (row 76); `hedgeParam` goes out only when it is set.
    public var hedgeType = ""
    /// ib_async's `Order.hedgeParam`, sent in placeOrder after row 76, only when `hedgeType` is set.
    public var hedgeParam = ""
    /// ib_async's `Order.optOutSmartRouting`, sent in placeOrder (row 77).
    public var optOutSmartRouting = false
    /// ib_async's `Order.clearingAccount`, sent in placeOrder (row 78).
    public var clearingAccount = ""
    /// ib_async's `Order.clearingIntent`, sent in placeOrder (row 79).
    public var clearingIntent = ""
    /// ib_async's `Order.notHeld`, sent in placeOrder (row 80).
    public var notHeld = false
    /// The IB algo's name, ib_async's `Order.algoStrategy` (row 82); `algoParams` goes out only when it is set.
    public var algoStrategy = ""
    /// The algo's parameters, sent in placeOrder after row 82, only when `algoStrategy` is set.
    public var algoParams: [TagValue] = []
    /// ib_async's `Order.algoId`, sent in placeOrder (row 83).
    public var algoID = ""
    /// Ask IB for the margin and commission instead of placing the order (row 84).
    public var whatIf = false
    /// ib_async's `Order.orderMiscOptions`, sent in placeOrder (row 85) as one `tag=value;` string.
    public var orderMiscOptions: [TagValue] = []
    /// ib_async's `Order.solicited`, sent in placeOrder (row 86).
    public var solicited = false
    /// ib_async's `Order.randomizeSize`, sent in placeOrder (row 87).
    public var randomizeSize = false
    /// ib_async's `Order.randomizePrice`, sent in placeOrder (row 88).
    public var randomizePrice = false
    // The 5 after row 88, sent only for PEG BENCH and PEGBENCH.
    /// ib_async's `Order.referenceContractId`, sent in placeOrder after row 88 for `PEG BENCH`.
    public var referenceContractID = 0
    /// ib_async's `Order.isPeggedChangeAmountDecrease`, sent in placeOrder after row 88 for `PEG BENCH`.
    public var isPeggedChangeAmountDecrease = false
    /// ib_async's `Order.peggedChangeAmount`, sent in placeOrder after row 88 for `PEG BENCH`.
    public var peggedChangeAmount: Decimal = 0
    /// ib_async's `Order.referenceChangeAmount`, sent in placeOrder after row 88 for `PEG BENCH`.
    public var referenceChangeAmount: Decimal = 0
    /// ib_async's `Order.referenceExchangeId`, sent in placeOrder after row 88 for `PEG BENCH`.
    public var referenceExchangeID = ""
    /// The order's conditions: row 89 is their count, then the elements.
    public var conditions: [OrderCondition] = []
    /// ib_async's `Order.conditionsIgnoreRth`, sent after the conditions, only when there are any.
    public var conditionsIgnoreRTH = false
    /// ib_async's `Order.conditionsCancelOrder`, sent after the conditions, only when there are any: cancel the
    /// order, rather than submit it, once a condition is met.
    public var conditionsCancelOrder = false
    /// ib_async's `Order.adjustedOrderType`, sent in placeOrder (row 90).
    public var adjustedOrderType = ""
    /// ib_async's `Order.triggerPrice`, sent in placeOrder (row 91).
    public var triggerPrice: Decimal?
    /// ib_async's `Order.lmtPriceOffset`, sent in placeOrder (row 92).
    public var limitPriceOffset: Decimal?
    /// ib_async's `Order.adjustedStopPrice`, sent in placeOrder (row 93).
    public var adjustedStopPrice: Decimal?
    /// ib_async's `Order.adjustedStopLimitPrice`, sent in placeOrder (row 94).
    public var adjustedStopLimitPrice: Decimal?
    /// ib_async's `Order.adjustedTrailingAmount`, sent in placeOrder (row 95).
    public var adjustedTrailingAmount: Decimal?
    /// ib_async's `Order.adjustableTrailingUnit`, sent in placeOrder (row 96).
    public var adjustableTrailingUnit = 0
    /// ib_async's `Order.extOperator`, sent in placeOrder (row 97).
    public var extOperator = ""
    /// The soft-dollar tier, sent in placeOrder as its name and value (rows 98-99).
    public var softDollarTier = SoftDollarTier()
    /// An order sized in currency instead of shares, ib_async's `Order.cashQty` (row 100).
    public var cashQty: Decimal?
    /// ib_async's `Order.mifid2DecisionMaker`, sent in placeOrder (row 101).
    public var mifid2DecisionMaker = ""
    /// ib_async's `Order.mifid2DecisionAlgo`, sent in placeOrder (row 102).
    public var mifid2DecisionAlgo = ""
    /// ib_async's `Order.mifid2ExecutionTrader`, sent in placeOrder (row 103).
    public var mifid2ExecutionTrader = ""
    /// ib_async's `Order.mifid2ExecutionAlgo`, sent in placeOrder (row 104).
    public var mifid2ExecutionAlgo = ""
    /// ib_async's `Order.dontUseAutoPriceForHedge`, sent in placeOrder (row 105).
    public var dontUseAutoPriceForHedge = false
    /// ib_async's `Order.isOmsContainer`, sent in placeOrder (row 106).
    public var isOmsContainer = false
    /// ib_async's `Order.discretionaryUpToLimitPrice`, sent in placeOrder (row 107).
    public var discretionaryUpToLimitPrice = false
    /// ib_async's `Order.usePriceMgmtAlgo`, sent in placeOrder (row 108).
    public var usePriceMgmtAlgo = false
    /// ib_async's `Order.duration`, sent in placeOrder (row 109).
    public var duration: Int?
    /// ib_async's `Order.postToAts`, sent in placeOrder (row 110).
    public var postToAts: Int?
    /// ib_async's `Order.autoCancelParent`, sent in placeOrder (row 111).
    public var autoCancelParent = false
    /// ib_async's `Order.advancedErrorOverride`, sent in placeOrder (row 112).
    public var advancedErrorOverride = ""
    /// ib_async's `Order.manualOrderTime`, sent in placeOrder (row 113).
    public var manualOrderTime = ""
    // After row 113: minTradeQty for exchange IBKRATS; minCompeteSize and competeAgainstBestOffset for PEG BEST and
    // PEGBEST (the mid offsets too when it is upToMid); the mid offsets for PEG MID and PEGMID.
    /// ib_async's `Order.minTradeQty`, sent in placeOrder after row 113 for exchange `IBKRATS`.
    public var minTradeQty: Int?
    /// ib_async's `Order.minCompeteSize`, sent in placeOrder after row 113 for `PEG BEST`.
    public var minCompeteSize: Int?
    /// ib_async's `Order.competeAgainstBestOffset`, sent in placeOrder after row 113 for `PEG BEST`.
    public var competeAgainstBestOffset: CompeteOffset?
    /// ib_async's `Order.midOffsetAtWhole`, sent in placeOrder after row 113 (see the note above).
    public var midOffsetAtWhole: Decimal?
    /// ib_async's `Order.midOffsetAtHalf`, sent in placeOrder after row 113 (see the note above).
    public var midOffsetAtHalf: Decimal?

    // Decoded only, never sent: openOrder's, then completedOrder's.
    /// ib_async's `Order.basisPoints`, decoded from openOrder.
    public var basisPoints: Decimal?
    /// ib_async's `Order.basisPointsType`, decoded from openOrder.
    public var basisPointsType: Int?
    /// ib_async's `Order.autoCancelDate`, decoded from completedOrder.
    public var autoCancelDate = ""
    /// ib_async's `Order.refFuturesConId`, decoded from completedOrder.
    public var refFuturesConID: Int?
    /// ib_async's `Order.shareholder`, decoded from completedOrder.
    public var shareholder = ""
    /// ib_async's `Order.imbalanceOnly`, decoded from completedOrder.
    public var imbalanceOnly = false
    /// ib_async's `Order.routeMarketableToBbo`, decoded from completedOrder.
    public var routeMarketableToBbo = false
    /// ib_async's `Order.parentPermId`, decoded from completedOrder.
    public var parentPermID: Int?

    /// An order with `ib_async`'s defaults for every other field.
    public init(action: OrderAction, quantity: Decimal, orderType: String,
                limitPrice: Decimal? = nil, auxPrice: Decimal? = nil, tif: String = "DAY") {
        self.action = action; totalQuantity = quantity; self.orderType = orderType
        self.limitPrice = limitPrice; self.auxPrice = auxPrice; self.tif = tif
        outsideRTH = false; parentID = 0; transmit = true
        ocaGroup = ""; ocaType = 0; orderRef = ""; account = ""
    }
}
