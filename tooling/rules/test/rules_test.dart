import 'package:rules/src/engine.dart';
import 'package:rules/src/registry.dart';
import 'package:rules/src/rules/imports.dart';
import 'package:rules/src/rules/structure.dart';
import 'package:rules/src/rules/usage.dart';
import 'package:test/test.dart';

const _app = 'apps/expense_tracker/lib';
const _feat = '$_app/src/features';

List<Violation> run(Rule rule, Map<String, String> sources) =>
    rule.check(Project(sources));

void main() {
  test('the registry has the nine rules with unique ids', () {
    final ids = [for (final r in allRules) r.id];
    expect(ids.toSet(), hasLength(9));
    expect(
      ids,
      containsAll([
        'A2-feature-isolation',
        'A3-ui-no-data',
        'A4-pure-calc',
        'B2-number-format',
        'B3-clock',
        'B9-text-literals',
        'D2-no-part',
        'E1-catch-handled',
        'C1-tests-exist',
      ]),
    );
  });

  group('A2-feature-isolation', () {
    const rule = FeatureIsolation();
    test('flags relative and package imports of another feature', () {
      final v = run(rule, {
        '$_feat/a/ui/page.dart':
            "import '../../b/model/x.dart';\n"
            "import 'package:expense_tracker/src/features/c/y.dart';\n",
      });
      expect(v, hasLength(2));
      expect(v.first.line, 1);
    });
    test('passes own feature, core and other packages', () {
      expect(
        run(rule, {
          '$_feat/a/ui/page.dart':
              "import '../model/x.dart';\n"
              "import '../../../core/design_system/theme.dart';\n"
              "import 'package:flutter/material.dart';\n"
              "import 'dart:async';\n",
        }),
        isEmpty,
      );
    });
  });

  group('A3-ui-no-data', () {
    const rule = UiNoData();
    test('flags data packages and data folders', () {
      final v = run(rule, {
        '$_feat/a/ui/page.dart':
            "import 'package:vault/ledger_vault.dart';\n"
            "import 'package:storage/storage.dart';\n"
            "import '../../../app/android/file_adapter.dart';\n"
            "import '../../../core/ledger/persistence/write_queue.dart';\n",
      });
      expect(v, hasLength(4));
    });
    test('passes core imports and files outside features', () {
      expect(
        run(rule, {
          '$_feat/a/ui/page.dart':
              "import '../../../core/ledger/ledger.dart';\n",
          '$_app/src/app/x.dart': "import 'package:vault/ledger_vault.dart';\n",
        }),
        isEmpty,
      );
    });
  });

  group('A4-pure-calc', () {
    const rule = PureCalc();
    test('flags impure imports and hidden inputs', () {
      final v = run(rule, {
        'packages/core/lib/src/a.dart':
            "import 'package:flutter/foundation.dart';\n"
            "import 'dart:io';\n"
            'final a = DateTime.now();\n'
            'final b = Stopwatch();\n'
            'final c = Random(3);\n'
            'final d = new DateTime.now();\n',
        'packages/domain/lib/src/b.dart': "import 'dart:ui';\n",
      });
      expect(v, hasLength(7));
    });
    test('passes pure code, the clock file and tests', () {
      expect(
        run(rule, {
          'packages/core/lib/src/a.dart':
              "import 'dart:math';\nint f(DateTime d) => d.year;\n",
          'packages/core/lib/time/clock.dart':
              'final a = DateTime.now();\n',
          'packages/core/test/a_test.dart': 'final a = DateTime.now();\n',
        }),
        isEmpty,
      );
    });
  });

  group('B2-number-format', () {
    const rule = NumberFormat();
    test('flags formatting and parsing by hand', () {
      final v = run(rule, {
        '$_app/src/features/a/x.dart': '''
void f(double d, String s) {
  d.toStringAsFixed(2);
  d.toStringAsPrecision(3);
  int.parse(s);
  int.tryParse(s);
  double.parse(s);
  double.tryParse(s);
  num.parse(s);
  num.tryParse(s);
}
''',
      });
      expect(v, hasLength(8));
    });
    test('the old formatting folder is no longer an owner', () {
      expect(
        run(rule, {
          '$_app/src/core/formatting/a.dart':
              'void f(String s) { int.parse(s); }\n',
        }),
        hasLength(1),
      );
    });
    test('passes the owners and other parse calls', () {
      expect(
        run(rule, {
          '$_app/design_system/display/a.dart':
              'void f(String s) { int.parse(s); }\n',
          '$_app/src/features/a/x.dart':
              'void f(String s) { DateTime.parse(s); s.trim(); }\n',
          'packages/core/lib/src/a.dart':
              'void f(String s) { int.parse(s); }\n',
        }),
        isEmpty,
      );
    });
  });

  group('B3-clock', () {
    const rule = ClockAndPadding();
    test('flags DateTime.now() and padLeft(2, 0)', () {
      final v = run(rule, {
        '$_app/src/features/a/x.dart': '''
void f(int m) {
  final a = DateTime.now();
  final b = m.toString().padLeft(2, '0');
}
''',
      });
      expect(v, hasLength(2));
      expect(v.map((e) => e.message), [
        'DateTime.now() outside the clock',
        contains('padLeft'),
      ]);
    });
    test('passes the owners and other paddings', () {
      expect(
        run(rule, {
          '$_app/src/core/time/app_clock.dart': 'final a = DateTime.now();\n',
          '$_app/main.dart': 'final a = DateTime.now();\n',
          '$_app/main_preview.dart': 'final a = DateTime.now();\n',
          '$_app/design_system/display/d.dart':
              "String f(int m) => m.toString().padLeft(2, '0');\n",
          '$_app/src/features/a/x.dart':
              "String f(int m) => m.toString().padLeft(3, '0');\n",
        }),
        isEmpty,
      );
    });
  });

  group('B9-text-literals', () {
    const rule = TextLiterals();
    test('counts simple, interpolated and adjacent literals once each', () {
      final v = run(rule, {
        '$_app/src/features/a/x.dart': r'''
const a = '新增';
String b(int n) => '共 $n 筆';
const c = '第一行'
    '第二行';
const d = 'plain';
String e(int n) => '${n > 1 ? '多' : 'plain'} items';
''',
      });
      // a, b, c (once), and the nested '多' inside e's interpolation.
      expect(v, hasLength(4));
    });
    test('leaves out assert, Error throws, the owner and other places', () {
      expect(
        run(rule, {
          '$_app/src/features/a/x.dart': '''
void f(int n) {
  assert(n > 0, '必須大於零');
  if (n < 0) throw StateError('不可能');
  if (n < 0) throw ArgumentError('壞了');
}
''',
          '$_app/src/core/messages/m.dart': "const a = '訊息';\n",
          '$_app/src/core/design_system/x.dart': "const a = '訊息';\n",
          '$_app/src/app/y.dart': "const a = 'english';\n",
        }),
        isEmpty,
      );
    });
    test('still counts a thrown non-Error and the shell', () {
      final v = run(rule, {
        '$_app/src/app/y.dart': "void f() { throw FormatException('壞了'); }\n",
      });
      expect(v, hasLength(1));
    });
  });

  group('D2-no-part', () {
    const rule = NoPart();
    test('counts part and part of', () {
      final v = run(rule, {
        '$_app/src/a.dart': "part 'b.dart';\npart 'c.dart';\n",
        '$_app/src/b.dart': "part of 'a.dart';\n",
      });
      expect(v, hasLength(3));
    });
    test('passes a plain library', () {
      expect(run(rule, {'$_app/src/a.dart': "import 'b.dart';\n"}), isEmpty);
    });
  });

  group('E1-catch-handled', () {
    const rule = CatchHandled();
    test('flags a swallowed error, one per catch clause', () {
      final v = run(rule, {
        '$_app/src/a.dart': '''
void f() {
  try { g(); } catch (e) { print(e); }
  try { g(); } on Object { }
  try { g(); } catch (e) { h(); } catch (_) {}
}
''',
      });
      expect(v, hasLength(4));
    });
    test('passes rethrow, throw, ErrorLog and record/report', () {
      expect(
        run(rule, {
          '$_app/src/a.dart': '''
void f() {
  try { g(); } catch (e) { rethrow; }
  try { g(); } catch (e) { throw StateError('x'); }
  try { g(); } catch (e) { ErrorLog.instance.record('x', e); }
  try { g(); } catch (e) { logger.record('x', e); }
  try { g(); } catch (e) { service.report(e); }
  try { g(); } catch (e, s) { completer.completeError(e, s); }
}
''',
        }),
        isEmpty,
      );
    });
  });

  group('C1-tests-exist', () {
    const rule = TestsExist();
    test('flags a core file and a feature without tests', () {
      final v = run(rule, {
        'packages/core/lib/src/a/money.dart': '',
        'packages/core/lib/src/a/fx.dart': '',
        'packages/core/test/a/money_test.dart': '',
        '$_feat/accounts/ui/page.dart': '',
        '$_feat/tags/ui/page.dart': '',
        'apps/expense_tracker/test/features/tags/ui/page_test.dart': '',
      });
      expect(v.map((e) => e.file), [
        'packages/core/lib/src/a/fx.dart',
        '$_feat/accounts',
      ]);
    });
    test('passes when every file and feature is covered', () {
      expect(
        run(rule, {
          'packages/domain/lib/src/a/b.dart': '',
          'packages/domain/test/b_test.dart': '',
          'packages/domain/lib/a.dart': '',
          '$_feat/tags/ui/page.dart': '',
          'apps/expense_tracker/test/features/tags/page_test.dart': '',
        }),
        isEmpty,
      );
    });
  });
}
