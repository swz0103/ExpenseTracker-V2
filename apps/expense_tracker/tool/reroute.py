#!/usr/bin/env python3
"""Moves call sites to a member's new home, as the analyzer finds them.

After a member leaves a class (say `Ledger.balance` moved to
`Ledger.balanceService.balance`), every call to it is an analyzer error
that names the member, the file, the line and the column. This tool reads
those errors and rewrites each call in place, so no call site is guessed by
pattern: a receiver named `ledger`, `widget.ledger`, `l` or an implicit
`this` is all the same to it.

    tool/reroute.py --type Ledger --map routes.json [--reader Reader ...]

`routes.json` maps a member name to what replaces it, as a path from the
same receiver: {"balance": "balanceService.balance",
"entriesIn": "entries.inMonth"}.

With `--reader`, a value of a type ending in that name that is used as a
list (iterated, spread, passed where a List is expected, or asked for a
List member) gets `.all` appended: `ledger.accounts.where(...)` becomes
`ledger.accounts.all.where(...)`.

It repeats until the analyzer reports nothing it can mend, at most ten
times, and prints what is left.
"""

import argparse
import json
import re
import subprocess
import sys
from collections import defaultdict

UNDEFINED = re.compile(
    r"The (?:method|getter|setter|operator) '([^']+)' isn't defined for the "
    r"type '([^']+)'"
)
UNDEFINED_NAME = re.compile(
    r"(?:Undefined name|The function) '([^']+)'(?: isn't defined)?"
)


def analyze(paths):
    out = subprocess.run(
        ["dart", "analyze", "--format=machine", *paths],
        capture_output=True,
        text=True,
    )
    rows = []
    for line in out.stdout.splitlines() + out.stderr.splitlines():
        parts = line.split("|", 7)
        if len(parts) != 8 or parts[0] != "ERROR":
            continue
        _, _, code, path, row, col, length, message = parts
        rows.append((code, path, int(row), int(col), int(length), message))
    return rows


def utf16_to_index(text, units):
    """The str index of the UTF-16 offset [units] in [text]."""
    count = 0
    for i, ch in enumerate(text):
        if count >= units:
            return i
        count += 2 if ord(ch) > 0xFFFF else 1
    return len(text)


def plan(rows, owner, routes, readers, extensions=()):
    edits = defaultdict(list)  # path -> [(line, col, length, kind, text)]
    for code, path, row, col, length, message in rows:
        found = UNDEFINED.search(message)
        if found:
            member, on = found.groups()
            if (on == owner or on.startswith(owner) or on in extensions) and (
                member in routes
            ):
                edits[path].append((row, col, length, "replace", routes[member]))
                continue
            if any(on.endswith(r) for r in readers):
                # `x[i]` reads `x.all[i]`; `x.m` reads `x.all.m`.
                text = ".all" if member.startswith("[]") else "all."
                edits[path].append((row, col, 0, "insert", text))
                continue
        named = UNDEFINED_NAME.search(message)
        if named and named.group(1) in routes and "/core/ledger/" in path:
            # An implicit `this` inside the ledger's own files.
            edits[path].append((row, col, length, "replace", routes[named.group(1)]))
            continue
        if code == "NOT_ITERABLE_SPREAD" and readers:
            # The message names no type: a spread of a reader property.
            edits[path].append((row, col + length, 0, "insert", ".all"))
            continue
        if any(f"'{r}" in message or r + "'" in message for r in readers):
            mentioned = re.findall(r"'([A-Za-z]*Reader)'", message)
            if mentioned and any(m.endswith(r) for m in mentioned for r in readers):
                edits[path].append((row, col + length, 0, "insert", ".all"))
    return edits


def apply(edits):
    changed = 0
    for path, items in edits.items():
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
        seen = set()
        for row, col, length, kind, text in sorted(items, reverse=True):
            if (row, col, kind) in seen:
                continue
            seen.add((row, col, kind))
            line = lines[row - 1]
            start = utf16_to_index(line, col - 1)
            end = utf16_to_index(line, col - 1 + length)
            lines[row - 1] = line[:start] + text + line[end:]
            changed += 1
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
    return changed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--type", required=True)
    parser.add_argument("--map", required=True)
    parser.add_argument("--reader", action="append", default=[])
    parser.add_argument("--extension", action="append", default=[])
    parser.add_argument("paths", nargs="*", default=["lib", "test"])
    args = parser.parse_args()
    with open(args.map, encoding="utf-8") as f:
        routes = json.load(f)
    for round_ in range(10):
        rows = analyze(args.paths)
        edits = plan(rows, args.type, routes, args.reader, args.extension)
        if not edits:
            break
        print(f"round {round_ + 1}: {apply(edits)} call sites", file=sys.stderr)
    left = analyze(args.paths)
    for code, path, row, col, _, message in left:
        print(f"{path}:{row}:{col} {code} {message}")
    return 1 if left else 0


if __name__ == "__main__":
    sys.exit(main())
