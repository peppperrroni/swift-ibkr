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

# A frame ib_async rejects (openOrder cut after its id): the oracle must record the exception, not «no calls».
CANARY: tuple[str, list[str]] = ("gen/canary/short-openOrder", ["5", "1"])
