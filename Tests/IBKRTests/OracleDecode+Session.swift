import Foundation
@testable import IBKR

/// in 4, 9, 15, 49, 107 under ib_async's wrapper names (wrapper.py: error, nextValidId, managedAccounts, currentTime,
/// userInfo). ib_async passes managedAccounts' raw comma string; swift-ibkr splits it, so the mapping joins it back.
func sessionCalls(id: Int, _ m: IBMessage) -> [OracleCall]? {
    switch m {
    case .error(let e):
        [OracleCall(method: "error", args: ["reqId": canon(e.requestID), "errorCode": canon(e.code),
                                            "errorString": e.text, "advancedOrderRejectJson": e.advancedOrderRejectJSON])]
    case .nextValidID(let id): [OracleCall(method: "nextValidId", args: ["reqId": canon(id)])]
    case .managedAccounts(let accounts):
        [OracleCall(method: "managedAccounts", args: ["accountsList": accounts.joined(separator: ",")])]
    case .currentTime(let time): [OracleCall(method: "currentTime", args: ["time": canon(time)])]
    case .userInfo(let requestID, let whiteBrandingID):
        [OracleCall(method: "userInfo", args: ["reqId": canon(requestID), "whiteBrandingId": whiteBrandingID])]
    default: nil
    }
}
