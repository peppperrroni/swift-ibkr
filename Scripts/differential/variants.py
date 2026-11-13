"""Decode variants the generator adds to the corpus, per incoming message id (written from ib_async's decoder.py).

Each entry is (variant name, fields); decode.json names it gen/<id>/<variant>. Variants are not in corpus.json.
"""

VARIANTS: dict[int, list[tuple[str, list[str]]]] = {
    # errorMsg (decoder.py:208-216): advancedOrderRejectJson is read from 166 on, so a frame without it is rejected.
    4: [
        ("with-json", ["4", "2", "7", "201", "Order rejected - reason:", '{"code":"X"}']),
        ("without-json", ["4", "2", "7", "201", "Order rejected - reason:"]),
        ("reqid-minus-one", ["4", "2", "-1", "2104", "Market data farm connection is OK:usfarm", ""]),
        ("unicode-escape", ["4", "2", "-1", "2104", "Caf\\u00e9 farm is OK", ""]),
    ],
    9: [("next-id", ["9", "1", "42"])],
    15: [
        ("one-account", ["15", "1", "DU0000001"]),
        ("three-accounts", ["15", "1", "DU0000001,DU0000002,DU0000003"]),
        ("trailing-comma", ["15", "1", "DU0000001,DU0000002,"]),
    ],
    49: [("time", ["49", "1", "1794321000"])],
    107: [
        ("empty-branding", ["107", "3", ""]),
        ("branding", ["107", "3", "acme"]),
    ],
}

MAX_INT, MAX_DOUBLE = "2147483647", "1.7976931348623157E308"


def _unset(base: list[str], numeric: dict[str, tuple[int, str]]) -> list[tuple[str, list[str]]]:
    """`unset-empty-<name>` and `unset-max-<name>` for every numeric field: "" and IB's sentinel (int or double)."""
    out = []
    for name, (i, kind) in numeric.items():
        for tag, value in (("empty", ""), ("max", MAX_INT if kind == "int" else MAX_DOUBLE)):
            f = list(base)
            f[i] = value
            out.append((f"unset-{tag}-{name}", f))
    return out


def _empty(name: str, base: list[str], index: int) -> tuple[str, list[str]]:
    f = list(base)
    f[index] = ""
    return name, f


# Account and portfolio (decoder.py:56-114 table; updatePortfolio 218-253; position 596-618; positionMulti 620-646).
_CONTRACT = ("265598", "AAPL", "STK", "", "0.0", "", "", "NASDAQ", "USD", "AAPL", "NMS")  # conId … tradingClass
_POSITION = ["61", "3", "DU0000001", *_CONTRACT, "40", "351.5"]
_PORTFOLIO = ["7", "8", "265598", "AAPL", "STK", "", "0.0", "", "", "NASDAQ", "USD", "AAPL", "NMS",
              "5", "187.25", "936.25", "180.5", "33.75", "12.5", "DU0000001"]
_POSITION_MULTI = ["71", "3", "9", "DU0000001", *_CONTRACT, "40", "351.5", "TQQQ"]
_ACCOUNT_VALUE = ["6", "2", "NetLiquidation", "1000000.00", "USD", "DU0000001"]
_SUMMARY = ["63", "1", "9", "DU0000001", "NetLiquidation", "1000000.00", "USD"]
_UPDATE_MULTI = ["73", "1", "9", "DU0000001", "TQQQ", "NetLiquidation", "1000000.00", "USD"]
_PNL = ["94", "9", "-4.97", "-0.93", "-4.04"]
_PNL_SINGLE = ["95", "9", "1", "-4.97", "-0.93", "-4.04", "347.61"]

VARIANTS[6] = [("base", _ACCOUNT_VALUE), _empty("empty-currency", _ACCOUNT_VALUE, 4)]
VARIANTS[7] = [
    ("base", _PORTFOLIO),
    # in 7 the exchange slot is primaryExchange; an empty slot and a different value
    _empty("empty-primary-exchange", _PORTFOLIO, 9),
    ("primary-exchange-isld", [*_PORTFOLIO[:9], "ISLAND", *_PORTFOLIO[10:]]),
    *_unset(_PORTFOLIO, {"conId": (2, "int"), "strike": (6, "double"), "position": (13, "double"),
                         "marketPrice": (14, "double"), "marketValue": (15, "double"),
                         "averageCost": (16, "double"), "unrealizedPNL": (17, "double"),
                         "realizedPNL": (18, "double")}),
]
VARIANTS[8] = [("base", ["8", "1", "09:30"])]
VARIANTS[54] = [("base", ["54", "1", "DU0000001"])]
VARIANTS[61] = [
    ("base", _POSITION),
    ("short", [*_POSITION[:14], "-40", "351.5"]),
    *_unset(_POSITION, {"conId": (3, "int"), "strike": (7, "double"), "position": (14, "double"),
                        "averageCost": (15, "double")}),
]
VARIANTS[62] = [("base", ["62", "1"])]
VARIANTS[63] = [
    ("base", _SUMMARY),
    _empty("empty-currency", _SUMMARY, 6),
    *_unset(_SUMMARY, {"reqId": (2, "int")}),
]
VARIANTS[64] = [("base", ["64", "1", "9"])]
VARIANTS[71] = [
    ("base", _POSITION_MULTI),
    _empty("empty-model", _POSITION_MULTI, 17),
    *_unset(_POSITION_MULTI, {"reqId": (2, "int"), "conId": (4, "int"), "strike": (8, "double"),
                              "position": (15, "double"), "averageCost": (16, "double")}),
]
VARIANTS[72] = [("base", ["72", "1", "9"])]
VARIANTS[73] = [
    ("base", _UPDATE_MULTI),
    _empty("empty-currency", _UPDATE_MULTI, 7),
    _empty("empty-model", _UPDATE_MULTI, 4),
    *_unset(_UPDATE_MULTI, {"reqId": (2, "int")}),
]
VARIANTS[74] = [("base", ["74", "1", "9"])]
VARIANTS[94] = [
    ("base", _PNL),
    ("all-unset-max", ["94", "9", MAX_DOUBLE, MAX_DOUBLE, MAX_DOUBLE]),
    ("all-zero", ["94", "9", "0", "0", "0"]),
    *_unset(_PNL, {"reqId": (1, "int"), "dailyPnL": (2, "double"), "unrealizedPnL": (3, "double"),
                   "realizedPnL": (4, "double")}),
]
VARIANTS[95] = [
    ("base", _PNL_SINGLE),
    ("all-unset-max", ["95", "9", "1", *[MAX_DOUBLE] * 4]),
    ("value-zero", ["95", "9", "1", "-4.97", "-0.93", "-4.04", "0"]),
    ("all-zero", ["95", "9", "0", "0", "0", "0", "0"]),
    *_unset(_PNL_SINGLE, {"reqId": (1, "int"), "pos": (2, "double"), "dailyPnL": (3, "double"),
                          "unrealizedPnL": (4, "double"), "realizedPnL": (5, "double"), "value": (6, "double")}),
]

# Order events (orderStatus 49-53, execDetails 426-475, commissionReport 573-594, orderBound 133 of decoder.py).
_STATUS = ["3", "5", "Submitted", "40", "60", "351.5", "610467324", "0", "351.5", "7", "", "0"]
VARIANTS[3] = [
    ("base", _STATUS),
    ("mkt-cap-price", [*_STATUS[:11], "12.5"]),
    ("why-held", [*_STATUS[:10], "locate", "0"]),
    *_unset(_STATUS, {"orderId": (1, "int"), "filled": (3, "double"), "remaining": (4, "double"),
                      "avgFillPrice": (5, "double"), "permId": (6, "int"), "parentId": (7, "int"),
                      "lastFillPrice": (8, "double"), "clientId": (9, "int"), "mktCapPrice": (11, "double")}),
    ("long-max-permId", [*_STATUS[:6], "9223372036854775807", *_STATUS[7:]]),
    ("without-mkt-cap-price", _STATUS[:11]),  # wrap zips, so ib_async calls with the default mktCapPrice
    ("short-after-status", _STATUS[:3]),
]
_EXEC = ["11", "-1", "5", "265598", "AAPL", "STK", "", "0", "", "", "ISLAND", "USD", "AAPL", "NMS",
         "0000e0d5.6564a7b1.01.01", "20261110-11:56:31", "DU0000001", "ISLAND", "BOT", "40", "351.5", "610467324",
         "7", "0", "40", "351.5", "", "", "", "", "1", "0"]


def _exec(i: int, v: str) -> list[str]:
    f = list(_EXEC)
    f[i] = v
    return f


VARIANTS[11] = [
    ("base", _EXEC),
    ("time-with-zone", _exec(15, "20261110 06:56:31 US/Eastern")),
    ("time-with-utc", _exec(15, "20261110 11:56:31 UTC")),
    ("ev-multiplier", _exec(28, "0.25")),
    ("ev-rule", _exec(27, "Vwap")),
    ("pending-price-revision", _exec(31, "1")),
    ("sold", _exec(18, "SLD")),
    ("bad-time", _exec(15, "yesterday")),
    ("long-max-permId", _exec(21, "9223372036854775807")),
    ("without-pending-price-revision", _EXEC[:31]),
    ("short-after-model-code", _EXEC[:30]),
    ("short-after-exec-id", _EXEC[:15]),
    *_unset(_EXEC, {"orderId": (2, "int"), "conId": (3, "int"), "strike": (7, "double"), "shares": (19, "double"),
                    "price": (20, "double"), "permId": (21, "int"), "clientId": (22, "int"),
                    "liquidation": (23, "int"), "cumQty": (24, "double"), "avgPrice": (25, "double"),
                    "evMultiplier": (28, "double"), "lastLiquidity": (30, "int"),
                    "pendingPriceRevision": (31, "int")}),
]
VARIANTS[53] = [("base", ["53", "1"])]
VARIANTS[55] = [("base", ["55", "1", "9"])]
_COMMISSION = ["59", "1", "0000e0d5.6564a7b1.01.01", "1", "USD", MAX_DOUBLE, MAX_DOUBLE, ""]
VARIANTS[59] = [
    ("base", _COMMISSION),
    ("realized-and-yield", [*_COMMISSION[:5], "-12.5", "0.045", "20271115"]),
    *_unset(_COMMISSION, {"commission": (3, "double"), "realizedPNL": (5, "double"), "yield": (6, "double"),
                          "yieldRedemptionDate": (7, "int")}),
    ("short-after-currency", _COMMISSION[:5]),
]
VARIANTS[100] = [
    ("base", ["100", "610467324", "7", "5"]),
    *_unset(["100", "610467324", "7", "5"], {"permId": (1, "int"), "apiClientId": (2, "int"), "apiOrderId": (3, "int")}),
    ("short", ["100", "610467324"]),
]
VARIANTS[102] = [("base", ["102", "1"])]

# openOrder (decoder.py:882-1147) and completedOrder (1149-1359) at 178, built field by field under ib_async's names
# so each optional group can be switched on and every numeric field set unset. A spec is [(name, kind, value)];
# kinds: I int, D double, F flag, S text, G a gate (a count, presence flag, type or enum text that sizes or refuses
# what follows).
I, D, F, S, G = "int", "double", "flag", "text", "gate"
LONG_MAX, LONG_MIN = "9223372036854775807", "-9223372036854775808"

_ORDER_CONTRACT = [("c.conId", I, "265598"), ("c.symbol", S, "AAPL"), ("c.secType", S, "OPT"),
                   ("c.lastTradeDateOrContractMonth", S, "20261218"), ("c.strike", D, "350"), ("c.right", S, "C"),
                   ("c.multiplier", S, "100"), ("c.exchange", S, "SMART"), ("c.currency", S, "USD"),
                   ("c.localSymbol", S, "AAPL  261218C00350000"), ("c.tradingClass", S, "AAPL")]
_ORDER_HEAD = [("action", G, "BUY"), ("totalQuantity", D, "40"), ("orderType", G, "LMT"), ("lmtPrice", D, "351.5"),
               ("auxPrice", D, "0"), ("tif", S, "DAY"), ("ocaGroup", S, "oca-1"), ("account", S, "DU0000001"),
               ("openClose", S, "O"), ("origin", I, "0"), ("orderRef", S, "ref-1")]
_LEG = [("conId", I, "{n}0001"), ("ratio", I, "1"), ("action", G, "SELL"), ("exchange", S, "SMART"),
        ("openClose", I, "1"), ("shortSaleSlot", I, "1"), ("designatedLocation", S, "loc"), ("exemptCode", I, "2")]
_CONDITIONS = {  # dataclass order after condType (order.py:503-556)
    "price": ("1", [("isMore", F, "1"), ("price", D, "350.25"), ("conId", I, "265598"), ("exch", S, "SMART"),
                    ("triggerMethod", I, "2")]),
    "time": ("3", [("isMore", F, "0"), ("time", S, "20261218 15:30:00 US/Eastern")]),
    "margin": ("4", [("isMore", F, "1"), ("percent", I, "30")]),
    "execution": ("5", [("secType", S, "STK"), ("exch", S, "SMART"), ("symbol", S, "AAPL")]),
    "volume": ("6", [("isMore", F, "1"), ("volume", I, "100000"), ("conId", I, "265598"), ("exch", S, "SMART")]),
    "percent-change": ("7", [("isMore", F, "0"), ("changePercent", D, "2.5"), ("conId", I, "265598"),
                             ("exch", S, "SMART")]),
}
_MARGINS = ["initMarginBefore", "maintMarginBefore", "equityWithLoanBefore", "initMarginChange", "maintMarginChange",
            "equityWithLoanChange", "initMarginAfter", "maintMarginAfter", "equityWithLoanAfter"]


def _order_spec(msg: int, dn=False, legs=0, order_legs=0, smart=0, scale=False, hedge=False, dnc=False, algo=None,
                peg=None, conds=(), conjunctions=None):
    """The spec of one openOrder (5) or completedOrder (101) frame with the named optional groups switched on."""
    o = msg == 5
    head = [("orderType", G, peg) if n == "orderType" and peg else (n, k, v) for n, k, v in _ORDER_HEAD]
    s = [("msgId", G, str(msg))] + ([("orderId", I, "7")] if o else []) + _ORDER_CONTRACT + head
    s += [("clientId", I, "1")] if o else []
    s += [("permId", I, "610467324"), ("outsideRth", F, "1"), ("hidden", F, "0"), ("discretionaryAmt", D, "0.5"),
          ("goodAfterTime", S, "20261110 09:30:00 US/Eastern")]
    s += [("sharesAllocation", S, "")] if o else []
    s += [("faGroup", S, "grp"), ("faMethod", S, "Equal"), ("faPercentage", S, "50"), ("modelCode", S, "model"),
          ("goodTillDate", S, "20261231 16:00:00 US/Eastern"), ("rule80A", S, "I"), ("percentOffset", D, "0.01"),
          ("settlingFirm", S, "firm"), ("shortSaleSlot", I, "1"), ("designatedLocation", S, "loc"),
          ("exemptCode", I, "3")]
    s += [("auctionStrategy", I, "1")] if o else []
    s += [("startingPrice", D, "350.5"), ("stockRefPrice", D, "349.5"), ("delta", D, "0.45"),
          ("stockRangeLower", D, "340"), ("stockRangeUpper", D, "360"), ("displaySize", I, "10")]
    s += [("blockOrder", F, "1")] if o else []
    s += [("sweepToFill", F, "1"), ("allOrNone", F, "1"), ("minQty", I, "5"), ("ocaType", I, "2")]
    if o:
        s += [("eTradeOnly", F, "1"), ("firmQuoteOnly", F, "1"), ("nbboPriceCap", D, "352"), ("parentId", I, "6")]
    s += [("triggerMethod", I, "7"), ("volatility", D, "0.3"), ("volatilityType", I, "2"),
          ("deltaNeutralOrderType", G, "LMT" if dn else ""), ("deltaNeutralAuxPrice", D, "1.5")]
    if dn:
        s += [("deltaNeutralConId", I, "12087792")]
        if o:
            s += [("deltaNeutralSettlingFirm", S, "dnfirm"), ("deltaNeutralClearingAccount", S, "dnacct"),
                  ("deltaNeutralClearingIntent", S, "IB"), ("deltaNeutralOpenClose", S, "O")]
        s += [("deltaNeutralShortSale", F, "1"), ("deltaNeutralShortSaleSlot", I, "2"),
              ("deltaNeutralDesignatedLocation", S, "dnloc")]
    s += [("continuousUpdate", F, "1"), ("referencePriceType", I, "2"), ("trailStopPrice", D, "345"),
          ("trailingPercent", D, "1.5")]
    s += [("basisPoints", D, "0.25"), ("basisPointsType", I, "1")] if o else []
    s += [("comboLegsDescrip", S, "legs" if legs else ""), ("comboLegs.#", G, str(legs))]
    for n in range(legs):
        s += [(f"leg{n}.{k}", kind, v.format(n=n + 1)) for k, kind, v in _LEG]
    s += [("orderComboLegs.#", G, str(order_legs))]
    s += [(f"orderComboLegs[{n}].price", D, f"1.{n + 1}5") for n in range(order_legs)]
    s += [("smartComboRoutingParams.#", G, str(smart))]
    for n in range(smart):
        s += [(f"smart{n}.tag", S, f"NonGuaranteed{n}"), (f"smart{n}.value", S, str(n))]
    s += [("scaleInitLevelSize", I, "100"), ("scaleSubsLevelSize", I, "50"),
          ("scalePriceIncrement", G, "0.05" if scale else "")]
    if scale:
        s += [("scalePriceAdjustValue", D, "0.01"), ("scalePriceAdjustInterval", I, "60"),
              ("scaleProfitOffset", D, "0.2"), ("scaleAutoReset", F, "1"), ("scaleInitPosition", I, "10"),
              ("scaleInitFillQty", I, "5"), ("scaleRandomPercent", F, "1")]
    s += [("hedgeType", G, "D" if hedge else "")] + ([("hedgeParam", S, "0.5")] if hedge else [])
    s += [("optOutSmartRouting", F, "1")] if o else []
    s += [("clearingAccount", S, "clracct"), ("clearingIntent", S, "IB"), ("notHeld", F, "1"),
          ("dncPresent", G, "1" if dnc else "0")]
    s += [("dnc.conId", I, "8314"), ("dnc.delta", D, "0.55"), ("dnc.price", D, "102.5")] if dnc else []
    s += [("algoStrategy", G, "Adaptive" if algo is not None else "")]
    if algo is not None:
        s += [("algoParams.#", G, str(algo))]
        for n in range(algo):
            s += [(f"algo{n}.tag", S, f"adaptivePriority{n}"), (f"algo{n}.value", S, "Normal")]
    s += [("solicited", F, "1")]
    s += [("whatIf", F, "0")] if o else []
    s += [("status", S, "Submitted" if o else "Cancelled")]
    if o:
        s += [(m, S, "") for m in _MARGINS]  # text in ib_async (order.py:310-318), so not swept as numbers
        s += [("commission", D, ""), ("minCommission", D, ""), ("maxCommission", D, ""), ("commissionCurrency", S, ""),
              ("warningText", S, "")]
    s += [("randomizeSize", F, "1"), ("randomizePrice", F, "1")]
    if peg:
        s += [("referenceContractId", I, "13824"), ("isPeggedChangeAmountDecrease", F, "1"),
              ("peggedChangeAmount", D, "0.5"), ("referenceChangeAmount", D, "0.25"), ("referenceExchangeId", S, "NYSE")]
    s += [("conditions.#", G, str(len(conds)))]
    for n, kind in enumerate(conds):
        t, fields = _CONDITIONS[kind]
        s += [(f"cond{n}.condType", G, t), (f"cond{n}.conjunction", G, conjunctions[n] if conjunctions else "a")]
        s += [(f"cond{n}.{k}", fk, v) for k, fk, v in fields]
    if conds:
        s += [("conditionsIgnoreRth", F, "1"), ("conditionsCancelOrder", F, "1")]
    if o:
        s += [("adjustedOrderType", S, "STP"), ("triggerPrice", D, "349"), ("trailStopPrice2", D, "346"),
              ("lmtPriceOffset", D, "0.1"), ("adjustedStopPrice", D, "348"), ("adjustedStopLimitPrice", D, "347.5"),
              ("adjustedTrailingAmount", D, "0.75"), ("adjustableTrailingUnit", I, "1"),
              ("softDollarTier.name", S, "tier"), ("softDollarTier.val", S, "t1"),
              ("softDollarTier.displayName", S, "Tier 1"), ("cashQty", D, "1000"),
              ("dontUseAutoPriceForHedge", F, "1"), ("isOmsContainer", F, "1"),
              ("discretionaryUpToLimitPrice", F, "1"), ("usePriceMgmtAlgo", F, "1"), ("duration", I, "60"),
              ("postToAts", I, "1"), ("autoCancelParent", F, "1")]
    else:
        s += [("trailStopPrice2", D, "346"), ("lmtPriceOffset", D, "0.1"), ("cashQty", D, "1000"),
              ("dontUseAutoPriceForHedge", F, "1"), ("isOmsContainer", F, "1"),
              ("autoCancelDate", S, "20261231"), ("filledQuantity", D, "15"), ("refFuturesConId", I, "4977"),
              ("autoCancelParent", F, "1"), ("shareholder", S, "holder"), ("imbalanceOnly", F, "1"),
              ("routeMarketableToBbo", F, "1"), ("parentPermId", I, "610467320"),
              ("completedTime", S, "20261110 12:46:35 US/Eastern"), ("completedStatus", S, "Cancelled by Trader")]
    s += [("minTradeQty", I, "100"), ("minCompeteSize", I, "100"), ("competeAgainstBestOffset", D, "0.02"),
          ("midOffsetAtWhole", D, "0.01"), ("midOffsetAtHalf", D, "0.005")]
    return s


def _fields(spec, **values) -> list[str]:
    names = [n for n, _, _ in spec]
    assert len(set(names)) == len(names) and set(values) <= set(names), set(values) - set(names)
    return [values.get(n, v) for n, _, v in spec]


def _all(spec, kinds, value) -> list[str]:
    """Every field of `kinds` set to `value` (a string, or a function of the kind)."""
    return [(value(k) if callable(value) else value) if k in kinds else v for _, k, v in spec]


_ALL_CONDS = ("price", "time", "margin", "execution", "volume", "percent-change")
_GATES = ("comboLegs.#", "orderComboLegs.#", "smartComboRoutingParams.#", "conditions.#", "dncPresent",
          "scalePriceIncrement")


def _order_variants(msg: int) -> list[tuple[str, list[str]]]:
    spec = lambda **g: _order_spec(msg, **g)  # noqa: E731
    base = spec()
    full = spec(dn=True, legs=2, order_legs=2, smart=2, scale=True, hedge=True, dnc=True, algo=2, peg="PEG BENCH",
                conds=_ALL_CONDS, conjunctions="aoaoao")
    v = [
        ("base", _fields(base)),
        ("full", _fields(full)),
        ("delta-neutral", _fields(spec(dn=True))),
        ("combo-legs-1", _fields(spec(legs=1, order_legs=1))),
        ("combo-legs-2", _fields(spec(legs=2, order_legs=2))),
        ("combo-legs-2-without-order-legs", _fields(spec(legs=2))),
        ("order-combo-legs-1", _fields(spec(order_legs=1))),
        ("order-combo-leg-prices-unset", _fields(spec(legs=2, order_legs=2), **{
            "orderComboLegs[0].price": "", "orderComboLegs[1].price": MAX_DOUBLE})),
        ("smart-combo-1", _fields(spec(smart=1))),
        ("smart-combo-2", _fields(spec(smart=2))),
        ("scale", _fields(spec(scale=True))),
        ("scale-increment-zero", _fields(base, scalePriceIncrement="0")),
        ("scale-increment-negative", _fields(base, scalePriceIncrement="-0.05")),
        ("hedge", _fields(spec(hedge=True))),
        ("delta-neutral-contract", _fields(spec(dnc=True))),
        ("algo-0", _fields(spec(algo=0))),
        ("algo-1", _fields(spec(algo=1))),
        ("algo-2", _fields(spec(algo=2))),
        ("peg-bench", _fields(spec(peg="PEG BENCH"))),
        ("pegbench", _fields(spec(peg="PEGBENCH"))),
        *[(f"condition-{c}", _fields(spec(conds=(c,)))) for c in _ALL_CONDS],
        ("conditions-and-or", _fields(spec(conds=("price", "volume"), conjunctions="ao"))),
        ("conditions-or-and", _fields(spec(conds=("time", "margin"), conjunctions="oa"))),
        # every numeric field of every group at once: "", IB's MAX for its kind, and the two long sentinels
        ("unset-empty", _all(full, (I, D, F), "")),
        ("unset-max", _all(full, (I, D, F), lambda k: MAX_DOUBLE if k == D else MAX_INT)),
        ("unset-long-max", _all(full, (I, D, F), LONG_MAX)),
        ("unset-long-min", _all(full, (I, D, F), LONG_MIN)),
        ("empty-strings", _all(full, (S,), "")),
        # the gates' own unset values, each on the layout it leaves (no group follows)
        *[(f"unset-{t}-{g}", _fields(base, **{g: x})) for g in _GATES
          for t, x in (("empty", ""), ("max", MAX_DOUBLE if g == "scalePriceIncrement" else MAX_INT))],
        ("unset-empty-algoParams.#", _fields(spec(algo=0), **{"algoParams.#": ""})),
        ("unset-max-algoParams.#", _fields(spec(algo=0), **{"algoParams.#": MAX_INT})),
        ("unset-max-dncPresent-with-contract", _fields(spec(dnc=True), dncPresent=MAX_INT)),
        ("unset-empty-condType", _fields(spec(conds=("margin",)), **{"cond0.condType": ""})),
        ("empty-action", _fields(base, action="")),
        ("empty-leg-action", _fields(spec(legs=1), **{"leg0.action": ""})),
        ("empty-conjunction", _fields(spec(conds=("margin",)), **{"cond0.conjunction": ""})),
        ("short-after-status", _fields(base)[:[n for n, _, _ in base].index("status") + 1]),
        ("without-mid-offset-at-half", _fields(base)[:-1]),
    ]
    if msg == 5:
        v += [
            ("what-if", _fields(base, whatIf="1", status="PreSubmitted", initMarginBefore="12345.60",
                                maintMarginBefore="11000.00", equityWithLoanBefore="1000000.00",
                                initMarginChange="1500.25", maintMarginChange="-1500.25", equityWithLoanChange="0",
                                initMarginAfter="13845.85", maintMarginAfter="9499.75",
                                equityWithLoanAfter="1000000.00", commission="1.00", minCommission="0.35",
                                maxCommission="1.5", commissionCurrency="USD", warningText="margin warning")),
            ("what-if-unset-max", _fields(base, whatIf="1", **{m: MAX_DOUBLE for m in _MARGINS},
                                          commission=MAX_DOUBLE, minCommission=MAX_DOUBLE,
                                          maxCommission=MAX_DOUBLE)),
            ("what-if-unset-long", _fields(base, whatIf="1", **{m: LONG_MAX for m in _MARGINS},
                                           commission=LONG_MAX, minCommission=LONG_MIN, maxCommission=LONG_MAX)),
        ]
    return v


VARIANTS[5] = _order_variants(5)
VARIANTS[101] = _order_variants(101)

# A frame ib_async rejects (openOrder cut after its id): the oracle must record the exception, not «no calls».
CANARY: tuple[str, list[str]] = ("gen/canary/short-openOrder", ["5", "1"])
