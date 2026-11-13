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
        ("openClose", I, "1"), ("shortSaleSlot", I, "2"), ("designatedLocation", S, "loc"), ("exemptCode", I, "4")]
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
    s += [("sweepToFill", F, "0"), ("allOrNone", F, "1"), ("minQty", I, "5"), ("ocaType", I, "2")]
    if o:
        s += [("eTradeOnly", F, "1"), ("firmQuoteOnly", F, "0"), ("nbboPriceCap", D, "352"), ("parentId", I, "6")]
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
    s += [("randomizeSize", F, "1"), ("randomizePrice", F, "0")]
    if peg:
        s += [("referenceContractId", I, "13824"), ("isPeggedChangeAmountDecrease", F, "1"),
              ("peggedChangeAmount", D, "0.5"), ("referenceChangeAmount", D, "0.25"), ("referenceExchangeId", S, "NYSE")]
    s += [("conditions.#", G, str(len(conds)))]
    for n, kind in enumerate(conds):
        t, fields = _CONDITIONS[kind]
        s += [(f"cond{n}.condType", G, t), (f"cond{n}.conjunction", G, conjunctions[n] if conjunctions else "a")]
        s += [(f"cond{n}.{k}", fk, v) for k, fk, v in fields]
    if conds:
        s += [("conditionsIgnoreRth", F, "1"), ("conditionsCancelOrder", F, "0")]
    if o:
        s += [("adjustedOrderType", S, "STP"), ("triggerPrice", D, "349"), ("trailStopPrice2", D, "346"),
              ("lmtPriceOffset", D, "0.1"), ("adjustedStopPrice", D, "348"), ("adjustedStopLimitPrice", D, "347.5"),
              ("adjustedTrailingAmount", D, "0.75"), ("adjustableTrailingUnit", I, "1"),
              ("softDollarTier.name", S, "tier"), ("softDollarTier.val", S, "t1"),
              ("softDollarTier.displayName", S, "Tier 1"), ("cashQty", D, "1000"),
              ("dontUseAutoPriceForHedge", F, "1"), ("isOmsContainer", F, "0"),
              ("discretionaryUpToLimitPrice", F, "1"), ("usePriceMgmtAlgo", F, "0"), ("duration", I, "60"),
              ("postToAts", I, "1"), ("autoCancelParent", F, "0")]
    else:
        s += [("trailStopPrice2", D, "346"), ("lmtPriceOffset", D, "0.1"), ("cashQty", D, "1000"),
              ("dontUseAutoPriceForHedge", F, "1"), ("isOmsContainer", F, "0"),
              ("autoCancelDate", S, "20261231"), ("filledQuantity", D, "15"), ("refFuturesConId", I, "4977"),
              ("autoCancelParent", F, "0"), ("shareholder", S, "holder"), ("imbalanceOnly", F, "1"),
              ("routeMarketableToBbo", F, "0"), ("parentPermId", I, "610467320"),
              ("completedTime", S, "20261110 12:46:35 US/Eastern"), ("completedStatus", S, "Cancelled by Trader")]
    s += [("minTradeQty", I, "100"), ("minCompeteSize", I, "200"), ("competeAgainstBestOffset", D, "0.02"),
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
        # ib_async reads a long sentinel as a float in range (decoder.py:1019-1020), so its scale group follows
        ("unset-long-max-scalePriceIncrement", _fields(spec(scale=True), scalePriceIncrement=LONG_MAX)),
        ("unset-long-min-scalePriceIncrement", _fields(base, scalePriceIncrement=LONG_MIN)),
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

# Market data (wrap table decoder.py:60-141; priceSizeTick 200-206; tickOptionComputation 547-563; deltaNeutralValidation
# 565-571; tickByTick 838-880). Every tick type ib_async's wrapper maps gets a frame of its own (the decoder reads the
# type as a plain int, so they differ only in the number); neighbouring fields of one kind carry distinct values.
from ib_async.wrapper import (  # noqa: E402  (variants.py is imported after ib_async, so the pinned maps are the truth)
    EFP_TICK_MAP, GENERIC_TICK_MAP, GREEKS_TICK_MAP, PRICE_TICK_MAP, RT_VOLUME_TICK_MAP, SIZE_TICK_MAP,
    STRING_TICK_MAP, TIMESTAMP_TICK_MAP)

_INT_FIELDS = {"reqId", "tickType", "tickAttrib", "position", "operation", "side", "isSmartDepth", "time", "count",
               "conId", "snapshotPermissions", "timeStamp", "holdDays", "mask"}
_SENTINELS = (("empty", ""), ("max", MAX_INT), ("max-double", MAX_DOUBLE), ("long-max", LONG_MAX),
              ("long-min", LONG_MIN))


def _unset_all(base: list[str], indices: dict[str, int], prefix: str = "") -> list[tuple[str, list[str]]]:
    """`unset-<sentinel>-<name>` for every sentinel of every named numeric field (empty, MAX, double MAX, long limits)."""
    out = []
    for name, i in indices.items():
        for tag, value in _SENTINELS:
            if tag == "max-double" and name in _INT_FIELDS:  # IB never sends a double's MAX in an int slot
                continue
            f = list(base)
            f[i] = value
            out.append((f"{prefix}unset-{tag}-{name}", f))
    return out


def _at(base: list[str], **at: str) -> list[str]:
    """`base` with the fields at the given indices replaced (`_at(b, i3="x")` sets index 3)."""
    f = list(base)
    for k, v in at.items():
        f[int(k[1:])] = v
    return f


# tickPrice (1): `_, _, reqId, tickType, price, size, _ = fields`, so exactly 7 fields; an empty price makes no call.
_TICK_PRICE = ["1", "6", "7", "1", "351.5", "200", "5"]
_PRICE_TYPES = sorted(set(PRICE_TICK_MAP) | {1, 2, 4, 66, 67, 68})
VARIANTS[1] = [
    ("base", _TICK_PRICE),
    *[(f"price-{k}", _at(_TICK_PRICE, i3=str(k), i4="187.25", i5="100", i6="0")) for k in _PRICE_TYPES],
    *[(f"price-{k}-no-size", _at(_TICK_PRICE, i3=str(k), i4="187.25", i5="0", i6="0")) for k in _PRICE_TYPES],
    *[(f"mask-{m}", _at(_TICK_PRICE, i6=str(m))) for m in (0, 1, 2, 3, 4, 6, 7)],
    ("price-minus-one", _at(_TICK_PRICE, i4="-1", i5="0")),
    ("price-zero", _at(_TICK_PRICE, i4="0", i5="0")),
    ("fractional-size", _at(_TICK_PRICE, i4="351.123456789", i5="0.5")),
    # IB's «no value» price: ib_async makes no call (`if price:`), swift-ibkr yields a tick with a nil price
    *[(f"empty-price-{k}", _at(_TICK_PRICE, i3=str(k), i4="", i5="0")) for k in (1, 2, 4, 6, 66)],
    ("empty-price-with-size", _at(_TICK_PRICE, i4="", i5="100")),
    *_unset_all(_TICK_PRICE, {"reqId": 2, "tickType": 3, "price": 4, "size": 5, "mask": 6}),
    ("short-after-size", _TICK_PRICE[:6]),
    ("short-after-type", _TICK_PRICE[:4]),
]

# tickSize (2), tickGeneric (45), tickString (46): wrap with skip 2, so fields past the last type are ignored.
_SIZE_TYPES = sorted(set(SIZE_TICK_MAP) | {0, 3, 5, 69, 70, 71})
_TICK_SIZE = ["2", "6", "7", "8", "1234567"]
VARIANTS[2] = [
    ("base", _TICK_SIZE),
    *[(f"size-{k}", _at(_TICK_SIZE, i3=str(k))) for k in _SIZE_TYPES],
    ("size-zero", _at(_TICK_SIZE, i4="0")),
    ("fractional-size", _at(_TICK_SIZE, i4="0.5")),
    *_unset_all(_TICK_SIZE, {"reqId": 2, "tickType": 3, "size": 4}),
    ("short-after-type", _TICK_SIZE[:4]),
]
_TICK_GENERIC = ["45", "6", "7", "49", "35.25"]
VARIANTS[45] = [
    ("base", _TICK_GENERIC),
    *[(f"generic-{k}", _at(_TICK_GENERIC, i3=str(k))) for k in sorted(GENERIC_TICK_MAP)],
    ("generic-zero", _at(_TICK_GENERIC, i4="0")),
    *_unset_all(_TICK_GENERIC, {"reqId": 2, "tickType": 3, "value": 4}),
    ("short-after-type", _TICK_GENERIC[:4]),
]
_TICK_STRING = ["46", "6", "7", "32", "ISLAND"]
_RT_VOLUME = "351.5;100;1794321000000;12345;351.2;true"
VARIANTS[46] = [
    ("base", _TICK_STRING),
    *[(f"string-{k}", _at(_TICK_STRING, i3=str(k))) for k in sorted(STRING_TICK_MAP)],
    *[(f"timestamp-{k}", _at(_TICK_STRING, i3=str(k), i4="1794321000")) for k in sorted(TIMESTAMP_TICK_MAP)],
    *[(f"rt-volume-{k}", _at(_TICK_STRING, i3=str(k), i4=_RT_VOLUME)) for k in sorted(RT_VOLUME_TICK_MAP)],
    ("empty-value", _at(_TICK_STRING, i4="")),
    ("empty-rt-volume", _at(_TICK_STRING, i3="48", i4="")),
    ("empty-rt-volume-fields", _at(_TICK_STRING, i3="48", i4=";0;1794321000000;0;;false")),
    *_unset_all(_TICK_STRING, {"reqId": 2, "tickType": 3}),
    ("short-after-type", _TICK_STRING[:4]),
]

# tickOptionComputation (21): no version; `_, reqId, tickType, tickAttrib, *fields = fields` then exactly 8 values, all
# `float(x)` (an empty one raises). The wrapper, not the decoder, turns -1 and -2 into None (wrapper.py:1383-1392).
_GREEKS_TYPES = sorted(GREEKS_TICK_MAP)
_OPTION = ["21", "7", "13", "1", "0.25", "0.55", "6.1", "0.42", "0.03", "0.12", "-0.05", "187.2"]
_OPTION_NAMES = ("impliedVol", "delta", "optPrice", "pvDividend", "gamma", "vega", "theta", "undPrice")


def _option_all(value: str, **at: str) -> dict[str, str]:
    return {f"i{4 + j}": value for j in range(8)} | at


VARIANTS[21] = [
    ("base", _OPTION),
    *[(f"greeks-{k}-attrib-{a}", _at(_OPTION, i2=str(k), i3=str(a))) for k in _GREEKS_TYPES for a in (0, 1)],
    *[(f"greeks-{k}-minus-one", _at(_OPTION, i2=str(k), **_option_all("-1"))) for k in _GREEKS_TYPES],
    *[(f"greeks-{k}-minus-two", _at(_OPTION, i2=str(k), **_option_all("-2"))) for k in _GREEKS_TYPES],
    # one field uncomputed at a time, so a swapped read of two fields fails
    *[(f"{n}-minus-one", _at(_OPTION, **{f"i{4 + j}": "-1"})) for j, n in enumerate(_OPTION_NAMES)],
    *[(f"{n}-minus-two", _at(_OPTION, **{f"i{4 + j}": "-2"})) for j, n in enumerate(_OPTION_NAMES)],
    ("negative-delta", _at(_OPTION, i5="-0.55", i8="-0.03")),
    *_unset_all(_OPTION, {"reqId": 1, "tickType": 2, "tickAttrib": 3, **{n: 4 + j for j, n in enumerate(_OPTION_NAMES)}}),
    ("short-after-und-price", _OPTION[:11]),
    ("short-after-attrib", _OPTION[:4]),
]

# tickEFP (47): the wrapper names the fifth value totalDividends; wrap reads empty numbers as 0.
_EFP = ["47", "1", "7", "38", "1.5", "1.50%", "187.3", "30", "20261218", "0.2", "0.25"]
VARIANTS[47] = [
    ("base", _EFP),
    *[(f"efp-{k}", _at(_EFP, i3=str(k))) for k in sorted(EFP_TICK_MAP)],
    ("empty-strings", _at(_EFP, i5="", i8="")),
    *_unset_all(_EFP, {"reqId": 2, "tickType": 3, "basisPoints": 4, "totalDividends": 6, "holdDays": 7,
                       "dividendImpact": 9, "dividendsToLastTradeDate": 10}),
    ("short-after-impact", _EFP[:10]),
]

# updateMktDepth (12) and updateMktDepthL2 (13): wrap with exact types; isSmartDepth is a bool and has a default.
_DEPTH = ["12", "1", "4", "3", "0", "1", "351.5", "100"]
_DEPTH_L2 = ["13", "1", "4", "3", "NSDQ", "0", "1", "351.6", "50", "1"]
VARIANTS[12] = [
    ("base", _DEPTH),
    *[(f"op-{op}-side-{side}", _at(_DEPTH, i4=str(op), i5=str(side))) for op in (0, 1, 2) for side in (0, 1)],
    ("position-zero", _at(_DEPTH, i3="0")),
    ("fractional-size", _at(_DEPTH, i7="0.5")),
    *_unset_all(_DEPTH, {"reqId": 2, "position": 3, "operation": 4, "side": 5, "price": 6, "size": 7}),
    ("short-after-price", _DEPTH[:7]),
]
VARIANTS[13] = [
    ("base", _DEPTH_L2),
    *[(f"op-{op}-side-{side}-smart-{s}", _at(_DEPTH_L2, i5=str(op), i6=str(side), i9=str(s)))
      for op in (0, 1, 2) for side in (0, 1) for s in (0, 1)],
    ("empty-market-maker", _at(_DEPTH_L2, i4="")),
    ("position-zero", _at(_DEPTH_L2, i3="0")),
    ("fractional-size", _at(_DEPTH_L2, i8="0.5")),
    *_unset_all(_DEPTH_L2, {"reqId": 2, "position": 3, "operation": 5, "side": 6, "price": 7, "size": 8,
                            "isSmartDepth": 9}),
    ("without-is-smart-depth", _DEPTH_L2[:9]),
    ("short-after-price", _DEPTH_L2[:8]),
]

# realtimeBar (50): wrap with skip 2, nine values.
_RT_BAR = ["50", "3", "7", "1794321000", "351.0", "352.0", "350.5", "351.5", "1000", "351.2", "42"]
VARIANTS[50] = [
    ("base", _RT_BAR),
    ("minus-one-midpoint", ["50", "3", "7", "1794321005", "351.0", "352.0", "350.5", "351.5", "-1", "-1", "-1"]),
    ("fractional-volume", _at(_RT_BAR, i8="0.5")),
    *_unset_all(_RT_BAR, {"reqId": 2, "time": 3, "open": 4, "high": 5, "low": 6, "close": 7, "volume": 8, "wap": 9,
                          "count": 10}),
    ("short-after-wap", _RT_BAR[:10]),
]

# deltaNeutralValidation (56): `_, _, reqId, conId, delta, price = fields`, exactly 6; empty delta and price read as 0.
_DNC = ["56", "1", "7", "265598", "0.5", "187.25"]
VARIANTS[56] = [
    ("base", _DNC),
    ("negative-delta", _at(_DNC, i4="-0.5")),
    *_unset_all(_DNC, {"reqId": 2, "conId": 3, "delta": 4, "price": 5}),
    ("short-after-delta", _DNC[:5]),
]
VARIANTS[57] = [("base", ["57", "1", "7"]), *_unset_all(["57", "1", "7"], {"reqId": 2}), ("short", ["57", "1"])]
VARIANTS[58] = [
    *[(f"type-{t}", ["58", "1", "7", str(t)]) for t in (1, 2, 3, 4)],
    *_unset_all(["58", "1", "7", "2"], {"reqId": 2}),
    ("short", ["58", "1", "7"]),
]

# tickReqParams (81) and tickNews (84): wrap with skip 1, no version.
_REQ_PARAMS = ["81", "7", "0.01", "9c0001", "3"]
VARIANTS[81] = [
    ("base", _REQ_PARAMS),
    ("empty-bbo-exchange", _at(_REQ_PARAMS, i3="")),
    *_unset_all(_REQ_PARAMS, {"reqId": 1, "minTick": 2, "snapshotPermissions": 4}),
    ("short-after-bbo", _REQ_PARAMS[:4]),
]
_NEWS = ["84", "7", "1794321000000", "BRFG", "BRFG$12345", "Apple headline", "extra"]
VARIANTS[84] = [
    ("base", _NEWS),
    ("empty-extra-data", _at(_NEWS, i6="")),
    ("empty-strings", _at(_NEWS, i3="", i4="", i5="")),
    *_unset_all(_NEWS, {"reqId": 1, "timeStamp": 2}),
    ("short-after-headline", _NEWS[:6]),
]
_REROUTE = ["91", "7", "12087792", "IDEALPRO"]
VARIANTS[91] = [
    ("base", _REROUTE),
    ("empty-exchange", _at(_REROUTE, i3="")),
    *_unset_all(_REROUTE, {"reqId": 1, "conId": 2}),
    ("short-after-con-id", _REROUTE[:3]),
]
_REROUTE_DEPTH = ["92", "7", "12087792", "IDEALPRO"]
VARIANTS[92] = [
    ("base", _REROUTE_DEPTH),
    ("empty-exchange", _at(_REROUTE_DEPTH, i3="")),
    *_unset_all(_REROUTE_DEPTH, {"reqId": 1, "conId": 2}),
    ("short-after-con-id", _REROUTE_DEPTH[:3]),
]

# tickByTick (99): `_, reqId, tickType, time, *fields`, then exactly 5 (types 1, 2), 5 (type 3) or 1 (type 4) values;
# the masks are read as bool(mask & 1) and bool(mask & 2) for both attribute classes.
_TBT = {
    1: ["99", "7", "1", "1794321000", "351.5", "100", "0", "NASDAQ", "@ I"],
    2: ["99", "7", "2", "1794321001", "351.4", "120", "0", "ARCA", "@ F T"],
    3: ["99", "7", "3", "1794321002", "351.4", "351.6", "300", "200", "0"],
    4: ["99", "7", "4", "1794321003", "351.5"],
}
VARIANTS[99] = [
    *[(f"type-{t}", f) for t, f in _TBT.items()],
    *[(f"type-{t}-mask-{m}", _at(_TBT[t], i6=str(m))) for t in (1, 2) for m in (1, 2, 3, 4)],
    *[(f"type-3-mask-{m}", _at(_TBT[3], i8=str(m))) for m in (1, 2, 3, 4)],
    ("type-1-empty-strings", _at(_TBT[1], i7="", i8="")),
    ("type-2-fractional-size", _at(_TBT[2], i5="0.5")),
    ("type-1-short-after-mask", _TBT[1][:7]),
    ("type-1-short-after-size", _TBT[1][:6]),
    ("type-3-short-after-ask-size", _TBT[3][:8]),
    ("type-4-short", _TBT[4][:3]),
    *_unset_all(_TBT[1], {"reqId": 1, "time": 3, "price": 4, "size": 5, "mask": 6}, "type-1-"),
    *_unset_all(_TBT[3], {"bidPrice": 4, "askPrice": 5, "bidSize": 6, "askSize": 7, "mask": 8}, "type-3-"),
    *_unset_all(_TBT[4], {"midPoint": 4}, "type-4-"),
]

# A value outside IB's documented enum: swift-ibkr is .malformed, ib_async passes it on (or makes no call for 99).
VARIANTS[99] += [
    *[(f"type-{t}-unknown", ["99", "7", str(t), "1794321000", "351.5"]) for t in (0, 5, 9)],
    ("unset-max-tickType", ["99", "7", MAX_INT, "1794321000", "351.5"]),
    ("unset-long-max-tickType", ["99", "7", LONG_MAX, "1794321000", "351.5"]),
]
VARIANTS[58] += [
    *[(f"type-{t}-unknown", ["58", "1", "7", str(t)]) for t in (0, 5)],
    ("unset-empty-type", ["58", "1", "7", ""]),
    ("unset-max-type", ["58", "1", "7", MAX_INT]),
]
VARIANTS[12] += [("operation-3", _at(_DEPTH, i4="3")), ("side-2", _at(_DEPTH, i5="2"))]
VARIANTS[13] += [("operation-3", _at(_DEPTH_L2, i5="3")), ("side-2", _at(_DEPTH_L2, i6="2"))]

# History family (decoder.py:477-511, 757-829, 1361-1370): bars, bar updates, histogram, head timestamp, ticks, schedule.
_INT_FIELDS |= {"barCount", "numBars", "done", "n"}
_BAR = [
    ["1794321000", "351.0", "352.0", "350.5", "351.5", "1000", "351.2", "42"],
    ["1794321060", "351.5", "353.0", "351.0", "352.5", "1200", "352.2", "57"],
    ["1794321120", "352.5", "354.0", "352.0", "353.5", "900", "353.2", "31"],
]
_DAY_BAR = [["20260102", *_BAR[0][1:]], ["20260105", *_BAR[1][1:]], ["20260106", *_BAR[2][1:]]]
_START, _END = "20260101-09:30:00", "20260101-16:00:00"


def _bars(bars: list[list[str]], start: str = _START, end: str = _END) -> list[str]:
    return ["17", "7", start, end, str(len(bars)), *[x for b in bars for x in b]]


_ONE_BAR = _bars(_BAR[:1])
VARIANTS[17] = [
    ("zero-bars", _bars([])),
    ("one-bar", _ONE_BAR),
    ("three-bars", _bars(_BAR)),
    ("one-day-bar", _bars(_DAY_BAR[:1])),
    ("three-day-bars", _bars(_DAY_BAR)),
    ("mixed-bars", _bars([_BAR[0], _DAY_BAR[1], _BAR[2]])),
    ("empty-start-end", _bars(_BAR[:1], start="", end="")),
    ("volume-minus-one", _at(_ONE_BAR, i10="-1")),
    ("average-minus-one", _at(_ONE_BAR, i11="-1")),
    *_unset_all(_ONE_BAR, {"reqId": 1, "numBars": 4, "open": 6, "high": 7, "low": 8, "close": 9, "volume": 10,
                           "average": 11, "barCount": 12}),
    ("bar2-empty-average", _at(_bars(_BAR), i19="")),
    ("bar3-empty-volume", _at(_bars(_BAR), i26="")),
    ("short-after-count", _bars([])[:4]),
    ("short-after-start", _ONE_BAR[:3]),
    ("short-mid-bar", _ONE_BAR[:9]),
    ("short-after-average", _ONE_BAR[:12]),
    ("short-second-bar", _bars(_BAR[:2])[:18]),
]

# historicalDataUpdate (90): barCount first, then date, open, close, high, low, average, volume (`x or 0` reads).
_UPDATE = ["90", "7", "42", "1794321000", "351.0", "351.5", "352.0", "350.5", "351.2", "1000"]
VARIANTS[90] = [
    ("epoch", _UPDATE),
    ("day", _at(_UPDATE, i3="20260102")),
    ("volume-minus-one", _at(_UPDATE, i9="-1")),
    ("average-minus-one", _at(_UPDATE, i8="-1")),
    *_unset_all(_UPDATE, {"reqId": 1, "barCount": 2, "open": 4, "close": 5, "high": 6, "low": 7, "average": 8,
                          "volume": 9}),
    ("short-after-average", _UPDATE[:9]),
    ("short-after-low", _UPDATE[:8]),
    ("short-after-date", _UPDATE[:4]),
]

_HISTOGRAM = ["89", "7", "3", "351.0", "10", "351.5", "25", "352.0", "7"]
VARIANTS[89] = [
    ("zero-items", ["89", "7", "0"]),
    ("one-item", ["89", "7", "1", "351.0", "10"]),
    ("three-items", _HISTOGRAM),
    *_unset_all(["89", "7", "1", "351.0", "10"], {"reqId": 1, "n": 2, "price": 3, "count": 4}),
    ("item2-empty-count", _at(_HISTOGRAM, i6="")),
    ("item3-empty-price", _at(_HISTOGRAM, i7="")),
    ("short-after-count", ["89", "7", "1"]),
    ("short-after-price", _HISTOGRAM[:4]),
    ("short-second-item", _HISTOGRAM[:6]),
]

_HEAD = ["88", "7", "1794321000"]
VARIANTS[88] = [
    ("epoch", _HEAD),
    ("day", _at(_HEAD, i2="20260102")),
    *_unset_all(_HEAD, {"reqId": 1}),
    ("short", _HEAD[:2]),
]

# historicalTicks 96 (time, unused, price, size), 97 (time, mask, bidPrice, askPrice, bidSize, askSize) and 98 (time,
# mask, price, size, exchange, specialConditions), each n times, then done.
_T96 = [["1794321000", "0", "351.5", "100"], ["1794321001", "3", "351.6", "120"], ["1794321002", "0", "351.7", "140"]]
_T97 = [["1794321000", "0", "351.4", "351.6", "300", "200"], ["1794321001", "1", "351.5", "351.7", "310", "210"],
        ["1794321002", "2", "351.6", "351.8", "320", "220"]]
_T98 = [["1794321000", "0", "351.5", "100", "NASDAQ", "@ I"], ["1794321001", "1", "351.6", "120", "ARCA", "@ F T"],
        ["1794321002", "2", "351.7", "140", "ISLAND", "I"]]


def _ticks(msg: str, ticks: list[list[str]], done: str = "1") -> list[str]:
    return [msg, "7", str(len(ticks)), *[x for t in ticks for x in t], done]


def _tick_variants(msg: str, rows: list[list[str]], numeric: dict[str, int]) -> list[tuple[str, list[str]]]:
    width = len(rows[0])
    one, three = _ticks(msg, rows[:1]), _ticks(msg, rows)
    last_number = 3 + 2 * width + max(numeric.values())  # the last number of the third tick
    return [
        ("zero-ticks-done", _ticks(msg, [], "1")),
        ("zero-ticks-not-done", _ticks(msg, [], "0")),
        ("one-tick-done", one),
        ("one-tick-not-done", _ticks(msg, rows[:1], "0")),
        ("three-ticks-done", three),
        ("three-ticks-not-done", _ticks(msg, rows, "0")),
        *_unset_all(one, {"reqId": 1, "n": 2, **{k: 3 + v for k, v in numeric.items()}, "done": 3 + width}),
        ("done-2", _ticks(msg, rows[:1], "2")),
        ("negative-count", [msg, "7", "-1", "1"]),
        ("tick3-empty-last-number", _at(three, **{f"i{last_number}": ""})),
        ("short-after-count", one[:3]),
        ("short-mid-tick", one[:5]),
        ("short-before-done", one[:-1]),
        ("short-second-tick", _ticks(msg, rows[:2])[:3 + width + 2]),
    ]


VARIANTS[96] = _tick_variants("96", _T96, {"time": 0, "price": 2, "size": 3})
VARIANTS[97] = _tick_variants("97", _T97, {"time": 0, "mask": 1, "bidPrice": 2, "askPrice": 3, "bidSize": 4,
                                           "askSize": 5})
VARIANTS[98] = _tick_variants("98", _T98, {"time": 0, "mask": 1, "price": 2, "size": 3})
VARIANTS[96] += [("unused-field-set", _ticks("96", [["1794321000", "7", "351.5", "100"]]))]
VARIANTS[97] += [(f"mask-{m}", _ticks("97", [_at(_T97[0], i1=str(m))])) for m in (1, 2, 3, 4, 7)]
VARIANTS[98] += [
    *[(f"mask-{m}", _ticks("98", [_at(_T98[0], i1=str(m))])) for m in (1, 2, 3, 4, 7)],
    ("empty-special-conditions", _ticks("98", [_at(_T98[0], i5="")])),
    ("empty-exchange", _ticks("98", [_at(_T98[0], i4="")])),
    ("empty-exchange-and-conditions", _ticks("98", [_at(_T98[0], i4="", i5="")])),
    ("tick2-empty-special-conditions", _ticks("98", [_T98[0], _at(_T98[1], i5=""), _T98[2]])),
]

_SESSIONS = [["20260102-14:30:00", "20260102-21:00:00", "20260102"],
             ["20260105-14:30:00", "20260105-21:00:00", "20260105"]]


def _schedule(sessions: list[list[str]], zone: str = "US/Eastern") -> list[str]:
    return ["106", "7", "20260102-14:30:00", "20260106-21:00:00", zone, str(len(sessions)),
            *[x for s in sessions for x in s]]


_SCHEDULE = _schedule(_SESSIONS)
VARIANTS[106] = [
    ("zero-sessions", _schedule([])),
    ("one-session", _schedule(_SESSIONS[:1])),
    ("two-sessions", _SCHEDULE),
    ("empty-time-zone", _schedule(_SESSIONS, "")),
    ("empty-start-end", _at(_SCHEDULE, i2="", i3="")),
    ("empty-session-start", _at(_SCHEDULE, i6="")),
    ("empty-session-end", _at(_SCHEDULE, i7="")),
    ("empty-session-ref-date", _at(_SCHEDULE, i8="")),
    ("session2-empty-end", _at(_SCHEDULE, i10="")),
    *_unset_all(_SCHEDULE, {"reqId": 1, "n": 5}),
    ("short-after-count", _SCHEDULE[:6]),
    ("short-mid-session", _SCHEDULE[:8]),
    ("short-second-session", _SCHEDULE[:11]),
]

# A value outside what IB sends (Disagreements 17): a date that is empty or formatDate-1 text, a negative count.
VARIANTS[17] += [("empty-date", _at(_ONE_BAR, i5="")), ("text-date", _at(_ONE_BAR, i5="20260102  09:30:00")),
                 ("negative-count", ["17", "7", _START, _END, "-1"])]
VARIANTS[90] += [("empty-date", _at(_UPDATE, i3="")), ("text-date", _at(_UPDATE, i3="20260102  09:30:00"))]
VARIANTS[88] += [("empty-date", ["88", "7", ""]), ("text-date", ["88", "7", "20260102  09:30:00"])]
VARIANTS[89] += [("negative-count", ["89", "7", "-1"]), ("negative-item-count", ["89", "7", "1", "351.0", "-3"])]
VARIANTS[106] += [("negative-count", _at(_SCHEDULE, i5="-1"))]

# A frame ib_async rejects (openOrder cut after its id): the oracle must record the exception, not «no calls».
CANARY: tuple[str, list[str]] = ("gen/canary/short-openOrder", ["5", "1"])
