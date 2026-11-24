import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/places.dart';

/// What each place of the app costs on a book of SIZE entries more than
/// the demo book (spread over SPAN days, 1,095 by default): the first
/// frame, the frame and the widgets built again after 隱藏金額 and after
/// a save, and a few interactions (save, toggle, month, scroll, search).
/// One line per place in OUT (a TSV), and a line per error a place threw.
/// Slow, so it only runs when asked:
/// `BENCH=1 SIZE=100000 OUT=/tmp/pages.tsv flutter test test/perf/pages_bench_test.dart`
/// (ONLY=紀錄,商家 for some places). Widget counts are exact; times are
/// single samples (take the least of several runs).
void main() {
  final asked = Platform.environment['BENCH'] != null;
  final size = int.parse(Platform.environment['SIZE'] ?? '0');
  final out = File(Platform.environment['OUT'] ?? '/tmp/pages_$size.tsv');
  final only = Platform.environment['ONLY'];
  final span = int.parse(Platform.environment['SPAN'] ?? '1095');
  final noAdd = Platform.environment['NOADD'] != null;

  testWidgets(
    'pages at $size',
    (tester) async {
      final ledger = demoLedger();
      final baseCount = ledger.entries.all.length;
      final r = Random(3);
      final today = ledger.today;
      final spend = [
        for (final c in ledger.categories.forEntries(income: false)) c.name,
      ];
      final accts = [
        for (final a in ledger.accounts.all)
          if (!a.kind.isDebt) a.id,
      ];
      if (size > 0) {
        ledger.entryCommands.addAll([
          for (var i = 0; i < size; i++)
            Entry(
              id: 'b$i',
              date: today.subtract(Duration(days: (size - i) * span ~/ size)),
              type: EntryType.expense,
              amount: 40 + i * 37 % 900,
              account: accts[i % accts.length],
              category: spend[i % spend.length],
              merchant: '店${r.nextInt(300)}',
              note: i.isEven ? '午餐' : '',
              tags: i % 7 == 0 ? const ['家用'] : const [],
            ),
        ]);
      }
      out.writeAsStringSync('');
      void drain(String where) {
        for (Object? e; (e = tester.takeException()) != null;) {
          final line = '$e'
              .split('\n')
              .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
          out.writeAsStringSync('EXC\t$where\t$line\n', mode: FileMode.append);
        }
      }

      out.writeAsStringSync(
        '# size=$size base=$baseCount total=${ledger.entries.all.length}\n',
        mode: FileMode.append,
      );
      void log(String s) =>
          out.writeAsStringSync('$s\n', mode: FileMode.append);

      int sw(Stopwatch w) => w.elapsedMicroseconds;
      Future<(int, int)> counted(
        WidgetTester t,
        Future<void> Function() f,
      ) async {
        var count = 0;
        debugOnRebuildDirtyWidget = (_, _) => count++;
        final w = Stopwatch()..start();
        try {
          await f();
        } finally {
          debugOnRebuildDirtyWidget = null;
        }
        return (sw(w), count);
      }

      // warm-up (JIT), not logged
      await _showTimed(tester, ledger, Stopwatch(), Stopwatch());
      await go(tester, ['紀錄']);
      await tester.pumpAndSettle();
      drain('warm-up');
      // places
      for (final (name, taps) in places) {
        if (only != null && !only.split(',').any(name.contains)) continue;
        // first frame: pumpWidget only; then settle; then navigation
        final w0 = Stopwatch()..start();
        final preferencesShowSettled = Stopwatch();
        await _showTimed(tester, ledger, w0, preferencesShowSettled);
        final firstBuild = w0.elapsedMicroseconds;
        final shell = preferencesShowSettled.elapsedMicroseconds;
        final nav = Stopwatch()..start();
        try {
          await go(tester, taps);
        } catch (e) {
          log('$name\tFAIL\t$e'.replaceAll('\n', ' '));
          continue;
        }
        final navUs = nav.elapsedMicroseconds;
        // steady frame after a change that touches the whole page
        final (toggleUs, toggleCount) = await counted(tester, () async {
          ledger.amounts.toggle();
          await tester.pump();
        });
        final (idleUs, _) = await counted(tester, () async {
          await tester.pump(const Duration(milliseconds: 16));
        });
        await tester.pumpAndSettle();
        ledger.amounts.toggle();
        await tester.pumpAndSettle();
        // an entry added elsewhere (a save): rebuild count + frame
        final (addUs, addCount) = noAdd
            ? (0, 0)
            : await counted(tester, () async {
                ledger.entryCommands.add(
                  Entry(
                    id: 'save${DateTime.now().microsecondsSinceEpoch}',
                    date: today,
                    type: EntryType.expense,
                    amount: 50,
                    account: accts.first,
                    category: spend.first,
                  ),
                );
                await tester.pump();
              });
        await tester.pumpAndSettle();
        drain(name);
        log(
          '$name\t$firstBuild\t$shell\t$navUs\t$toggleUs\t$toggleCount\t$idleUs\t$addUs\t$addCount',
        );
      }

      // interactions
      Future<void> row(String name, Future<void> Function() f) async {
        try {
          final (us, c) = await counted(tester, () async {
            await f();
            await tester.pumpAndSettle();
          });
          log('INT\t$name\t$us\t$c');
        } catch (e) {
          log('INT\t$name\tFAIL\t${e.toString().split('\n').first}');
        }
        drain(name);
      }

      Future<void> fresh(List<String> taps) async {
        await _showTimed(tester, ledger, Stopwatch(), Stopwatch());
        try {
          await go(tester, taps);
        } catch (e) {
          log('INT\tfresh $taps FAIL $e');
        }
        drain('fresh $taps');
      }

      Future<void> save() async {
        await tester.tap(find.byTooltip('記一筆'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('金額'));
        await tester.pumpAndSettle();
        for (final key in ['1', '8', '0', '完成']) {
          await tester.tap(find.byKey(Keys.calc(key)));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(Keys.save));
        await tester.pumpAndSettle();
      }

      for (final page in const [
        ('總覽', <String>[]),
        ('紀錄', ['紀錄']),
        ('帳戶', ['帳戶']),
        ('報表 收支', ['更多', '財務報表']),
        ('預算管理', ['更多', '預算管理']),
      ]) {
        await fresh(page.$2);
        await row('${page.$1}: save from composer', save);
        await row(
          '${page.$1}: toggle 隱藏金額',
          () async => ledger.amounts.toggle(),
        );
        await row(
          '${page.$1}: toggle again',
          () async => ledger.amounts.toggle(),
        );
        for (final tip in ['上個月', '上一期']) {
          if (find.byTooltip(tip).evaluate().isNotEmpty) {
            await row('${page.$1}: previous month/period ($tip)', () async {
              await tester.tap(find.byTooltip(tip).first);
            });
            await row('${page.$1}: previous again', () async {
              await tester.tap(find.byTooltip(tip).first);
            });
          }
        }
      }
      // 紀錄 specifics
      await fresh(['紀錄']);
      await row('紀錄: scroll one screen', () async {
        await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      });
      await row('紀錄: scroll one screen again', () async {
        await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      });
      await row('紀錄: open filter', () async {
        await tester.tap(find.byTooltip('篩選').first, warnIfMissed: false);
      });
      await fresh(['紀錄']);
      await row('紀錄: open filter (go)', () async => go(tester, ['~篩選']));
      await fresh(['紀錄']);
      await row('紀錄: type search char 1', () async {
        await tester.enterText(find.byType(TextField).first, '午');
      });
      await row('紀錄: type search char 2', () async {
        await tester.enterText(find.byType(TextField).first, '午餐');
      });
      await row('紀錄: clear search', () async {
        await tester.enterText(find.byType(TextField).first, '');
      });
      await fresh(['紀錄']);
      await row('紀錄: open entry detail', () async {
        await tester.tap(find.text('週末點心').first, warnIfMissed: false);
      });
    },
    timeout: const Timeout(Duration(minutes: 90)),
    skip: !asked,
  );
}

Future<void> _showTimed(
  WidgetTester tester,
  Ledger ledger,
  Stopwatch first,
  Stopwatch settle,
) async {
  // same as show(), with the first frame timed apart from settling
  first
    ..reset()
    ..start();
  final f = show(tester, 360, 1, height: 800, book: ledger);
  // show() does pumpWidget then pumpAndSettle; time total instead
  await f;
  first.stop();
  settle
    ..reset()
    ..start()
    ..stop();
}
