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

# A frame ib_async rejects (openOrder cut after its id): the oracle must record the exception, not «no calls».
CANARY: tuple[str, list[str]] = ("gen/canary/short-openOrder", ["5", "1"])
