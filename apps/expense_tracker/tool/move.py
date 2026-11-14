#!/usr/bin/env python3
"""Moves Dart files within the app and rewrites every import, export and
part directive that names them, in lib/ and test/ and integration_test/.

    python3 tool/move.py lib/src/a/b.dart=lib/src/c/b.dart [...]

Run from apps/expense_tracker. Paths are relative to it; a directory moves
every Dart file under it. Uses git mv so history follows the files.
"""
import os
import re
import subprocess
import sys

ROOT = os.getcwd()
PKG = 'package:expense_tracker/'
DIRECTIVE = re.compile(r"""^(\s*(?:import|export|part(?: of)?)\s+')([^']+)(')""", re.M)


def dart_files():
    for top in ('lib', 'test', 'integration_test', 'test_driver', 'tool'):
        for base, _, names in os.walk(top):
            for n in names:
                if n.endswith('.dart'):
                    yield os.path.normpath(os.path.join(base, n))


def main(pairs):
    moves = {}
    for pair in pairs:
        old, new = pair.split('=')
        old, new = os.path.normpath(old), os.path.normpath(new)
        if os.path.isdir(old):
            for f in dart_files():
                if f.startswith(old + os.sep):
                    moves[f] = os.path.join(new, os.path.relpath(f, old))
        else:
            moves[old] = new
    files = list(dart_files())
    texts = {f: open(f, encoding='utf-8').read() for f in files}

    def target(f, uri):
        if uri.startswith(PKG):
            return os.path.normpath(os.path.join('lib', uri[len(PKG):])), True
        if ':' in uri:
            return None, False
        return os.path.normpath(os.path.join(os.path.dirname(f), uri)), False

    out = {}
    for f, text in texts.items():
        here = moves.get(f, f)

        def fix(m):
            uri = m.group(2)
            path, pkg = target(f, uri)
            if path is None:
                return m.group(0)
            path = moves.get(path, path)
            if pkg:
                return m.group(1) + PKG + os.path.relpath(path, 'lib') + m.group(3)
            rel = os.path.relpath(path, os.path.dirname(here))
            return m.group(1) + rel.replace(os.sep, '/') + m.group(3)

        new = DIRECTIVE.sub(fix, text)
        if new != text or f in moves:
            out[f] = new
    for f, new in out.items():
        open(f, 'w', encoding='utf-8').write(new)
    for old, new in moves.items():
        os.makedirs(os.path.dirname(new), exist_ok=True)
        subprocess.run(['git', 'mv', old, new], check=True)
    print(f'moved {len(moves)} files, rewrote {len(out)}')


if __name__ == '__main__':
    main(sys.argv[1:])
