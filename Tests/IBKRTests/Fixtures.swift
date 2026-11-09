import Foundation

func body(_ fields: [String]) -> [UInt8] { fields.flatMap { Array($0.utf8) + [0] } }

/// Version-178 incoming order messages in their base case (docs/protocol-178.md), every unmodelled
/// field at what a gateway sends for a plain SMART stock order.
enum Fixtures {
    static func openOrderFields(orderID: Int, permID: Int, clientID: Int, symbol: String, action: String, quantity: String,
                                orderType: String, limitPrice: String, auxPrice: String, tif: String, parentID: String,
                                outsideRTH: String, orderRef: String, status: String) -> [String] {
        ["5", "\(orderID)",
         "0", symbol, "STK", "", "0", "", "", "SMART", "USD", symbol, "",                      // 2–12 contract
         action, quantity, orderType, limitPrice, auxPrice, tif, "", "DU123456", "O", "0", orderRef, // 13–23
         "\(clientID)", "\(permID)", outsideRTH,                                               // 24–26
         "0", "0", "", "", "", "", "", "", "", "", "", "", "0", "", "-1", "0",                 // 27–42 hidden … auctionStrategy
         "", "", "", "", "", "0", "0", "0", "0", "",                                           // 43–52 startingPrice … minQty
         "0", "0", "0", "", parentID,                                                          // 53–57 ocaType … parentId
         "0", "", "0", "", "",                                                                 // 58–62 triggerMethod … deltaNeutralAuxPrice
         "0", "0", "", "", "", "",                                                             // 63–68 continuousUpdate … basisPointsType
         "", "0", "0", "0",                                                                    // 69–72 combo legs, smart routing counts
         "", "", "", "",                                                                       // 73–76 scale …, hedgeType
         "0", "", "IB", "0", "0", "", "0", "0",                                                // 77–84 optOutSmartRouting … whatIf
         status,                                                                               // 85
         "", "", "", "", "", "", "", "", "",                                                   // 86–94 margins
         "", "", "", "", "",                                                                   // 95–99 commission … warningText
         "0", "0", "0",                                                                        // 100–102 randomize, conditionsCount
         "", "", "", "", "", "", "", "0", "", "", "", "",                                      // 103–114 adjustedOrderType … cashQty
         "0", "0", "0", "0", "", "", "0",                                                      // 115–121
         "", "", "", "", ""]                                                                   // 122–126 minTradeQty … midOffsetAtHalf
    }

    /// orderID, clientID and parentID are not on the wire at 178 and are ignored: they are kept so both
    /// builders take the same arguments. `completedStatus` defaults to `status`.
    static func completedOrderFields(orderID: Int, permID: Int, clientID: Int, symbol: String, action: String,
                                     quantity: String, orderType: String, limitPrice: String, auxPrice: String,
                                     tif: String, parentID: String, outsideRTH: String, orderRef: String, status: String,
                                     completedTime: String = "20261109 15:59:01",
                                     completedStatus: String? = nil,
                                     filledQuantity: String = "0") -> [String] {
        ["101",
         "0", symbol, "STK", "", "0", "", "", "SMART", "USD", symbol, "",                      // 1–11 contract
         action, quantity, orderType, limitPrice, auxPrice, tif, "", "DU123456", "O", "0", orderRef, // 12–22
         "\(permID)", outsideRTH,                                                              // 23–24
         "0", "0", "", "", "", "", "", "", "", "", "", "0", "", "-1",                          // 25–38 hidden … exemptCode
         "", "", "", "", "", "0", "0", "0", "",                                                // 39–47 startingPrice … minQty
         "0", "0", "", "0", "", "",                                                            // 48–53 ocaType … deltaNeutralAuxPrice
         "0", "0", "", "",                                                                     // 54–57 continuousUpdate … trailingPercent
         "", "0", "0", "0",                                                                    // 58–61 combo legs, smart routing counts
         "", "", "", "",                                                                       // 62–65 scale …, hedgeType
         "", "IB", "0", "0", "", "0",                                                          // 66–71 clearingAccount … solicited
         status,                                                                               // 72
         "0", "0", "0",                                                                        // 73–75 randomize, conditionsCount
         "", "", "", "0", "0", "", filledQuantity, "", "0", "", "0", "0", "",                           // 76–88 trailStopPrice … parentPermId
         completedTime, completedStatus ?? status,                                             // 89–90
         "", "", "", "", ""]                                                                   // 91–95 minTradeQty … midOffsetAtHalf
    }
}
