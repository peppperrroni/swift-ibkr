#!/usr/bin/env python3
"""Lists every public symbol without a doc comment in the given symbol graphs and exits 1 if there is any.

Usage: python3 Scripts/doc-coverage.py .build/symbol-graphs/*.symbols.json
Symbols without a source location (synthesized, inherited) are skipped.
"""
import json
import os
import re
import sys
from urllib.parse import unquote


def source_path(uri):
    # macOS and Linux write file:///Users/..., Windows writes file://C:\Users\...
    path = unquote(uri[len("file://"):] if uri.startswith("file://") else uri)
    if re.match(r"^/[A-Za-z]:", path):
        path = path[1:]
    try:
        path = os.path.relpath(path)
    except ValueError:  # another drive on Windows
        pass
    return path.replace("\\", "/")


def main(paths):
    if not paths:
        sys.exit("usage: doc-coverage.py GRAPH.symbols.json [GRAPH.symbols.json ...]")
    missing = set()
    checked = 0
    for graph_path in paths:
        with open(graph_path, encoding="utf-8") as graph:
            symbols = json.load(graph)["symbols"]
        for symbol in symbols:
            location = symbol.get("location")
            if symbol.get("accessLevel") not in ("public", "open") or not location:
                continue
            checked += 1
            if symbol.get("docComment"):
                continue
            missing.add((source_path(location["uri"]), location["position"]["line"] + 1,
                         symbol["kind"]["identifier"].removeprefix("swift."), ".".join(symbol["pathComponents"])))
    for path, line, kind, name in sorted(missing):
        print(f"{path}:{line} {kind} {name}")
    print(f"checked {checked} public symbols", file=sys.stderr)
    if not checked:  # an empty or wrong graph must not pass the gate vacuously
        print("error: no public symbols found in the given graphs", file=sys.stderr)
        return 1
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
