import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:rules/src/cli.dart';
import 'package:rules/src/config.dart';
import 'package:rules/src/engine.dart';
import 'package:rules/src/ratchet.dart';
import 'package:test/test.dart';

void main() {
  group('compare', () {
    final baseline = {
      'R1': {'a.dart': 2, 'b.dart': 1},
    };

    test('the same counts pass', () {
      final report = compare({
        'R1': {'a.dart': 2, 'b.dart': 1},
      }, baseline);
      expect(report.ok, isTrue);
    });

    test('more violations in a known file fail', () {
      final report = compare({
        'R1': {'a.dart': 3, 'b.dart': 1},
      }, baseline);
      expect(report.growth, hasLength(1));
      expect(report.growth.single, contains('a.dart'));
      expect(report.stale, isEmpty);
    });

    test('a violation in a file not in the baseline fails', () {
      final report = compare({
        'R1': {'a.dart': 2, 'b.dart': 1, 'c.dart': 1},
      }, baseline);
      expect(report.growth.single, contains('c.dart'));
    });

    test('a rule missing from the baseline allows nothing', () {
      final report = compare(
        {
          'R2': {'a.dart': 1},
        },
        baseline,
        rules: {'R2'},
      );
      expect(report.growth, hasLength(1));
    });

    test('fewer violations make the baseline stale', () {
      final report = compare({
        'R1': {'a.dart': 1, 'b.dart': 1},
      }, baseline);
      expect(report.growth, isEmpty);
      expect(report.stale.single, contains('a.dart'));
    });

    test('a file that is clean now makes the baseline stale', () {
      final report = compare({'R1': <String, int>{}}, baseline);
      expect(report.stale, hasLength(2));
    });

    test('limiting to a rule leaves the others alone', () {
      final report = compare(
        {
          'R1': {'a.dart': 2, 'b.dart': 1},
        },
        {
          'R1': {'a.dart': 2, 'b.dart': 1},
          'R2': {'x.dart': 5},
        },
        rules: {'R1'},
      );
      expect(report.ok, isTrue);
    });
  });

  group('update', () {
    test('refuses growth without allowGrowth and keeps the baseline', () {
      final baseline = {
        'R1': {'a.dart': 1},
      };
      final result = update(
        {
          'R1': {'a.dart': 2},
        },
        baseline,
        rules: {'R1'},
      );
      expect(result.refused, isNotEmpty);
      expect(result.baseline, baseline);
    });

    test('accepts growth with allowGrowth', () {
      final result = update(
        {
          'R1': {'a.dart': 2},
        },
        {
          'R1': {'a.dart': 1},
        },
        rules: {'R1'},
        allowGrowth: true,
      );
      expect(result.refused, isEmpty);
      expect(result.baseline['R1'], {'a.dart': 2});
    });

    test('shrinks, and leaves rules it was not asked about', () {
      final result = update(
        {
          'R1': {'a.dart': 1},
        },
        {
          'R1': {'a.dart': 3, 'b.dart': 1},
          'R2': {'z.dart': 4},
        },
        rules: {'R1'},
      );
      expect(result.refused, isEmpty);
      expect(result.baseline['R1'], {'a.dart': 1});
      expect(result.baseline['R2'], {'z.dart': 4});
    });
  });

  group('baseline file', () {
    test('is written sorted, without zero counts, and reads back', () {
      final text = encodeBaseline({
        'B': {'z.dart': 1, 'a.dart': 2, 'gone.dart': 0},
        'A': <String, int>{},
      });
      expect(
        text,
        '{\n  "A": {},\n  "B": {\n    "a.dart": 2,\n    "z.dart": 1\n  }\n}\n',
      );
      expect(decodeBaseline(text), {
        'A': <String, int>{},
        'B': {'a.dart': 2, 'z.dart': 1},
      });
    });

    test('countViolations groups by rule and file', () {
      final counts = countViolations(
        const [
          Violation('R1', 'a.dart', 1, 'm'),
          Violation('R1', 'a.dart', 9, 'm'),
        ],
        ['R1', 'R2'],
      );
      expect(counts, {
        'R1': {'a.dart': 2},
        'R2': <String, int>{},
      });
    });
  });

  group('check command in a scratch repository', () {
    late Directory dir;
    late String root;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('rules_check_');
      root = dir.path;
      for (final d in ['apps', 'packages', 'tooling/rules']) {
        Directory(p.join(root, d)).createSync(recursive: true);
      }
      final part = File(p.join(root, appLib, 'src/x.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync("part 'y.dart';\n");
      expect(part.existsSync(), isTrue);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    int run(List<String> args, StringBuffer out, StringBuffer err) =>
        runCheck(args, root: root, out: out, err: err);

    test(
      'fails without a baseline, then passes after --update --allow-growth',
      () {
        final out = StringBuffer(), err = StringBuffer();
        expect(run(['--rule', 'D2-no-part'], out, err), 1);
        expect(err.toString(), contains('D2-no-part'));

        expect(run(['--update', '--rule', 'D2-no-part'], out, err), 1);
        expect(File(p.join(root, baselineFile)).existsSync(), isFalse);

        expect(
          run(['--update', '--allow-growth', '--rule', 'D2-no-part'], out, err),
          0,
        );
        expect(run(['--rule', 'D2-no-part'], out, err), 0);
      },
    );

    test('a shrunk count is stale until --update', () {
      final out = StringBuffer(), err = StringBuffer();
      run(['--update', '--allow-growth', '--rule', 'D2-no-part'], out, err);
      File(p.join(root, appLib, 'src/x.dart')).writeAsStringSync('');
      final err2 = StringBuffer();
      expect(run(['--rule', 'D2-no-part'], out, err2), 1);
      expect(err2.toString(), contains('--update'));
      expect(run(['--update', '--rule', 'D2-no-part'], out, err2), 0);
      expect(run(['--rule', 'D2-no-part'], out, err2), 0);
    });

    test('a new violation fails even when others are recorded', () {
      final out = StringBuffer(), err = StringBuffer();
      run(['--update', '--allow-growth', '--rule', 'D2-no-part'], out, err);
      File(p.join(root, appLib, 'src/z.dart'))
          .writeAsStringSync("part 'q.dart';\n");
      final err2 = StringBuffer();
      expect(run(['--rule', 'D2-no-part'], out, err2), 1);
      expect(err2.toString(), contains('z.dart'));
    });

    test('--list prints every rule id and --rule rejects an unknown id', () {
      final out = StringBuffer(), err = StringBuffer();
      expect(run(['--list'], out, err), 0);
      expect(out.toString(), contains('A2-feature-isolation'));
      expect(run(['--rule', 'nope'], out, err), 2);
    });
  });
}
