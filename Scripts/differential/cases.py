"""Encode cases: (case name, ib_async `Client` method, keyword arguments with ib_async objects).

The generator calls `Client.<method>(**kwargs)` with the send path captured and writes the fields to encode.json.
Arguments are what ib.py would pass the `Client` (a case that prepares one names the ib.py line it imitates).
Each request runs once at its defaults (a required argument at its type's zero value, an enum at its first value)
and once with every argument non-default, neighbouring arguments of one kind distinct so a swapped write fails.
`_client` holds `Client` attributes a method reads instead of arguments (CLIENT_ATTRS, ruling P15).
"""

import datetime
import json
import math
import os

from ib_async import util
from ib_async.contract import Bag, ComboLeg, Contract, DeltaNeutralContract, Stock, TagValue
from ib_async.decoder import Decoder
from ib_async.ib import IB
from ib_async.objects import ExecutionFilter, SoftDollarTier
from ib_async.order import (
    ExecutionCondition, LimitOrder, MarginCondition, MarketOrder, Order, OrderComboLeg, PercentChangeCondition,
    PriceCondition, StopLimitOrder, StopOrder, TimeCondition, VolumeCondition,
)

RECORDED = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Tests", "IBKRTests", "Recorded")

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
    localSymbol="AAPL  261218C00182500", tradingClass="AAPLW", includeExpired=True, secIdType="ISIN",
    secId="US0378331005", issuerId="e1234567", comboLegsDescrip="leg text",
    comboLegs=[ComboLeg(conId=8314, ratio=2, action="SELL", exchange="CBOE", openClose=1, shortSaleSlot=2,
                        designatedLocation="LOC", exemptCode=3)],
    deltaNeutralContract=DeltaNeutralContract(conId=265598, delta=0.25, price=181.75),
)

AAPL = Stock("AAPL", "SMART", "USD", conId=265598, primaryExchange="NASDAQ", localSymbol="AAPL", tradingClass="NMS")
BAG = Bag(symbol="AAPL", exchange="SMART", currency="USD", comboLegs=[
    ComboLeg(conId=265598, ratio=1, action="BUY", exchange="SMART", openClose=1, shortSaleSlot=2,
             designatedLocation="LOC1", exemptCode=3),
    ComboLeg(conId=272093, ratio=2, action="SELL", exchange="ISLAND", openClose=2, shortSaleSlot=1,
             designatedLocation="LOC2", exemptCode=4),
])


def _base(flip: bool) -> Order:
    """Every placeOrder field outside a conditional group set, values distinct within the order; the bools alternate
    in wire order (`flip` starts the other way), so each is non-default in one of the two cases and a swap fails."""
    bools = ["transmit", "blockOrder", "sweepToFill", "outsideRth", "hidden", "allOrNone", "eTradeOnly",
             "firmQuoteOnly", "overridePercentageConstraints", "continuousUpdate", "optOutSmartRouting", "notHeld",
             "whatIf", "solicited", "randomizeSize", "randomizePrice", "dontUseAutoPriceForHedge", "isOmsContainer",
             "discretionaryUpToLimitPrice", "usePriceMgmtAlgo", "autoCancelParent"]
    k = "b" if flip else "a"
    o = Order(
        action="SELL" if flip else "BUY", totalQuantity=12.5 if flip else 7, orderType="STP LMT" if flip else "LMT",
        lmtPrice=351.5, auxPrice=349.25, tif="GTC" if flip else "DAY", ocaGroup=f"oca-{k}", account="DU0000001",
        openClose="C", origin=1, orderRef=f"ref-{k}", parentId=7, displaySize=9, triggerMethod=2,
        discretionaryAmt=0.15, goodAfterTime="20261113 09:30:00 UTC", goodTillDate="20261120 16:00:00 UTC",
        faGroup=f"grp-{k}", faMethod="EqualQuantity", faPercentage="25", modelCode="MODEL1", shortSaleSlot=1,
        designatedLocation="LOC1", exemptCode=4, ocaType=3, rule80A="I", settlingFirm="FIRM1", minQty=100,
        percentOffset=0.01, nbboPriceCap=352.75, auctionStrategy=5, startingPrice=350.05, stockRefPrice=350.1,
        delta=0.45, stockRangeLower=340.5, stockRangeUpper=360.5, volatilityType=2, deltaNeutralAuxPrice=1.75,
        referencePriceType=2, trailStopPrice=345.5, trailingPercent=2.5, scaleInitLevelSize=10,
        scaleSubsLevelSize=6, scaleTable="tbl", activeStartTime="20261113 10:00:00 UTC",
        activeStopTime="20261113 15:00:00 UTC", clearingAccount="CLR1", clearingIntent="IB", algoId=f"algo-{k}",
        orderMiscOptions=[TagValue("opt1", "v1"), TagValue("opt2", "v2")], adjustedOrderType="STP",
        triggerPrice=348.5, lmtPriceOffset=0.05, adjustedStopPrice=347.5, adjustedStopLimitPrice=346.5,
        adjustedTrailingAmount=1.25, adjustableTrailingUnit=8, extOperator="ext1",
        softDollarTier=SoftDollarTier("tier-name", "tier-val", "Tier Display"), cashQty=5000.5,
        mifid2DecisionMaker="dm", mifid2DecisionAlgo="da", mifid2ExecutionTrader="et", mifid2ExecutionAlgo="ea",
        duration=30, postToAts=11, advancedErrorOverride="8229", manualOrderTime="20261113-10:15:00",
    )
    for i, name in enumerate(bools):
        setattr(o, name, (i % 2 == 0) != flip)
    return o


def _limit(**kwargs) -> Order:
    return LimitOrder("BUY", 10, 351.5, **kwargs)


def _price(conjunction="o", isMore=False):
    return PriceCondition(conjunction=conjunction, isMore=isMore, price=351.25, conId=265598, exch="NASDAQ",
                          triggerMethod=2)


_CONDITIONS = [
    ("price", _price()),
    ("time", TimeCondition(conjunction="o", isMore=False, time="20261113 14:30:00 UTC")),
    ("margin", MarginCondition(conjunction="o", isMore=False, percent=30)),
    ("execution", ExecutionCondition(conjunction="o", secType="STK", exch="ISLAND", symbol="MSFT")),
    ("volume", VolumeCondition(conjunction="o", isMore=False, volume=150000, conId=272093, exch="ARCA")),
    ("percent-change", PercentChangeCondition(conjunction="o", isMore=False, changePercent=2.5, conId=756733,
                                              exch="BATS")),
]


def _recorded_open_order(file: str) -> dict:
    """The first openOrder of a live recording as ib_async's Decoder builds it (decoder.py:882-1147), sent back as
    ib.py:790-791 sends a modification: `placeOrder(order.orderId, contract, order)`."""
    with open(os.path.join(RECORDED, file), encoding="utf-8", newline="\n") as f:
        frame = next(fields for fields in json.load(f) if fields[0] == "5")
    got = []

    class OpenOrders:  # the only wrapper method an openOrder frame calls
        def openOrder(self, orderId, contract, order, orderState):
            got.append((contract, order))

    Decoder(OpenOrders(), 178).interpret(frame)
    (contract, order), = got  # interpret swallows a decode error: then nothing was recorded
    return {"orderId": order.orderId, "contract": contract, "order": order}


# ib.py:723-748, bracketOrder with the ids its getReqId would hand out.
_BRACKET = [
    LimitOrder("BUY", 5, 350.5, orderId=40, transmit=False),
    LimitOrder("SELL", 5, 360.25, orderId=41, transmit=False, parentId=40),
    StopOrder("SELL", 5, 340.75, orderId=42, transmit=True, parentId=40),
]
# ib.py:753-765 (a staticmethod: no connection).
_OCA = IB.oneCancelsAll([LimitOrder("BUY", 3, 350.5), StopOrder("SELL", 3, 345.25)], "oca-group-1", 2)

PLACE_ORDER_CASES: list[tuple[str, str, dict]] = [
    ("placeOrder/limit", "placeOrder", {"orderId": 1, "contract": Stock("AAPL", "SMART", "USD"),
                                        "order": LimitOrder("BUY", 1, 351.5)}),
    ("placeOrder/market", "placeOrder", {"orderId": 2, "contract": AAPL, "order": MarketOrder("SELL", 2)}),
    ("placeOrder/stop", "placeOrder", {"orderId": 3, "contract": AAPL, "order": StopOrder("SELL", 3, 340.25)}),
    ("placeOrder/stop-limit", "placeOrder",
     {"orderId": 4, "contract": AAPL, "order": StopLimitOrder("BUY", 4, 352.5, 351.75)}),
    ("placeOrder/base-a", "placeOrder", {"orderId": 5, "contract": AAPL, "order": _base(False)}),
    ("placeOrder/base-b", "placeOrder", {"orderId": 6, "contract": AAPL, "order": _base(True)}),
    *[(f"placeOrder/condition-{name}", "placeOrder",
       {"orderId": 10 + i, "contract": AAPL,
        "order": _limit(conditions=[cond], conditionsIgnoreRth=True, conditionsCancelOrder=False)})
      for i, (name, cond) in enumerate(_CONDITIONS)],
    ("placeOrder/conditions-and-or", "placeOrder",
     {"orderId": 16, "contract": AAPL,
      "order": _limit(conditions=[_price("a", True), TimeCondition(conjunction="o", time="20261113 15:45:00 UTC")],
                      conditionsIgnoreRth=False, conditionsCancelOrder=True)}),
    ("placeOrder/conditions-all-six", "placeOrder",
     {"orderId": 17, "contract": AAPL,
      "order": _limit(conditions=[_price("a", True)] + [c for _, c in _CONDITIONS[1:]],
                      conditionsIgnoreRth=True, conditionsCancelOrder=False)}),
    ("placeOrder/algo-0-params", "placeOrder",
     {"orderId": 18, "contract": AAPL, "order": _limit(algoStrategy="Adaptive", algoId="algo-1")}),
    ("placeOrder/algo-1-param", "placeOrder",
     {"orderId": 19, "contract": AAPL,
      "order": _limit(algoStrategy="Adaptive", algoParams=[TagValue("adaptivePriority", "Urgent")])}),
    ("placeOrder/algo-2-params", "placeOrder",
     {"orderId": 20, "contract": AAPL,
      "order": _limit(algoStrategy="Vwap", algoParams=[TagValue("maxPctVol", "0.1"),
                                                       TagValue("startTime", "09:30:00 US/Eastern")])}),
    ("placeOrder/peg-bench", "placeOrder",
     {"orderId": 21, "contract": AAPL,
      "order": Order(action="BUY", totalQuantity=10, orderType="PEG BENCH", lmtPrice=351.5, auxPrice=0.5,
                     referenceContractId=272093, isPeggedChangeAmountDecrease=True, peggedChangeAmount=0.35,
                     referenceChangeAmount=0.2, referenceExchangeId="NASDAQ")}),
    ("placeOrder/pegbench", "placeOrder",
     {"orderId": 22, "contract": AAPL,
      "order": Order(action="SELL", totalQuantity=11, orderType="PEGBENCH", lmtPrice=350.5, auxPrice=0.25,
                     referenceContractId=756733, isPeggedChangeAmountDecrease=False, peggedChangeAmount=0.45,
                     referenceChangeAmount=0.3, referenceExchangeId="ARCA")}),
    ("placeOrder/peg-best", "placeOrder",
     {"orderId": 23, "contract": AAPL,
      "order": Order(action="BUY", totalQuantity=12, orderType="PEG BEST", lmtPrice=351.5, minCompeteSize=100,
                     competeAgainstBestOffset=0.02, midOffsetAtWhole=0.03, midOffsetAtHalf=0.015)}),
    ("placeOrder/pegbest-up-to-mid", "placeOrder",
     {"orderId": 24, "contract": AAPL,
      "order": Order(action="BUY", totalQuantity=13, orderType="PEGBEST", lmtPrice=351.5, minCompeteSize=200,
                     competeAgainstBestOffset=math.inf, midOffsetAtWhole=0.01, midOffsetAtHalf=0.005)}),
    ("placeOrder/peg-mid", "placeOrder",
     {"orderId": 25, "contract": AAPL,
      "order": Order(action="SELL", totalQuantity=14, orderType="PEG MID", lmtPrice=351.5, midOffsetAtWhole=0.02,
                     midOffsetAtHalf=0.035)}),
    ("placeOrder/pegmid", "placeOrder",
     {"orderId": 26, "contract": AAPL,
      "order": Order(action="BUY", totalQuantity=15, orderType="PEGMID", lmtPrice=351.5, midOffsetAtWhole=0.04,
                     midOffsetAtHalf=0.025)}),
    ("placeOrder/bag-two-legs", "placeOrder", {"orderId": 27, "contract": BAG, "order": _limit()}),
    ("placeOrder/bag-order-leg-prices", "placeOrder",
     {"orderId": 28, "contract": BAG,
      "order": _limit(orderComboLegs=[OrderComboLeg(1.25), OrderComboLeg(-0.75)],
                      smartComboRoutingParams=[TagValue("NonGuaranteed", "1")])}),
    ("placeOrder/bag-order-legs-without-prices", "placeOrder",
     {"orderId": 29, "contract": BAG,
      "order": _limit(orderComboLegs=[OrderComboLeg(), OrderComboLeg()],
                      smartComboRoutingParams=[TagValue("NonGuaranteed", "0"), TagValue("LeginPrio", "1")])}),
    ("placeOrder/delta-neutral-order", "placeOrder",
     {"orderId": 30, "contract": AAPL,
      "order": _limit(deltaNeutralOrderType="LMT", deltaNeutralAuxPrice=1.5, deltaNeutralConId=8314,
                      deltaNeutralSettlingFirm="DNFIRM", deltaNeutralClearingAccount="DNCLR",
                      deltaNeutralClearingIntent="Away", deltaNeutralOpenClose="C", deltaNeutralShortSale=True,
                      deltaNeutralShortSaleSlot=2, deltaNeutralDesignatedLocation="DNLOC")}),
    ("placeOrder/delta-neutral-order-type-only", "placeOrder",
     {"orderId": 31, "contract": AAPL, "order": _limit(deltaNeutralOrderType="MKT")}),
    ("placeOrder/delta-neutral-contract", "placeOrder",
     {"orderId": 32, "contract": OPTION, "order": LimitOrder("BUY", 2, 4.35)}),
    ("placeOrder/scale", "placeOrder",
     {"orderId": 33, "contract": AAPL,
      "order": _limit(scaleInitLevelSize=10, scaleSubsLevelSize=5, scalePriceIncrement=0.05,
                      scalePriceAdjustValue=0.02, scalePriceAdjustInterval=60, scaleProfitOffset=0.1,
                      scaleAutoReset=True, scaleInitPosition=20, scaleInitFillQty=3, scaleRandomPercent=False)}),
    ("placeOrder/scale-b", "placeOrder",
     {"orderId": 34, "contract": AAPL,
      "order": _limit(scalePriceIncrement=0.07, scaleAutoReset=False, scaleRandomPercent=True)}),
    ("placeOrder/scale-increment-zero", "placeOrder",  # 0 is not above 0: the 7 fields stay out
     {"orderId": 35, "contract": AAPL,
      "order": _limit(scaleInitLevelSize=10, scaleSubsLevelSize=5, scalePriceIncrement=0.0,
                      scalePriceAdjustValue=0.02, scaleAutoReset=True)}),
    ("placeOrder/hedge", "placeOrder",
     {"orderId": 36, "contract": AAPL, "order": _limit(hedgeType="D", hedgeParam="0.5")}),
    ("placeOrder/hedge-param-without-type", "placeOrder",
     {"orderId": 37, "contract": AAPL, "order": _limit(hedgeParam="0.5")}),
    ("placeOrder/what-if", "placeOrder", {"orderId": 38, "contract": AAPL, "order": _limit(whatIf=True)}),
    ("placeOrder/soft-dollar-tier", "placeOrder",
     {"orderId": 39, "contract": AAPL,
      "order": _limit(softDollarTier=SoftDollarTier("tier-name", "tier-val", "Tier Display"))}),
    ("placeOrder/cash-quantity", "placeOrder",
     {"orderId": 43, "contract": AAPL, "order": MarketOrder("BUY", 0, cashQty=5000.5)}),
    ("placeOrder/adjusted-stop", "placeOrder",
     {"orderId": 44, "contract": AAPL,
      "order": StopOrder("SELL", 10, 340.25, adjustedOrderType="STP LMT", triggerPrice=345.5, lmtPriceOffset=0.15,
                         adjustedStopPrice=344.25, adjustedStopLimitPrice=343.75, adjustedTrailingAmount=1.5,
                         adjustableTrailingUnit=1)}),
    ("placeOrder/ibkrats", "placeOrder",
     {"orderId": 45, "contract": Stock("AAPL", "IBKRATS", "USD"), "order": _limit(minTradeQty=10)}),
    ("placeOrder/deprecated-a", "placeOrder",
     {"orderId": 46, "contract": AAPL, "order": _limit(eTradeOnly=True, firmQuoteOnly=False, nbboPriceCap=352.25)}),
    ("placeOrder/deprecated-b", "placeOrder",
     {"orderId": 47, "contract": AAPL, "order": _limit(eTradeOnly=False, firmQuoteOnly=True)}),
    ("placeOrder/volatility-vol", "placeOrder",
     {"orderId": 48, "contract": AAPL,
      "order": Order(action="BUY", totalQuantity=1, orderType="VOL", volatility=0.35, volatilityType=2)}),
    ("placeOrder/volatility-lmt", "placeOrder",  # client.py:480-482 drops it for any type not VOL…
     {"orderId": 49, "contract": AAPL, "order": _limit(volatility=0.35, volatilityType=1)}),
    *[(f"placeOrder/bracket/{leg}", "placeOrder", {"orderId": o.orderId, "contract": AAPL, "order": o})
      for leg, o in zip(("parent", "take-profit", "stop-loss"), _BRACKET)],
    *[(f"placeOrder/oca/{n}", "placeOrder", {"orderId": 50 + i, "contract": AAPL, "order": o})
      for i, (n, o) in enumerate(zip(("first", "second"), _OCA))],
    # A modification is placeOrder again with the same id (ib.py:790-791).
    ("placeOrder/modify/place", "placeOrder", {"orderId": 60, "contract": AAPL, "order": LimitOrder("BUY", 5, 350.5)}),
    ("placeOrder/modify/again", "placeOrder", {"orderId": 60, "contract": AAPL, "order": LimitOrder("BUY", 6, 350.75)}),
    ("placeOrder/modify/recorded-openOrder", "placeOrder",
     _recorded_open_order("liveLimitOrderPlacesAndCancels.json")),
]

# Market data and history. Dates are what ib.py prepares with util.formatIBDatetime (ib.py:2353, 2385, 2414-2415).
_T0 = datetime.datetime(2026, 11, 13, 15, 30, 0, tzinfo=datetime.timezone.utc)
_T1 = datetime.datetime(2026, 11, 12, 9, 45, 30, tzinfo=datetime.timezone.utc)
_BAG_DNC = Bag(symbol="AAPL", exchange="SMART", currency="USD", comboLegs=list(BAG.comboLegs),
               deltaNeutralContract=DeltaNeutralContract(conId=8314, delta=-0.5, price=12.25))
_BAG_NO_LEGS = Bag(symbol="AAPL", exchange="SMART", currency="USD")
_OPT1 = [TagValue("XYZ", "1")]
_OPT2 = [TagValue("a", "1.5"), TagValue("b", "two")]
_NONE = Contract()


def _mkt(reqId, contract=AAPL, genericTickList="", snapshot=False, regulatorySnapshot=False, mktDataOptions=()):
    return {"reqId": reqId, "contract": contract, "genericTickList": genericTickList, "snapshot": snapshot,
            "regulatorySnapshot": regulatorySnapshot, "mktDataOptions": list(mktDataOptions)}


def _hist(reqId, contract=AAPL, endDateTime="", durationStr="1 D", barSizeSetting="5 mins", whatToShow="TRADES",
          useRTH=False, formatDate=2, keepUpToDate=False, chartOptions=()):
    return {"reqId": reqId, "contract": contract, "endDateTime": endDateTime, "durationStr": durationStr,
            "barSizeSetting": barSizeSetting, "whatToShow": whatToShow, "useRTH": useRTH, "formatDate": formatDate,
            "keepUpToDate": keepUpToDate, "chartOptions": list(chartOptions)}


def _ticks(reqId, contract=AAPL, start="", end="", n=0, what="TRADES", rth=False, ignoreSize=False, misc=()):
    return {"reqId": reqId, "contract": contract, "startDateTime": start, "endDateTime": end, "numberOfTicks": n,
            "whatToShow": what, "useRth": rth, "ignoreSize": ignoreSize, "miscOptions": list(misc)}


MARKET_DATA_CASES = [
    # reqMktData: generic ticks, snapshot vs regulatorySnapshot alone and together, options, BAG, delta-neutral
    ("reqMktData/default", "reqMktData", _mkt(0, _NONE)),
    ("reqMktData/generic-ticks", "reqMktData", _mkt(30, genericTickList="100,mdoff,292:BRFG")),
    ("reqMktData/snapshot", "reqMktData", _mkt(31, snapshot=True)),
    ("reqMktData/regulatory-snapshot", "reqMktData", _mkt(32, regulatorySnapshot=True)),
    ("reqMktData/snapshot-and-regulatory", "reqMktData",
     _mkt(33, genericTickList="233", snapshot=True, regulatorySnapshot=True)),
    ("reqMktData/options-1", "reqMktData", _mkt(34, mktDataOptions=_OPT1)),
    ("reqMktData/options-n", "reqMktData", _mkt(35, mktDataOptions=_OPT2)),
    ("reqMktData/delta-neutral", "reqMktData",
     _mkt(36, Stock("AAPL", "SMART", "USD", deltaNeutralContract=DeltaNeutralContract(
         conId=8314, delta=0.25, price=181.75)))),
    ("reqMktData/bag", "reqMktData", _mkt(37, BAG)),
    ("reqMktData/bag-no-legs", "reqMktData", _mkt(38, _BAG_NO_LEGS)),
    ("reqMktData/bag-delta-neutral", "reqMktData", _mkt(39, _BAG_DNC)),
    ("reqMktData/set", "reqMktData", _mkt(40, OPTION, "100,101,104,106", True, True, _OPT2)),
    ("cancelMktData/default", "cancelMktData", {"reqId": 0}),
    ("cancelMktData/set", "cancelMktData", {"reqId": 41}),
    # reqMktDepth: numRows vs isSmartDepth
    ("reqMktDepth/default", "reqMktDepth",
     {"reqId": 0, "contract": _NONE, "numRows": 0, "isSmartDepth": False, "mktDepthOptions": []}),
    ("reqMktDepth/smart", "reqMktDepth",
     {"reqId": 42, "contract": AAPL, "numRows": 7, "isSmartDepth": True, "mktDepthOptions": []}),
    ("reqMktDepth/not-smart", "reqMktDepth",
     {"reqId": 43, "contract": AAPL, "numRows": 5, "isSmartDepth": False, "mktDepthOptions": _OPT1}),
    ("reqMktDepth/set", "reqMktDepth",
     {"reqId": 44, "contract": OPTION, "numRows": 20, "isSmartDepth": True, "mktDepthOptions": _OPT2}),
    ("cancelMktDepth/default", "cancelMktDepth", {"reqId": 0, "isSmartDepth": False}),
    ("cancelMktDepth/smart", "cancelMktDepth", {"reqId": 45, "isSmartDepth": True}),
    ("cancelMktDepth/not-smart", "cancelMktDepth", {"reqId": 46, "isSmartDepth": False}),
    # reqHistoricalData: includeExpired / useRTH / keepUpToDate each alone, end date, chart options, BAG, SCHEDULE
    ("reqHistoricalData/default", "reqHistoricalData", _hist(0, _NONE, durationStr="", barSizeSetting="", whatToShow="")),
    ("reqHistoricalData/typical", "reqHistoricalData", _hist(50)),
    ("reqHistoricalData/end-date", "reqHistoricalData",
     _hist(51, endDateTime=ib_datetime(_T0), durationStr="2 W", barSizeSetting="1 hour", whatToShow="MIDPOINT")),
    ("reqHistoricalData/include-expired", "reqHistoricalData",
     _hist(52, OPTION, durationStr="1 M", barSizeSetting="1 day", whatToShow="BID")),
    ("reqHistoricalData/rth", "reqHistoricalData",
     _hist(53, durationStr="3 D", barSizeSetting="15 mins", whatToShow="ASK", useRTH=True)),
    ("reqHistoricalData/keep-up-to-date", "reqHistoricalData",
     _hist(54, durationStr="1800 S", barSizeSetting="1 min", keepUpToDate=True)),
    ("reqHistoricalData/chart-options-1", "reqHistoricalData",
     _hist(55, barSizeSetting="1 min", chartOptions=_OPT1)),
    ("reqHistoricalData/chart-options-n", "reqHistoricalData",
     _hist(56, barSizeSetting="1 min", chartOptions=_OPT2)),
    ("reqHistoricalData/bag", "reqHistoricalData",
     _hist(57, BAG, endDateTime=ib_datetime(_T1), durationStr="1 W", barSizeSetting="30 mins", useRTH=True)),
    ("reqHistoricalData/bag-no-legs", "reqHistoricalData",
     _hist(58, _BAG_NO_LEGS, durationStr="1 W", barSizeSetting="1 day")),
    # ib.py:2376-2398 (reqHistoricalSchedule): "<n> D", "1 day", SCHEDULE, formatDate 1, no chart options (None)
    ("reqHistoricalData/schedule", "reqHistoricalData",
     {**_hist(59, durationStr="7 D", barSizeSetting="1 day", whatToShow="SCHEDULE", useRTH=True, formatDate=1),
      "chartOptions": None}),
    ("reqHistoricalData/set", "reqHistoricalData",
     _hist(60, OPTION, ib_datetime(_T0), "2 M", "4 hours", "HISTORICAL_VOLATILITY", True, 2, True, _OPT2)),
    ("cancelHistoricalData/default", "cancelHistoricalData", {"reqId": 0}),
    ("cancelHistoricalData/set", "cancelHistoricalData", {"reqId": 61}),
    # reqRealTimeBars: ib.py always asks for 5-second bars (ib.py:1152)
    ("reqRealTimeBars/default", "reqRealTimeBars",
     {"reqId": 0, "contract": _NONE, "barSize": 5, "whatToShow": "", "useRTH": False, "realTimeBarsOptions": []}),
    ("reqRealTimeBars/rth", "reqRealTimeBars",
     {"reqId": 62, "contract": AAPL, "barSize": 5, "whatToShow": "MIDPOINT", "useRTH": True,
      "realTimeBarsOptions": []}),
    ("reqRealTimeBars/options-1", "reqRealTimeBars",
     {"reqId": 63, "contract": AAPL, "barSize": 5, "whatToShow": "TRADES", "useRTH": False,
      "realTimeBarsOptions": _OPT1}),
    ("reqRealTimeBars/set", "reqRealTimeBars",
     {"reqId": 64, "contract": OPTION, "barSize": 5, "whatToShow": "BID", "useRTH": True,
      "realTimeBarsOptions": _OPT2}),
    ("cancelRealTimeBars/default", "cancelRealTimeBars", {"reqId": 0}),
    ("cancelRealTimeBars/set", "cancelRealTimeBars", {"reqId": 65}),
    # reqMktDepthExchanges, reqSmartComponents
    ("reqMktDepthExchanges/default", "reqMktDepthExchanges", {}),
    ("reqSmartComponents/default", "reqSmartComponents", {"reqId": 0, "bboExchange": ""}),
    ("reqSmartComponents/set", "reqSmartComponents", {"reqId": 66, "bboExchange": "a6"}),
    # reqHeadTimeStamp and reqHistogramData: includeExpired and useRTH each alone, then both (formatDate 2: what
    # swift-ibkr always asks for, so Bar.time is a Date)
    ("reqHeadTimeStamp/default", "reqHeadTimeStamp",
     {"reqId": 0, "contract": _NONE, "whatToShow": "", "useRTH": False, "formatDate": 2}),
    ("reqHeadTimeStamp/include-expired", "reqHeadTimeStamp",
     {"reqId": 67, "contract": OPTION, "whatToShow": "TRADES", "useRTH": False, "formatDate": 2}),
    ("reqHeadTimeStamp/rth", "reqHeadTimeStamp",
     {"reqId": 68, "contract": AAPL, "whatToShow": "MIDPOINT", "useRTH": True, "formatDate": 2}),
    ("reqHeadTimeStamp/set", "reqHeadTimeStamp",
     {"reqId": 69, "contract": OPTION, "whatToShow": "BID_ASK", "useRTH": True, "formatDate": 2}),
    ("cancelHeadTimeStamp/default", "cancelHeadTimeStamp", {"reqId": 0}),
    ("cancelHeadTimeStamp/set", "cancelHeadTimeStamp", {"reqId": 70}),
    ("reqHistogramData/default", "reqHistogramData",
     {"tickerId": 0, "contract": _NONE, "useRTH": False, "timePeriod": ""}),
    ("reqHistogramData/include-expired", "reqHistogramData",
     {"tickerId": 71, "contract": OPTION, "useRTH": False, "timePeriod": "1 week"}),
    ("reqHistogramData/rth", "reqHistogramData",
     {"tickerId": 72, "contract": AAPL, "useRTH": True, "timePeriod": "3 days"}),
    ("reqHistogramData/set", "reqHistogramData",
     {"tickerId": 73, "contract": OPTION, "useRTH": True, "timePeriod": "2 months"}),
    ("cancelHistogramData/default", "cancelHistogramData", {"tickerId": 0}),
    ("cancelHistogramData/set", "cancelHistogramData", {"tickerId": 74}),
    # reqHistoricalTicks: start vs end, includeExpired / useRth / ignoreSize each alone, misc options
    ("reqHistoricalTicks/default", "reqHistoricalTicks", _ticks(0, _NONE, what="")),
    ("reqHistoricalTicks/start-only", "reqHistoricalTicks", _ticks(75, start=ib_datetime(_T1), n=100)),
    ("reqHistoricalTicks/end-only", "reqHistoricalTicks", _ticks(76, end=ib_datetime(_T0), n=200, what="BID_ASK")),
    ("reqHistoricalTicks/start-and-end", "reqHistoricalTicks",
     _ticks(77, start=ib_datetime(_T1), end=ib_datetime(_T0), n=300, what="MIDPOINT")),
    ("reqHistoricalTicks/include-expired", "reqHistoricalTicks", _ticks(78, OPTION, n=10)),
    ("reqHistoricalTicks/rth", "reqHistoricalTicks", _ticks(79, n=20, rth=True)),
    ("reqHistoricalTicks/ignore-size", "reqHistoricalTicks", _ticks(80, n=30, what="BID_ASK", ignoreSize=True)),
    ("reqHistoricalTicks/misc-options-1", "reqHistoricalTicks", _ticks(81, n=40, misc=_OPT1)),
    ("reqHistoricalTicks/misc-options-n", "reqHistoricalTicks", _ticks(82, n=50, misc=_OPT2)),
    ("reqHistoricalTicks/set", "reqHistoricalTicks",
     _ticks(83, OPTION, ib_datetime(_T1), ib_datetime(_T0), 1000, "BID_ASK", True, True, _OPT2)),
    # reqTickByTickData: each type, count and ignoreSize
    ("reqTickByTickData/default", "reqTickByTickData",
     {"reqId": 0, "contract": _NONE, "tickType": "Last", "numberOfTicks": 0, "ignoreSize": False}),
    ("reqTickByTickData/last", "reqTickByTickData",
     {"reqId": 84, "contract": AAPL, "tickType": "Last", "numberOfTicks": 0, "ignoreSize": False}),
    ("reqTickByTickData/all-last", "reqTickByTickData",
     {"reqId": 85, "contract": AAPL, "tickType": "AllLast", "numberOfTicks": 100, "ignoreSize": True}),
    ("reqTickByTickData/bid-ask", "reqTickByTickData",
     {"reqId": 86, "contract": AAPL, "tickType": "BidAsk", "numberOfTicks": 50, "ignoreSize": False}),
    ("reqTickByTickData/mid-point", "reqTickByTickData",
     {"reqId": 87, "contract": AAPL, "tickType": "MidPoint", "numberOfTicks": 25, "ignoreSize": True}),
    ("reqTickByTickData/set", "reqTickByTickData",
     {"reqId": 88, "contract": OPTION, "tickType": "BidAsk", "numberOfTicks": 10, "ignoreSize": True}),
    ("cancelTickByTickData/default", "cancelTickByTickData", {"reqId": 0}),
    ("cancelTickByTickData/set", "cancelTickByTickData", {"reqId": 89}),
]

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
    *PLACE_ORDER_CASES,
    *MARKET_DATA_CASES,
]
