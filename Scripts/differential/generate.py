"""Differential oracle: run ib_async 2.1.0 offline; write decode.json (its Decoder over every corpus frame) and
encode.json (what its Client sends for every case of cases.py).

Run with `python -I Scripts/differential/generate.py` (`--self-test` runs the startup checks and writes nothing).
Network-free by construction: nothing connects, and every socket factory raises (docs/DECISIONS.md, the oracle row).
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # -I leaves the script's directory off sys.path
sys.dont_write_bytecode = True  # no __pycache__ beside variants.py in the working tree

import asyncio
import dataclasses
import datetime
import importlib.metadata
import inspect
import json
import logging
import math
import socket
import types
import zoneinfo
from decimal import Decimal

zoneinfo.reset_tzpath(to=[])  # zones from the pinned tzdata package, never the OS's copy: Windows and CI agree

import ib_async  # noqa: F401  (imported before the guard: asyncio's ssl subclasses socket.socket at import)
from ib_async.client import Client
from ib_async.decoder import Decoder
from ib_async.wrapper import Wrapper

SERVER_VERSION = 178
ORACLE = os.path.join(HERE, "..", "..", "Tests", "IBKRTests", "Oracle")


# --- network guard (C3) -------------------------------------------------------------------------------------------

def _refuse(*_args, **_kwargs):
    raise RuntimeError("the oracle never touches the network")


class _NoSocket(socket.socket):
    def __init__(self, *_args, **_kwargs):
        _refuse()


socket.socket = _NoSocket
socket.create_connection = _refuse
socket.socketpair = _refuse
for _name in ("create_connection", "create_server", "create_unix_connection"):
    setattr(asyncio.BaseEventLoop, _name, _refuse)
asyncio.open_connection = _refuse

from cases import CASES, CLIENT_ATTRS  # noqa: E402  (after the guard: cases.py decodes a recorded frame at import)
from variants import CANARY, VARIANTS  # noqa: E402


# --- canonical form (decision 5) ----------------------------------------------------------------------------------

UNSET_INTS = {2147483647, 9223372036854775807, -9223372036854775808}
UNSET_DOUBLE = 1.7976931348623157e308


def canon(value):
    """A scalar's canonical string; a dataclass, list, tuple or set flattens to a dict of paths."""
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return "" if value in UNSET_INTS else str(value)
    if isinstance(value, float):
        if value == UNSET_DOUBLE or math.isnan(value):
            return ""
        if math.isinf(value):
            return "Infinite" if value > 0 else "-Infinite"
        text = format(Decimal(repr(value)).normalize(), "f")
        return "0" if text == "-0" else text
    if isinstance(value, datetime.datetime):
        if value.tzinfo is None:
            raise TypeError(f"naive datetime {value!r} would depend on the machine's zone")
        return canon(value.timestamp())
    if dataclasses.is_dataclass(value) or isinstance(value, (list, tuple, set, frozenset)):
        return flatten("", value)
    raise TypeError(f"no canonical form for {type(value).__name__}: {value!r}")


def flatten(prefix, value):
    """`{path: canonical string}` for one argument: `<path>.<field>`, `<path>.#` and `<path>[i]`."""
    if dataclasses.is_dataclass(value) and not isinstance(value, type):
        out = {}
        for f in dataclasses.fields(value):
            out.update(flatten(f"{prefix}.{f.name}" if prefix else f.name, getattr(value, f.name)))
        return out
    if isinstance(value, (set, frozenset)):
        value = sorted(value)
    if isinstance(value, (list, tuple)):
        out = {f"{prefix}.#" if prefix else "#": str(len(value))}
        for i, v in enumerate(value):
            out.update(flatten(f"{prefix}[{i}]", v))
        return out
    return {prefix: canon(value)}


# --- recording wrapper (decision 3, P1, P9) -----------------------------------------------------------------------

class Recorder:
    """Records every wrapper call; a call that does not fit `Wrapper`'s signature raises as the real one would."""

    def __init__(self):
        self.calls = []
        self.defaultTimezone = datetime.timezone.utc
        self.ib = types.SimpleNamespace(TimezoneTWS="UTC")  # zone-less execution times read as UTC (P1)

    def __getattr__(self, name):
        if name.startswith("__"):
            raise AttributeError(name)
        target = getattr(Wrapper, name, None)

        def method(*args):
            if target is None:  # the 9 methods Wrapper lacks: no signature to check
                names = [f"_{i + 1}" for i in range(len(args))]
                self.calls.append((name, list(zip(names, args))))
                return
            bound = inspect.signature(target).bind(None, *args)
            bound.apply_defaults()
            self.calls.append((name, list(bound.arguments.items())[1:]))

        return method


class _Errors(logging.Handler):
    def __init__(self):
        super().__init__(logging.DEBUG)
        self.errors = []

    def emit(self, record):
        exc = record.exc_info[1] if record.exc_info else None
        # `wrap`'s except formats `args`, unbound when building them failed (decoder.py:150-172): keep that cause only
        if isinstance(exc, UnboundLocalError) and "'args'" in str(exc) and exc.__context__ is not None:
            exc = exc.__context__
        if exc is None:
            self.errors.append(record.getMessage())
        elif isinstance(exc, OSError):  # errno and strerror are the platform's (Windows 22, Linux 75): the type alone
            self.errors.append(type(exc).__name__)
        else:
            self.errors.append(f"{type(exc).__name__}: {exc}")


_errors = _Errors()
_logger = logging.getLogger("ib_async.Decoder")
_logger.addHandler(_errors)
_logger.setLevel(logging.DEBUG)
_logger.propagate = False


def record(fields):
    """ib_async's answer for one frame: `{"calls": [...]}`, or `{"error": message}` if its decoder logged one."""
    wrapper = Recorder()
    _errors.errors.clear()
    Decoder(wrapper, SERVER_VERSION).interpret(list(fields))
    if _errors.errors:
        return {"error": _errors.errors[0]}
    calls = []
    for method, arguments in wrapper.calls:
        args = {}
        for name, value in arguments:
            args.update(flatten(name, value))
        calls.append({"method": method, "args": args})
    return {"calls": calls}


# --- encode capture (decisions 9, 10; C3, P2, P15) ------------------------------------------------------------------

def case_value(value):
    """An argument as encode.json holds it: scalars as strings (float as repr), None as null, a dataclass as an object
    of all its fields plus `_type`, a list as an array."""
    if value is None:
        return None
    if isinstance(value, str):
        return value
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, (datetime.datetime, datetime.date)):  # P2: ib.py formats dates before the Client sees them
        raise TypeError(f"{value!r}: pass the text ib.py would send, through cases.ib_datetime")
    if dataclasses.is_dataclass(value) and not isinstance(value, type):
        out = {f.name: case_value(getattr(value, f.name)) for f in dataclasses.fields(value)}
        out["_type"] = type(value).__name__
        return out
    if isinstance(value, (list, tuple)):
        return [case_value(v) for v in value]
    raise TypeError(f"no case form for {type(value).__name__}: {value!r}")


def encode(name, method, kwargs):
    """The case as encode.json holds it: every argument (defaults included) and the fields the Client sent."""
    sent = []
    client = Client(Recorder())
    client._serverVersion = SERVER_VERSION
    client.connState = Client.CONNECTED  # send() refuses otherwise (client.py:250-251); nothing is connected
    client.sendMsg = sent.append  # send() ends in self.sendMsg(generated) (client.py:321)
    kwargs = dict(kwargs)
    for attr, value in kwargs.pop("_client", {}).items():
        assert attr in CLIENT_ATTRS.get(method, ()), f"{name}: {method} does not read Client.{attr}"
        setattr(client, attr, value)
    bound = inspect.signature(getattr(Client, method)).bind(client, **kwargs)
    bound.apply_defaults()
    # before the call: placeOrder clears a non-VOL order's volatility in place (client.py:480-482)
    args = {k: case_value(v) for k, v in list(bound.arguments.items())[1:]}
    getattr(client, method)(**kwargs)
    assert len(sent) == 1 and sent[0].endswith("\0"), f"{name}: expected one message, got {sent!r}"
    if method in CLIENT_ATTRS:
        args["_client"] = {a: case_value(getattr(client, a)) for a in CLIENT_ATTRS[method]}
    return {"name": name, "method": method, "args": args, "fields": sent[0].split("\0")[:-1]}


# --- I/O (decisions 6, 13) ----------------------------------------------------------------------------------------

def self_test():
    try:
        socket.socket()
    except RuntimeError:
        pass
    else:
        raise AssertionError("socket.socket() must raise")
    assert canon(100.0) == "100"
    assert canon(1e-05) == "0.00001"
    assert canon(1.7976931348623157e308) == ""
    assert canon(2147483647) == ""
    assert canon(True) == "true"
    assert canon(-0.0) == "0"
    assert importlib.metadata.version("ib_async") == "2.1.0"
    assert "error" in record(CANARY[1]), "a frame ib_async rejects must come out as an error"
    assert encode("check", "cancelOrder", {"orderId": 5})["fields"] == ["4", "1", "5", ""]


def main():
    self_test()
    if "--self-test" in sys.argv[1:]:
        return
    with open(os.path.join(ORACLE, "corpus.json"), encoding="utf-8", newline="\n") as f:
        corpus = json.load(f)
    assert len({c["name"] for c in corpus}) == len(corpus), "corpus names must be unique"
    assert len({json.dumps(c["fields"]) for c in corpus}) == len(corpus), "corpus frames must be unique"
    frames = [(c["name"], c["fields"]) for c in corpus]
    frames += [(f"gen/{i}/{name}", fields) for i in sorted(VARIANTS) for name, fields in VARIANTS[i]]
    frames.append(CANARY)
    out = {
        "ibAsync": importlib.metadata.version("ib_async"),
        "serverVersion": SERVER_VERSION,
        "handlers": sorted(Decoder(Recorder(), SERVER_VERSION).handlers),
        "frames": [{"name": name, "fields": fields, **record(fields)} for name, fields in frames],
    }
    assert len({c[0] for c in CASES}) == len(CASES), "case names must be unique"
    encoded = {"cases": [encode(*c) for c in CASES]}
    for file, value in (("decode.json", out), ("encode.json", encoded)):
        with open(os.path.join(ORACLE, file), "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(value, indent=1, sort_keys=True, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
