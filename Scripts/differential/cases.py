"""Encode cases: (case name, ib_async `Client` method, keyword arguments with ib_async objects).

The generator calls `Client.<method>(**kwargs)` with the send path captured and writes the fields to encode.json.
Arguments are what ib.py would pass the `Client` (a case that prepares one names the ib.py line it imitates).
Each request runs once at its defaults (a required argument at its type's zero value, an enum at its first value)
and once with every argument non-default, neighbouring arguments of one kind distinct so a swapped write fails.
`_client` holds `Client` attributes a method reads instead of arguments (CLIENT_ATTRS, ruling P15).
"""

import datetime

from ib_async import util
from ib_async.contract import ComboLeg, Contract, DeltaNeutralContract
from ib_async.objects import ExecutionFilter

# Client attributes each method sends (client.py:1017); encode.json records them under args["_client"].
CLIENT_ATTRS: dict[str, tuple[str, ...]] = {"startApi": ("clientId", "optCapab")}


def ib_datetime(dt: datetime.datetime) -> str:
    """A date argument as ib.py formats it (util.formatIBDatetime, util.py:574-590); naive times are refused (P2)."""
    assert isinstance(dt, datetime.datetime) and dt.tzinfo is not None, f"{dt!r} must be a tz-aware UTC datetime"
    return util.formatIBDatetime(dt)


# ib.py:2247-2258: the tags reqAccountSummaryAsync joins into one string.
IB_ACCOUNT_SUMMARY_TAGS = (
    "AccountType,NetLiquidation,TotalCashValue,SettledCash,"
    "AccruedCash,BuyingPower,EquityWithLoanValue,"
    "PreviousDayEquityWithLoanValue,GrossPositionValue,RegTEquity,"
    "RegTMargin,SMA,InitMarginReq,MaintMarginReq,AvailableFunds,"
    "ExcessLiquidity,Cushion,FullInitMarginReq,FullMaintMarginReq,"
    "FullAvailableFunds,FullExcessLiquidity,LookAheadNextChange,"
    "LookAheadInitMarginReq,LookAheadMaintMarginReq,"
    "LookAheadAvailableFunds,LookAheadExcessLiquidity,"
    "HighestSeverity,DayTradesRemaining,DayTradesRemainingT+1,"
    "DayTradesRemainingT+2,DayTradesRemainingT+3,"
    "DayTradesRemainingT+4,Leverage,$LEDGER:ALL"
)

# Every Contract attribute set (description excepted: swift-ibkr does not model it, so it keeps ib_async's default).
OPTION = Contract(
    conId=681734412, symbol="AAPL", secType="OPT", lastTradeDateOrContractMonth="20261218", strike=182.5,
    right="C", multiplier="100", exchange="SMART", primaryExchange="CBOE", currency="USD",
    localSymbol="AAPL  261218C00182500", tradingClass="AAPL", includeExpired=True, secIdType="ISIN",
    secId="US0378331005", issuerId="e1234567", comboLegsDescrip="leg text",
    comboLegs=[ComboLeg(conId=8314, ratio=2, action="SELL", exchange="CBOE", openClose=1, shortSaleSlot=2,
                        designatedLocation="LOC", exemptCode=3)],
    deltaNeutralContract=DeltaNeutralContract(conId=265598, delta=0.25, price=181.75),
)

CASES: list[tuple[str, str, dict]] = [
    # session
    ("startApi/default", "startApi", {}),  # Client's own clientId -1 and optCapab "" (client.py:114-115)
    ("startApi/set", "startApi", {"_client": {"clientId": 7, "optCapab": "+PACEAPI"}}),
    ("reqIds/one", "reqIds", {"numIds": 1}),  # swift-ibkr always asks for one id; ib.py never calls reqIds
    ("reqCurrentTime/default", "reqCurrentTime", {}),
    ("reqManagedAccts/default", "reqManagedAccts", {}),
    ("reqUserInfo/default", "reqUserInfo", {"reqId": 0}),
    ("reqUserInfo/set", "reqUserInfo", {"reqId": 41}),
    ("setServerLogLevel/default", "setServerLogLevel", {"logLevel": 1}),
    ("setServerLogLevel/set", "setServerLogLevel", {"logLevel": 5}),
    ("reqMarketDataType/default", "reqMarketDataType", {"marketDataType": 1}),
    ("reqMarketDataType/set", "reqMarketDataType", {"marketDataType": 4}),
    # account
    ("reqPositions/default", "reqPositions", {}),
    ("cancelPositions/default", "cancelPositions", {}),
    ("reqAccountSummary/default", "reqAccountSummary", {"reqId": 0, "groupName": "", "tags": ""}),
    ("reqAccountSummary/set", "reqAccountSummary",  # ib.py:2260
     {"reqId": 12, "groupName": "All", "tags": IB_ACCOUNT_SUMMARY_TAGS}),
    ("cancelAccountSummary/default", "cancelAccountSummary", {"reqId": 0}),
    ("cancelAccountSummary/set", "cancelAccountSummary", {"reqId": 13}),
    ("reqPnLSingle/default", "reqPnLSingle", {"reqId": 0, "account": "", "modelCode": "", "conid": 0}),
    ("reqPnLSingle/set", "reqPnLSingle", {"reqId": 14, "account": "DU0000001", "modelCode": "MODEL1",
                                          "conid": 265598}),
    ("cancelPnLSingle/default", "cancelPnLSingle", {"reqId": 0}),
    ("cancelPnLSingle/set", "cancelPnLSingle", {"reqId": 15}),
    ("reqAccountUpdates/default", "reqAccountUpdates", {"subscribe": False, "acctCode": ""}),
    ("reqAccountUpdates/set", "reqAccountUpdates", {"subscribe": True, "acctCode": "DU0000001"}),  # ib.py:2221
    ("reqPositionsMulti/default", "reqPositionsMulti", {"reqId": 0, "account": "", "modelCode": ""}),
    ("reqPositionsMulti/set", "reqPositionsMulti", {"reqId": 16, "account": "DU0000001", "modelCode": "MODEL1"}),
    ("cancelPositionsMulti/default", "cancelPositionsMulti", {"reqId": 0}),
    ("cancelPositionsMulti/set", "cancelPositionsMulti", {"reqId": 17}),
    ("reqAccountUpdatesMulti/default", "reqAccountUpdatesMulti",
     {"reqId": 0, "account": "", "modelCode": "", "ledgerAndNLV": False}),
    ("reqAccountUpdatesMulti/set", "reqAccountUpdatesMulti",
     {"reqId": 18, "account": "DU0000001", "modelCode": "MODEL1", "ledgerAndNLV": True}),
    ("cancelAccountUpdatesMulti/default", "cancelAccountUpdatesMulti", {"reqId": 0}),
    ("cancelAccountUpdatesMulti/set", "cancelAccountUpdatesMulti", {"reqId": 19}),
    ("reqPnL/default", "reqPnL", {"reqId": 0, "account": "", "modelCode": ""}),
    ("reqPnL/set", "reqPnL", {"reqId": 20, "account": "DU0000001", "modelCode": "MODEL1"}),
    ("cancelPnL/default", "cancelPnL", {"reqId": 0}),
    ("cancelPnL/set", "cancelPnL", {"reqId": 21}),
    # order side
    ("cancelOrder/default", "cancelOrder", {"orderId": 0}),
    ("cancelOrder/set", "cancelOrder", {"orderId": 22, "manualCancelOrderTime": "20261113-10:15:00"}),
    ("exerciseOptions/default", "exerciseOptions",
     {"reqId": 0, "contract": Contract(), "exerciseAction": 1, "exerciseQuantity": 0, "account": "",
      "override": 0}),
    ("exerciseOptions/set", "exerciseOptions",  # ib.py:1805 passes the int flags through
     {"reqId": 23, "contract": OPTION, "exerciseAction": 2, "exerciseQuantity": 3, "account": "DU0000001",
      "override": 1}),
    ("reqGlobalCancel/default", "reqGlobalCancel", {}),
    ("reqOpenOrders/default", "reqOpenOrders", {}),
    ("reqAllOpenOrders/default", "reqAllOpenOrders", {}),
    ("reqAutoOpenOrders/default", "reqAutoOpenOrders", {"bAutoBind": False}),
    ("reqAutoOpenOrders/set", "reqAutoOpenOrders", {"bAutoBind": True}),
    ("reqCompletedOrders/default", "reqCompletedOrders", {"apiOnly": False}),
    ("reqCompletedOrders/set", "reqCompletedOrders", {"apiOnly": True}),
    ("reqExecutions/default", "reqExecutions",  # ib.py:2281: ExecutionFilter() when none is given
     {"reqId": 0, "execFilter": ExecutionFilter()}),
    ("reqExecutions/set", "reqExecutions",
     {"reqId": 24, "execFilter": ExecutionFilter(clientId=3, acctCode="DU0000001", time="20261113-09:30:00",
                                                 symbol="AAPL", secType="STK", exchange="ISLAND", side="BOT")}),
]
