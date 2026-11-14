#!/usr/bin/env python3
"""Splits a long Dart file: moves its last top-level declarations into
`part` files of the same library, each under the limit, named after the
first declaration it holds. Behaviour is unchanged: parts share the
library's imports and privacy.

    python3 tool/split.py lib/src/x/y.dart [limit=600]

Run from apps/expense_tracker. A file that is itself a part sends the new
parts to its library, which gets the `part` lines.
"""
import os
import re
import subprocess
import sys

DECL = re.compile(r'^(?:@|///|(?:abstract |final |sealed |base |interface |mixin )*'
                  r'(?:class|enum|extension|typedef|mixin)\b|[A-Za-z_<(][^=;]*[({=])')


def snake(name):
    name = name.lstrip('_')
    return re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()


def declarations(lines, start):
    """(begin, end, name) of each top-level declaration from [start]."""
    out = []
    i = start
    n = len(lines)
    while i < n:
        line = lines[i]
        if not line.strip() or line.startswith('//') and not line.startswith('///'):
            i += 1
            continue
        if line[0].isspace() or line.startswith('}'):
            i += 1
            continue
        begin = i
        while i < n and (lines[i].startswith('///') or lines[i].startswith('@')):
            i += 1
        head = lines[i] if i < n else ''
        m = re.search(r'(?:class|enum|extension|typedef|mixin)\s+(\w+)', head) or \
            re.search(r'(\w+)\s*[(<=]', head)
        name = m.group(1) if m else 'part'
        # Find the end: braces balanced, or a ';' at depth 0.
        depth = 0
        seen = False
        j = i
        while j < n:
            code = re.sub(r"'(?:\\.|[^'])*'|\"(?:\\.|[^\"])*\"|//.*", '', lines[j])
            depth += code.count('{') + code.count('(') + code.count('[')
            depth -= code.count('}') + code.count(')') + code.count(']')
            seen = seen or bool(re.search(r'[{(\[]', code))
            if depth <= 0 and (code.rstrip().endswith(';') or code.rstrip().endswith('}')) and (seen or ';' in code):
                break
            j += 1
        out.append((begin, j + 1, name))
        i = j + 1
    return out


def main(path, limit=600):
    text = open(path, encoding='utf-8').read()
    lines = text.split('\n')
    if len(lines) <= limit:
        return
    m = re.search(r"^part of '([^']+)';", text, re.M)
    library = os.path.normpath(os.path.join(os.path.dirname(path), m.group(1))) if m else path
    # The header: directives and the comments right under them.
    start = 0
    for k, line in enumerate(lines):
        if re.match(r"^(import|export|part|library)\b", line) or not line.strip() \
                or (line.startswith('//') and not line.startswith('///')):
            start = k + 1
            continue
        break
    decls = declarations(lines, start)
    keep_end = len(lines)
    chunks = []
    current = []
    size = 0
    # Take declarations from the end until what is left fits.
    for begin, end, name in reversed(decls):
        if keep_end <= limit:
            break
        span = end - begin
        if size + span > limit - 8 and current:
            chunks.append(current)
            current, size = [], 0
        current.insert(0, (begin, end, name))
        size += span
        keep_end = begin
    if current:
        chunks.append(current)
    if not chunks:
        return
    base = os.path.splitext(os.path.basename(library))[0]
    folder = os.path.dirname(path)
    rel_lib = os.path.relpath(library, folder).replace(os.sep, '/')
    made = []
    for chunk in reversed(chunks):
        first = chunk[0][2]
        stem = snake(first)
        name = f'{base}_{stem}.dart' if not stem.startswith(base) else f'{stem}.dart'
        target = os.path.join(folder, name)
        k = 2
        while os.path.exists(target):
            target = os.path.join(folder, f'{base}_{stem}_{k}.dart')
            k += 1
        body = '\n'.join(lines[chunk[0][0]:chunk[-1][1]]).strip('\n')
        open(target, 'w', encoding='utf-8').write(f"part of '{rel_lib}';\n\n{body}\n")
        made.append(target)
    rest = '\n'.join(lines[:keep_end]).rstrip('\n') + '\n'
    open(path, 'w', encoding='utf-8').write(rest)
    lib_text = open(library, encoding='utf-8').read()
    directives = ''.join(
        f"part '{os.path.relpath(t, os.path.dirname(library)).replace(os.sep, '/')}';\n" for t in made)
    parts = list(re.finditer(r"^part '[^']+';\n", lib_text, re.M))
    if parts:
        at = parts[-1].end()
    else:
        imports = list(re.finditer(r"^(import|export) [^;]+;\n", lib_text, re.M))
        at = imports[-1].end() if imports else 0
        directives = '\n' + directives
    lib_text = lib_text[:at] + directives + lib_text[at:]
    open(library, 'w', encoding='utf-8').write(lib_text)
    for t in made:
        subprocess.run(['git', 'add', t])
    print(path, '->', ', '.join(os.path.basename(t) for t in made))


if __name__ == '__main__':
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 600)
