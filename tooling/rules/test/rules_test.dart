import 'package:rules/src/engine.dart';
import 'package:rules/src/registry.dart';
import 'package:rules/src/rules/imports.dart';
import 'package:rules/src/rules/owned.dart';
import 'package:rules/src/rules/structure.dart';
import 'package:rules/src/rules/usage.dart';
import 'package:test/test.dart';

const _app = 'apps/expense_tracker/lib';
const _feat = '$_app/src/features';

List<Violation> run(Rule rule, Map<String, String> sources) =>
    rule.check(Project(sources));

void main() {
  test('the registry has the twelve rules with unique ids', () {
    final ids = [for (final r in allRules) r.id];
    expect(ids.toSet(), hasLength(12));
    expect(
      ids,
      containsAll([
        'A2-feature-isolation',
        'A3-ui-no-data',
        'A4-pure-calc',
        'B2-number-format',
        'B3-clock',
        'B4-calendar-by-hand',
        'B5-owned-values',
        'B7-status-words',
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
    test('covers the lib of every ledger subject package', () {
      final v = run(rule, {
        'packages/ledger/loans/lib/calc/plan.dart':
            "import 'dart:io';\nfinal a = DateTime.now();\n",
        'packages/ledger/trade_costs/lib/model/x.dart':
            "import 'package:flutter/widgets.dart';\n",
        'packages/ledger/loans/test/calc/plan_test.dart':
            'final a = DateTime.now();\n',
      });
      expect(v.map((e) => e.file), [
        'packages/ledger/loans/lib/calc/plan.dart',
        'packages/ledger/loans/lib/calc/plan.dart',
        'packages/ledger/trade_costs/lib/model/x.dart',
      ]);
    });
    test('passes pure code, the clock file and tests', () {
      expect(
        run(rule, {
          'packages/core/lib/src/a.dart':
              "import 'dart:math';\nint f(DateTime d) => d.year;\n",
          'packages/core/lib/time/clock.dart': 'final a = DateTime.now();\n',
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

  group('B4-calendar-by-hand', () {
    const rule = CalendarByHand();
    test('flags a day strip, a month end, a month step and a month count', () {
      final v = run(rule, {
        '$_feat/a/x.dart': '''
void f(DateTime d, DateTime t, int year, int month) {
  final a = DateTime.utc(d.year, d.month, d.day);
  final b = DateTime.utc(year, month + 1, 0);
  final c = DateTime.utc(d.year, d.month - 1);
  final e = d.year * 12 + d.month;
}
''',
        'packages/domain/lib/src/y.dart':
            'final a = DateTime.utc(t.year, t.month, t.day);\n',
      });
      expect(v.map((e) => e.message), [
        'a day stripped by hand: use dayOf',
        'a month end by hand: use monthEnd or daysInMonth',
        'a month stepped by hand: use monthStart or shiftMonth',
        'months counted by hand: use monthIndex',
        'a day stripped by hand: use dayOf',
      ]);
    });
    test('passes core\'s time folder, tests, other days and other '
        'products', () {
      expect(
        run(rule, {
          'packages/core/lib/time/utc_days.dart':
              'final a = DateTime.utc(d.year, d.month, d.day);\n',
          'apps/expense_tracker/test/x_test.dart':
              'final a = DateTime.utc(d.year, d.month, d.day);\n',
          '$_feat/a/x.dart': '''
void f(DateTime d, DateTime e, int year) {
  final a = DateTime.utc(d.year, e.month, d.day);
  final b = DateTime.utc(year, 3, 1);
  final c = DateTime.utc(year, 1);
  final g = 12 * 7;
}
''',
        }),
        isEmpty,
      );
    });
  });

  group('B4-calendar-by-hand: a step that keeps its day (R26)', () {
    const rule = CalendarByHand();
    test('flags a month or year step with a day, in the app, the packages '
        'and infrastructure', () {
      final v = run(rule, {
        '$_feat/a/x.dart': '''
void f(DateTime end, DateTime today) {
  final a = DateTime.utc(end.year, end.month + 1, end.day);
  final b = DateTime.utc(today.year, today.month - 3, today.day);
  final c = DateTime.utc(today.year - 1, today.month, today.day);
  final d = DateTime.utc(today.year, today.month - 1, 15);
}
''',
        'infrastructure/market/lib/src/x.dart': '''
void f(DateTime today, int back) {
  final m = DateTime.utc(today.year, today.month - back);
  final e = DateTime.utc(today.year + 1, today.month, today.day);
}
''',
      });
      const step =
          'a month or year stepped by hand with its day: use monthsAfter '
          'or yearBefore';
      expect(
        [for (final e in v) (e.file, e.line, e.message)],
        [
          ('$_feat/a/x.dart', 2, step),
          ('$_feat/a/x.dart', 3, step),
          ('$_feat/a/x.dart', 4, step),
          ('$_feat/a/x.dart', 5, step),
          (
            'infrastructure/market/lib/src/x.dart',
            2,
            'a month stepped by hand: use monthStart or shiftMonth',
          ),
          ('infrastructure/market/lib/src/x.dart', 3, step),
        ],
      );
    });
    test('passes day 1, a year brought to another calendar, a day step and '
        'infrastructure tests', () {
      expect(
        run(rule, {
          '$_feat/a/x.dart': '''
void f(DateTime d, int rocYear, int month, int day, int i) {
  final a = DateTime.utc(d.year, d.month + i, 1);
  final b = DateTime.utc(rocYear + rocYearOffset, month, day);
  final c = DateTime.utc(d.year, d.month, d.day + 1);
}
''',
          'infrastructure/market/test/x_test.dart':
              'final a = DateTime.utc(d.year, d.month - 1, d.day);\n',
        }),
        isEmpty,
      );
    });
  });

  group('B4-calendar-by-hand: steps written another way (R28)', () {
    const rule = CalendarByHand();
    const step =
        'a month or year stepped by hand with its day: use monthsAfter '
        'or yearBefore';
    test('flags a step in brackets, with hours, local, a year stepped by a '
        'value, and a step in a ?:', () {
      final v = run(rule, {
        '$_feat/a/x.dart': '''
void f(DateTime d, int y, int m, int n) {
  final a = DateTime.utc(y, (m - 1), d.day);
  final b = DateTime.utc(y, m - 1, d.day, 0);
  final c = DateTime(y, m - 1, d.day);
  final e = DateTime.utc(d.year - n, d.month, d.day);
  final g = DateTime.utc(m == 1 ? y - 1 : y, m == 1 ? 12 : m - 1, d.day);
  final h = DateTime(y, m + 1, 0);
  final i = DateTime.utc(y, (m + 1), (0));
  final j = DateTime(y, m == 12 ? 1 : m + 1);
}
''',
      });
      expect(
        [for (final e in v) (e.line, e.message)],
        [
          (2, step),
          (3, step),
          (4, step),
          (5, step),
          (6, step),
          (7, 'a month end by hand: use monthEnd or daysInMonth'),
          (8, 'a month end by hand: use monthEnd or daysInMonth'),
          (9, 'a month stepped by hand: use monthStart or shiftMonth'),
        ],
      );
    });
    test('passes day 1 in brackets, an offset year, a local day of a moment '
        'and a ?: without a step', () {
      expect(
        run(rule, {
          '$_feat/a/x.dart': '''
void f(DateTime d, int y, int m, int rocYear, bool b) {
  final a = DateTime(y, m - 1, (1));
  final c = DateTime.utc(rocYear + rocYearOffset, m, d.day, 12);
  final e = DateTime(d.year, d.month, d.day);
  final g = DateTime.utc(b ? y : d.year, b ? m : d.month, d.day);
}
''',
        }),
        isEmpty,
      );
    });
  });

  group('B4-calendar-by-hand: a local midnight compared (R29)', () {
    const rule = CalendarByHand();
    const message =
        'a local midnight compared as a moment with the ledger\'s UTC days: '
        'compare dayOf of both';
    test('flags a local midnight compared written there or through a local '
        'variable, on either side', () {
      final v = run(rule, {
        '$_feat/a/x.dart': '''
bool f(DateTime d, DateTime from, DateTime to, int y, int m) {
  final day = DateTime(d.year, d.month, d.day);
  final a = !day.isBefore(from) && !day.isAfter(to);
  final b = from.isAfter(DateTime(y, m));
  final c = (DateTime(y, m, 1)).compareTo(to);
  return a && b && to.isAtSameMomentAs(day);
}
''',
      });
      expect(
        [for (final e in v) (e.line, e.message)],
        [(3, message), (3, message), (4, message), (5, message), (6, message)],
      );
    });
    test('passes UTC midnights, a local moment with hours, a local midnight '
        'not compared, and dayOf', () {
      expect(
        run(rule, {
          '$_feat/a/x.dart': '''
bool f(DateTime d, DateTime from, int y, int m) {
  final day = DateTime.utc(y, m, 1);
  final noon = DateTime(y, m, 1, 12);
  final shown = DateTime(y, m);
  final a = day.isBefore(from) || noon.isAfter(from);
  final b = dayOf(d).isAfter(dayOf(from));
  return a && b && shown.year == y;
}
''',
        }),
        isEmpty,
      );
    });
  });

  group('B5-owned-values', () {
    const rule = OwnedValues();
    test('flags an owned value outside its owner', () {
      final v = run(rule, {
        '$_app/src/core/design_system/paint.dart':
            "const f = TextStyle(fontFamily: 'Nunito');\n",
        '$_app/src/app/about.dart':
            "const b = String.fromEnvironment('APP_BUILD');\n",
        'packages/domain/lib/src/c.dart': 'bool f(int y) => y > 9999;\n',
      });
      expect(v, hasLength(3));
      expect(v.map((e) => e.message), [
        contains('app_update.dart'),
        contains('theme.dart'),
        contains('month_arithmetic.dart'),
      ]);
    });
    test('passes the owners, tests and other values', () {
      expect(
        run(rule, {
          '$_app/src/core/design_system/theme.dart':
              "const f = TextStyle(fontFamily: 'Nunito');\n",
          '$_app/src/features/settings/model/app_update.dart':
              "const b = int.fromEnvironment('APP_BUILD');\n",
          'packages/core/lib/time/month_arithmetic.dart':
              'const maxYear = 9999;\n',
          'packages/core/test/time/x_test.dart': 'final y = 9999;\n',
          '$_feat/a/x.dart': "const n = 'Nunito Sans'; const m = 999;\n",
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

  group('B7-status-words', () {
    const rule = StatusWordLiterals();
    test('flags a status word in a plain, interpolated or nested literal', () {
      final v = run(rule, {
        '$_app/src/features/a/x.dart': r'''
const a = '已逾期';
String b(int n) => '超支 $n';
String c(bool x) => '${x ? '已入帳' : 'plain'} items';
const d = '剩下';
''',
      });
      // a, b, and the nested '已入帳' inside c; d holds no status word.
      expect(v, hasLength(3));
      expect(v.map((x) => x.line), [1, 2, 3]);
    });
    test('leaves the presentation, its messages and comments alone', () {
      expect(
        run(rule, {
          '$_app/design_system/display/status.dart': "const a = '已逾期';\n",
          '$_app/design_system/display/status_messages.dart':
              "const a = '已賣光';\n",
          '$_app/src/features/a/x.dart': '// 已逾期 in a comment\nconst a = 1;\n',
          'packages/domain/lib/x.dart': "const a = '超支';\n",
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
    test('every lib file of a ledger package needs a test', () {
      final v = run(rule, {
        'packages/ledger/loans/lib/calc/loan_plan.dart': '',
        'packages/ledger/loans/lib/model/rate.dart': '',
        'packages/ledger/loans/test/calc/loan_plan_test.dart': '',
        'packages/ledger/trade_costs/lib/calc/settlement.dart': '',
        // A test of the same name in another package does not count.
        'packages/ledger/loans/test/settlement_test.dart': '',
      });
      expect(v.map((e) => e.file), [
        'packages/ledger/loans/lib/model/rate.dart',
        'packages/ledger/trade_costs/lib/calc/settlement.dart',
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
