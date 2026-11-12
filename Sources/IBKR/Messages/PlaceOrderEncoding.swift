import Foundation

extension IBRequest {
    /// placeOrder (out 3) with the BAG, delta-neutral, scale, hedge and delta-neutral-contract groups; no algo / PEG /
    /// conditions yet. Rows that open a group not modelled carry the table's default; row numbers are the table's.
    static func placeOrder(_ w: inout FieldWriter, _ id: Int, _ c: Contract, _ o: Order) throws(IBEncodingError) {
        // Table conditions that add fields this encoder does not emit; refuse rather than misalign.
        if c.exchange == "IBKRATS" { throw .unsupported("exchange IBKRATS") }
        if ["PEG BENCH", "PEGBENCH", "PEG BEST", "PEGBEST", "PEG MID", "PEGMID"].contains(o.orderType) {
            throw .unsupported("orderType \(o.orderType)")
        }
        func raw(_ values: String...) throws(IBEncodingError) { for v in values { try w.add(v) } }
        w.add(3); w.add(id)
        try contract(&w, c, allowBag: true)
        try w.add(c.secIDType); try w.add(c.secID)                                        // 14-15
        try w.add(o.action.rawValue); w.add(o.totalQuantity); try w.add(o.orderType)       // 16-18
        w.add(o.limitPrice); w.add(o.auxPrice)                                            // 19-20
        try w.add(o.tif); try w.add(o.ocaGroup); try w.add(o.account)                     // 21-23
        try w.add(o.openClose); w.add(o.origin); try w.add(o.orderRef)                    // 24-26
        w.add(o.transmit); w.add(o.parentID)                                              // 27-28
        w.add(o.blockOrder); w.add(o.sweepToFill); w.add(o.displaySize); w.add(o.triggerMethod)  // 29-32
        w.add(o.outsideRTH); w.add(o.hidden)                                              // 33-34
        if c.secType == "BAG" {
            w.add(c.comboLegs.count)
            for l in c.comboLegs {
                w.add(l.conID); w.add(l.ratio); try w.add(l.action.rawValue); try w.add(l.exchange)
                w.add(l.openClose); w.add(l.shortSaleSlot); try w.add(l.designatedLocation); w.add(l.exemptCode)
            }
            w.add(o.orderComboLegs.count)
            for l in o.orderComboLegs { w.add(l.price) }
            w.add(o.smartComboRoutingParams.count)
            for p in o.smartComboRoutingParams { try w.add(p.tag); try w.add(p.value) }
        }
        try raw("")                                                                       // 35 sharesAllocation
        w.addDouble(o.discretionaryAmt); try w.add(o.goodAfterTime); try w.add(o.goodTillDate)    // 36-38
        try w.add(o.faGroup); try w.add(o.faMethod); try w.add(o.faPercentage); try w.add(o.modelCode)  // 39-42
        w.add(o.shortSaleSlot); try w.add(o.designatedLocation); w.add(o.exemptCode)     // 43-45
        w.add(o.ocaType); try w.add(o.rule80A); try w.add(o.settlingFirm)                 // 46-48
        w.add(o.allOrNone); w.add(o.minQty); w.add(o.percentOffset)                       // 49-51
        try raw("0", "0", "")                                                             // 52-54 eTradeOnly, firmQuoteOnly, nbboPriceCap
        w.add(o.auctionStrategy); w.add(o.startingPrice); w.add(o.stockRefPrice); w.add(o.delta)  // 55-58
        w.add(o.stockRangeLower); w.add(o.stockRangeUpper); w.add(o.overridePercentageConstraints)  // 59-61
        w.add(o.orderType.hasPrefix("VOL") ? o.volatility : nil); w.add(o.volatilityType)  // 62-63
        try w.add(o.deltaNeutralOrderType); w.add(o.deltaNeutralAuxPrice)                 // 64-65
        if !o.deltaNeutralOrderType.isEmpty {
            w.add(o.deltaNeutralConID); try w.add(o.deltaNeutralSettlingFirm)
            try w.add(o.deltaNeutralClearingAccount); try w.add(o.deltaNeutralClearingIntent)
            try w.add(o.deltaNeutralOpenClose); w.add(o.deltaNeutralShortSale)
            w.add(o.deltaNeutralShortSaleSlot); try w.add(o.deltaNeutralDesignatedLocation)
        }
        w.add(o.continuousUpdate); w.add(o.referencePriceType)                            // 66-67
        w.add(o.trailStopPrice); w.add(o.trailingPercent)                                 // 68-69
        w.add(o.scaleInitLevelSize); w.add(o.scaleSubsLevelSize); w.add(o.scalePriceIncrement)  // 70-72
        if let increment = o.scalePriceIncrement, increment > 0 {
            w.add(o.scalePriceAdjustValue); w.add(o.scalePriceAdjustInterval); w.add(o.scaleProfitOffset)
            w.add(o.scaleAutoReset); w.add(o.scaleInitPosition); w.add(o.scaleInitFillQty); w.add(o.scaleRandomPercent)
        }
        try w.add(o.scaleTable); try w.add(o.activeStartTime); try w.add(o.activeStopTime)  // 73-75
        try w.add(o.hedgeType)                                                            // 76
        if !o.hedgeType.isEmpty { try w.add(o.hedgeParam) }
        w.add(o.optOutSmartRouting); try w.add(o.clearingAccount); try w.add(o.clearingIntent)  // 77-79
        w.add(o.notHeld)                                                                  // 80
        if let dnc = c.deltaNeutralContract {                                             // 81
            w.add(true); w.add(dnc.conID); w.addDouble(dnc.delta); w.addDouble(dnc.price)
        } else {
            w.add(false)
        }
        try raw("")                                                                       // 82 algoStrategy
        try w.add(o.algoID); w.add(o.whatIf)                                              // 83-84
        try w.add(o.orderMiscOptions.map { "\($0.tag)=\($0.value);" }.joined())           // 85
        w.add(o.solicited); w.add(o.randomizeSize); w.add(o.randomizePrice)               // 86-88
        try raw("0")                                                                      // 89 conditionsCount
        try w.add(o.adjustedOrderType); w.add(o.triggerPrice); w.add(o.limitPriceOffset)  // 90-92
        w.add(o.adjustedStopPrice); w.add(o.adjustedStopLimitPrice); w.add(o.adjustedTrailingAmount)  // 93-95
        w.add(o.adjustableTrailingUnit); try w.add(o.extOperator)                         // 96-97
        try w.add(o.softDollarTier.name); try w.add(o.softDollarTier.value)               // 98-99
        w.add(o.cashQty)                                                                  // 100
        try w.add(o.mifid2DecisionMaker); try w.add(o.mifid2DecisionAlgo)                 // 101-102
        try w.add(o.mifid2ExecutionTrader); try w.add(o.mifid2ExecutionAlgo)              // 103-104
        w.add(o.dontUseAutoPriceForHedge); w.add(o.isOmsContainer)                        // 105-106
        w.add(o.discretionaryUpToLimitPrice); w.add(o.usePriceMgmtAlgo)                   // 107-108
        w.add(o.duration); w.add(o.postToAts); w.add(o.autoCancelParent)                  // 109-111
        try w.add(o.advancedErrorOverride); try w.add(o.manualOrderTime)                  // 112-113
    }
}
