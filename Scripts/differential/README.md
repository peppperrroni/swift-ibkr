# Differential oracle

`generate.py` runs `ib_async` 2.1.0 offline and writes its answers to `Tests/IBKRTests/Oracle/decode.json`: for
every frame of `corpus.json`, then every variant of `variants.py` (`gen/<id>/<variant>`) and the canary
(`gen/canary/short-openOrder`), the wrapper callbacks its `Decoder` makes at server version 178, or the exception it
logged. `swift test` reads only the JSON; see CONTRIBUTING «Differential oracle» for the workflow and the allowlist.

```bash
python3.12 -m venv .venv
.venv/bin/pip install -r Scripts/differential/requirements.txt
.venv/bin/python -I Scripts/differential/generate.py               # rewrites decode.json
.venv/bin/python -I Scripts/differential/generate.py --self-test   # the startup checks only, writes nothing
```

- **Offline.** Nothing connects; after `import ib_async`, `socket.socket` becomes a subclass that raises, and so do
  `socket.create_connection`, `socket.socketpair`, asyncio's `create_connection` / `create_server` /
  `create_unix_connection` and `asyncio.open_connection`. The run asserts `socket.socket()` raises.
- **Recording wrapper.** Any method name is recorded; arguments are bound to `ib_async.wrapper.Wrapper`'s signature
  (a short frame raises as the real wrapper would), named after it (`_1`, `_2`, … for the 9 methods `Wrapper`
  lacks). Zone-less execution times read as UTC (`ib.TimezoneTWS = "UTC"`), zones come from the pinned `tzdata`.
- **Canonical form.** Each argument flattens to `{path: string}`: a dataclass to `<path>.<field>`, a list to
  `<path>.#` and `<path>[i]`, `None` to `""`, a bool to `true`/`false`, IB's unset markers (2147483647,
  9223372036854775807, -9223372036854775808, 1.7976931348623157e308, NaN) to `""`, ±∞ to `Infinite`/`-Infinite`, other numbers to plain
  decimal text (`100.0` → `100`), a datetime to epoch seconds.
- **Deterministic.** Corpus order, then variants by id; sorted keys, UTF-8, `\n` line ends. CI regenerates and fails
  on `git diff`.
