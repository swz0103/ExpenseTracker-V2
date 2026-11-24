#!/usr/bin/env python3
"""Mutation runner for the ledger's calculations (see README.md).

Each mutant in mutants.py replaces one exact substring of one file; the
area's tests then run against the changed file:

  KILLED      a test failed (or the run timed out)
  SURVIVED    every test passed: a change no test notices
  EQUIVALENT  listed in mutants.EQUIVALENT: the change cannot alter what
              the code does, so it is left out of the score
  INVALID     the text is not found exactly once, or the change does not
              compile: left out of the score, but reported

An area's score is KILLED / (KILLED + SURVIVED), in whole percent rounded
down. --check holds each area to baseline.json, which only rises
(--update never lowers a figure).

The files are changed in place and put back after each mutant, so run it
on a copy of the repository made with `git archive`, never in a checkout:
a root holding `.git` is refused unless --in-place is given.
"""

import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.dirname(os.path.dirname(HERE))
BASELINE = os.path.join(HERE, 'baseline.json')

COMPILE_ERROR = re.compile(
    r'\.dart:\d+:\d+: Error:|Failed to load|Compilation failed')


def load_catalogue(path):
    spec = importlib.util.spec_from_file_location('mutants', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_tests(root, area, env, timeout):
    """Runs [area]'s tests; returns (exit code or None on timeout, output)."""
    cwd, cmd = area
    try:
        p = subprocess.run(cmd, cwd=os.path.join(root, cwd), env=env,
                           shell=True, capture_output=True, text=True,
                           timeout=timeout)
        return p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        return None, ''


def classify(code, output):
    if code is None:
        return 'KILLED(timeout)'
    if code == 0:
        return 'SURVIVED'
    if COMPILE_ERROR.search(output):
        return 'INVALID(compile)'
    return 'KILLED'


def mutate_one(root, mutant, area, env, timeout):
    """Applies [mutant], runs [area], restores the file; returns the row."""
    mid, area_name, rel, old, new = mutant
    path = os.path.join(root, rel)
    src = open(path, encoding='utf-8').read()
    n = src.count(old)
    if n != 1:
        return mid, area_name, f'{rel}:?', f'INVALID(old occurs {n}x)'
    line = src[:src.index(old)].count('\n') + 1
    try:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(src.replace(old, new, 1))
        code, output = run_tests(root, area, env, timeout)
        result = classify(code, output)
    finally:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(src)
    return mid, area_name, f'{rel}:{line}', result


def read_results(path):
    """{id: (area, result)} from a results file written before."""
    rows = {}
    if os.path.exists(path):
        for line in open(path, encoding='utf-8'):
            parts = line.rstrip('\n').split('\t')
            if len(parts) >= 6:
                rows[parts[0]] = (parts[1], parts[5])
    return rows


def scores(rows):
    """{area: (killed, survived, equivalent, invalid, percent or None)}."""
    by_area = {}
    for area, result in rows.values():
        k, s, e, i = by_area.get(area, (0, 0, 0, 0))
        if result.startswith('KILLED'):
            k += 1
        elif result == 'SURVIVED':
            s += 1
        elif result == 'EQUIVALENT':
            e += 1
        else:
            i += 1
        by_area[area] = (k, s, e, i)
    return {
        a: (k, s, e, i, (k * 100) // (k + s) if k + s else None)
        for a, (k, s, e, i) in by_area.items()
    }


def check(found, baseline):
    """The areas whose score fell below [baseline], and those above it."""
    below, above = [], []
    for area, floor in sorted(baseline.items()):
        score = found.get(area, (0, 0, 0, 0, None))[4]
        if score is None:
            continue
        if score < floor:
            below.append((area, score, floor))
        elif score > floor:
            above.append((area, score, floor))
    return below, above


def raised(found, baseline):
    """[baseline] with each area raised to its score; never lowered."""
    out = dict(baseline)
    for area, row in found.items():
        score = row[4]
        if score is not None and score > out.get(area, -1):
            out[area] = score
    return dict(sorted(out.items()))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--root', default=DEFAULT_ROOT,
                    help='the repository copy to mutate (default: the one '
                         'holding this tool)')
    ap.add_argument('--areas', default='all',
                    help="comma list of areas, or 'all'")
    ap.add_argument('--out', default=None,
                    help='results file (TSV); rows already in it are kept '
                         'and not run again')
    ap.add_argument('--wide', action='store_true',
                    help="run the wide test set (mutants.AREAS_WIDE) for "
                         "each mutant instead of the area's own tests")
    ap.add_argument('--ids', default=None,
                    help='only these mutant ids: a comma list or a file')
    ap.add_argument('--timeout', type=int, default=300,
                    help='seconds per test run; a run past it is a kill')
    ap.add_argument('--catalogue', default=os.path.join(HERE, 'mutants.py'))
    ap.add_argument('--baseline', default=BASELINE)
    ap.add_argument('--check', action='store_true',
                    help='fail when an area scores below the baseline')
    ap.add_argument('--update', action='store_true',
                    help='raise the baseline to the scores found')
    ap.add_argument('--no-pub-get', action='store_true')
    ap.add_argument('--in-place', action='store_true',
                    help='allow a root that is a git checkout')
    args = ap.parse_args(argv)

    root = os.path.abspath(args.root)
    if os.path.exists(os.path.join(root, '.git')) and not args.in_place:
        sys.exit(f'{root} is a git checkout: run on a `git archive` copy '
                 '(see README.md), or pass --in-place.')
    m = load_catalogue(args.catalogue)
    areas = m.AREAS_WIDE if args.wide else m.AREAS
    equivalent = getattr(m, 'EQUIVALENT', {})
    chosen = None if args.areas == 'all' else set(args.areas.split(','))
    unknown = (chosen or set()) - set(m.AREAS)
    if unknown:
        sys.exit(f'unknown areas: {", ".join(sorted(unknown))}')
    only = None
    if args.ids:
        text = (open(args.ids).read() if os.path.exists(args.ids)
                else args.ids.replace(',', ' '))
        only = set(text.split())
    out = args.out or os.path.join(root, 'build', 'mutation', 'results.tsv')
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    done = read_results(out)
    env = dict(os.environ)
    flutter = '/opt/flutter-sdk/flutter/bin'
    if os.path.isdir(flutter):
        env['PATH'] = env.get('PATH', '') + os.pathsep + flutter

    todo = [mu for mu in m.MUTANTS
            if (chosen is None or mu[1] in chosen) and mu[0] not in done
            and (only is None or mu[0] in only)]
    # Each area's tests must pass before anything is changed, or every
    # mutant would count as killed.
    needed = sorted({mu[1] for mu in todo if mu[0] not in equivalent})
    if not args.no_pub_get:
        for cwd in sorted({areas[a][0] for a in needed}):
            tool = 'flutter' if cwd.startswith('apps/') else 'dart'
            subprocess.run(f'{tool} pub get --enforce-lockfile', shell=True,
                           cwd=os.path.join(root, cwd), env=env, check=True,
                           capture_output=True)
    for a in needed:
        code, output = run_tests(root, areas[a], env, args.timeout * 3)
        if code != 0:
            sys.stderr.write(output[-4000:])
            sys.exit(f'the tests of area {a} fail before any mutant')
    with open(out, 'a', encoding='utf-8') as fo:
        for mu in todo:
            mid, area, rel, old, new = mu
            started = time.time()
            if mid in equivalent:
                row = (mid, area, f'{rel}:-', 'EQUIVALENT')
            else:
                row = mutate_one(root, mu, areas[area], env, args.timeout)
            line = '\t'.join([
                row[0], row[1], row[2],
                old.replace('\n', '\\n')[:70], new.replace('\n', '\\n')[:70],
                row[3], f'{time.time() - started:.0f}s'])
            fo.write(line + '\n')
            fo.flush()
            print(line, flush=True)
            done[mid] = (area, row[3])

    found = scores({k: v for k, v in done.items()
                    if chosen is None or v[0] in chosen})
    print('\narea          killed survived equiv invalid score')
    for a in sorted(found):
        k, s, e, i, p = found[a]
        print(f'{a:13} {k:6} {s:8} {e:5} {i:7} '
              f'{"-" if p is None else f"{p}%":>5}')
    survivors = sorted(k for k, v in done.items()
                       if v[1] == 'SURVIVED'
                       and (chosen is None or v[0] in chosen))
    if survivors:
        print('\nsurvived: ' + ' '.join(survivors))

    baseline = (json.load(open(args.baseline))
                if os.path.exists(args.baseline) else {})
    if chosen is not None:
        baseline = {a: v for a, v in baseline.items() if a in chosen}
    status = 0
    if args.check:
        below, above = check(found, baseline)
        for a, s, f in below:
            print(f'::error::mutation score of {a} fell to {s}% '
                  f'(baseline {f}%)')
        for a, s, f in above:
            print(f'{a} rose to {s}% (baseline {f}%): raise the baseline '
                  'with --update')
        status = 1 if below else 0
    if args.update:
        whole = (json.load(open(args.baseline))
                 if os.path.exists(args.baseline) else {})
        whole.update(raised(found, baseline))
        with open(args.baseline, 'w', encoding='utf-8') as f:
            json.dump(dict(sorted(whole.items())), f, indent=2)
            f.write('\n')
    return status


if __name__ == '__main__':
    sys.exit(main())
