#!/usr/bin/env python3
"""Tests of the mutation runner: python3 tooling/mutation/test_mutate.py"""

import json
import os
import sys
import tempfile
import textwrap
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mutate  # noqa: E402

# A tiny "repository": calc.txt holds the code, and the area's test passes
# while it still says `a + b`; a mutant that breaks the syntax prints what
# a Dart compile error prints.
CATALOGUE = textwrap.dedent('''
    AREAS = {
        'calc': ('.', "grep -q 'a + b' calc.txt && ! grep -q 'oops' calc.txt"
                      " || { grep -q oops calc.txt && echo 'x.dart:1:2: Error: no' ;"
                      " exit 1; }"),
    }
    AREAS_WIDE = AREAS
    EQUIVALENT = {'calc-04': 'a comment only'}
    MUTANTS = [
        ('calc-01', 'calc', 'calc.txt', 'a + b', 'a - b'),
        ('calc-02', 'calc', 'calc.txt', 'x * 2', 'x * 3'),
        ('calc-03', 'calc', 'calc.txt', 'missing', 'gone'),
        ('calc-04', 'calc', 'calc.txt', '# note', '# other'),
        ('calc-05', 'calc', 'calc.txt', 'a + b', 'a + b oops'),
    ]
''')


class RunnerTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.root = os.path.join(self.dir, 'root')
        os.makedirs(self.root)
        with open(os.path.join(self.root, 'calc.txt'), 'w') as f:
            f.write('a + b\nx * 2\n# note\n')
        self.catalogue = os.path.join(self.dir, 'cat.py')
        with open(self.catalogue, 'w') as f:
            f.write(CATALOGUE)
        self.out = os.path.join(self.dir, 'out.tsv')
        self.baseline = os.path.join(self.dir, 'baseline.json')

    def run_tool(self, *extra):
        return mutate.main([
            '--root', self.root, '--catalogue', self.catalogue,
            '--out', self.out, '--baseline', self.baseline,
            '--no-pub-get', *extra])

    def results(self):
        return {k: v[1] for k, v in mutate.read_results(self.out).items()}

    def test_classifies_each_mutant_and_restores_the_file(self):
        self.assertEqual(self.run_tool(), 0)
        self.assertEqual(self.results(), {
            'calc-01': 'KILLED',
            'calc-02': 'SURVIVED',
            'calc-03': 'INVALID(old occurs 0x)',
            'calc-04': 'EQUIVALENT',
            'calc-05': 'INVALID(compile)',
        })
        with open(os.path.join(self.root, 'calc.txt')) as f:
            self.assertEqual(f.read(), 'a + b\nx * 2\n# note\n')

    def test_scores_leave_out_equivalent_and_invalid(self):
        self.run_tool()
        # 1 killed, 1 survived: 1 / 2 = 50%.
        self.assertEqual(mutate.scores(mutate.read_results(self.out)),
                         {'calc': (1, 1, 1, 2, 50)})

    def test_check_fails_below_the_baseline_and_update_only_raises(self):
        with open(self.baseline, 'w') as f:
            json.dump({'calc': 60}, f)
        self.assertEqual(self.run_tool('--check'), 1)
        self.assertEqual(self.run_tool('--update'), 0)
        # 50% found, 60% kept: the baseline never goes down.
        self.assertEqual(mutate.read_json(self.baseline), {'calc': 60})
        with open(self.baseline, 'w') as f:
            json.dump({'calc': 40}, f)
        self.assertEqual(self.run_tool('--check', '--update'), 0)
        self.assertEqual(mutate.read_json(self.baseline), {'calc': 50})

    def test_rows_already_written_are_not_run_again(self):
        with open(self.out, 'w') as f:
            f.write('calc-02\tcalc\tcalc.txt:2\tx\ty\tKILLED\t0s\n')
        self.run_tool()
        self.assertEqual(self.results()['calc-02'], 'KILLED')

    def test_a_git_checkout_is_refused(self):
        os.makedirs(os.path.join(self.root, '.git'))
        with self.assertRaises(SystemExit):
            self.run_tool()

    def test_an_area_failing_before_any_mutant_stops_the_run(self):
        with open(os.path.join(self.root, 'calc.txt'), 'w') as f:
            f.write('a - b\nx * 2\n# note\n')
        with self.assertRaises(SystemExit):
            self.run_tool()


if __name__ == '__main__':
    unittest.main()
