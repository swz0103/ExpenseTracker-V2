import 'dart:math';

import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/repositories/entry_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fuzz.dart';

DateTime _day(int m, int d) => DateTime.utc(2026, m, d);

/// Seeded runs, [fuzzSeeds] of them.
void repositoryFuzz() {
  for (var seed = 0; seed < fuzzSeeds; seed++) {
    test('lazy indexes agree with a fresh repository ($seed)', () {
      final r = Random(seed);
      final repo = EntryRepository();
      var serial = 0;
      final removed = <(int, Entry)>[]; // from removeEach
      final trash = <Entry>[];
      Entry make({String? id, Entry? like}) => Entry(
        id: id ?? 'e${serial++}',
        date: _day(1 + r.nextInt(3), 1 + r.nextInt(4)),
        type: EntryType.expense,
        amount: 10 + r.nextInt(90),
        account: 'a${r.nextInt(3)}',
        to: r.nextInt(4) == 0 ? 'a${r.nextInt(3)}' : null,
        group: r.nextInt(4) == 0 ? 'g${r.nextInt(3)}' : null,
        refundOf: serial > 3 && r.nextInt(4) == 0
            ? 'e${r.nextInt(serial)}'
            : null,
      );

      void readSome() {
        if (r.nextBool()) repo.inMonth(2026, 1 + r.nextInt(3));
        if (r.nextInt(3) == 0) repo.ofAccount('a${r.nextInt(3)}');
        if (r.nextInt(3) == 0) repo.inGroup('g${r.nextInt(3)}');
        if (r.nextInt(3) == 0) repo.refundsOf('e${r.nextInt(max(serial, 1))}');
        if (r.nextInt(3) == 0) repo.byId('e${r.nextInt(max(serial, 1))}');
        if (r.nextInt(5) == 0) repo.firstDate;
        if (r.nextInt(5) == 0 && repo.length > 0) {
          repo.orderOf(repo.all[r.nextInt(repo.length)].id);
        }
      }

      void compare(String step) {
        final fresh = EntryRepository.placed(
          [...repo.all],
          [for (final e in repo.all) repo.orderOf(e.id)],
        );
        List<String> ids(Iterable<Entry> es) => [for (final e in es) e.id];
        expect(ids(repo.all), ids(fresh.all), reason: step);
        for (var m = 1; m <= 3; m++) {
          expect(
            ids(repo.inMonth(2026, m)),
            ids(fresh.inMonth(2026, m)),
            reason: '$step m$m',
          );
          for (var d = 1; d <= 4; d++) {
            expect(
              ids(repo.onDay(_day(m, d))),
              ids(fresh.onDay(_day(m, d))),
              reason: '$step $m/$d',
            );
          }
        }
        for (var a = 0; a < 3; a++) {
          expect(
            ids(repo.ofAccount('a$a')),
            ids(fresh.ofAccount('a$a')),
            reason: '$step acct $a',
          );
          expect(
            ids(repo.inGroup('g$a')),
            ids(fresh.inGroup('g$a')),
            reason: '$step grp',
          );
        }
        for (var i = 0; i <= serial; i++) {
          expect(
            ids(repo.refundsOf('e$i')),
            ids(fresh.refundsOf('e$i')),
            reason: '$step refund $i',
          );
          expect(
            repo.byId('e$i')?.id,
            fresh.byId('e$i')?.id,
            reason: '$step byId',
          );
        }
        expect(ids(repo.byDate), ids(fresh.byDate), reason: '$step byDate');
        expect(
          [for (final l in repo.newestMonths) ids(l)],
          [for (final l in fresh.newestMonths) ids(l)],
          reason: '$step newest',
        );
        expect(repo.firstDate, fresh.firstDate, reason: step);
        for (final e in repo.all) {
          expect(repo.orderOf(e.id), fresh.orderOf(e.id), reason: step);
        }
        final some = [
          for (final e in repo.all)
            if (r.nextBool()) e,
        ]..shuffle(r);
        expect(
          ids(repo.written(some)),
          ids(fresh.written(some)),
          reason: '$step written',
        );
      }

      for (var step = 0; step < 250; step++) {
        final label = 'seed $seed step $step';
        switch (r.nextInt(12)) {
          case 0 || 1:
            repo.add(make());
          case 2:
            repo.addAll([
              for (var i = 0; i < (r.nextBool() ? 3 : 70); i++) make(),
            ]);
          case 3 when repo.length > 0:
            final i = r.nextInt(repo.length);
            trash.add(repo.removeAt(i));
          case 4 when repo.length > 0:
            // an edit in place: same id, maybe another day/account
            final i = r.nextInt(repo.length);
            repo[i] = make(id: repo[i].id);
          case 5 when trash.isNotEmpty:
            final e = trash.removeAt(r.nextInt(trash.length));
            repo.restoreAt(e, repo.orderOf(e.id));
          case 6 when repo.length > 0:
            final picks = [
              for (var i = 0; i < 1 + r.nextInt(12); i++)
                repo.all[r.nextInt(repo.length)],
            ];
            final got = repo.removeEach(picks);
            removed.addAll(got);
            for (final (_, e) in got) {
              trash.add(e);
            }
            // undo at once or later
            if (r.nextBool()) {
              for (final (i, e) in got) {
                repo.insert(i, e);
                trash.remove(e);
              }
            }
          case 7 when repo.length > 0:
            final m = r.nextInt(3);
            final moved = repo.changeAll(
              (e) =>
                  e.date.month == m + 1 && r.nextBool() ? make(id: e.id) : null,
            );
            expect(moved.length, greaterThanOrEqualTo(0));
          case 8 when repo.length > 0:
            final g = 'g${r.nextInt(3)}';
            repo.removeWhere((e) => e.group == g && r.nextBool());
          case 9 when repo.length > 0:
            // delete then re-add same id as new entry (add → new place)
            final e = repo.removeLast();
            repo.add(make(id: e.id));
          case 10 when repo.length > 0:
            final i = r.nextInt(repo.length);
            final e = repo[i];
            repo[i] = e; // identical put
          default:
        }
        readSome();
        if (r.nextInt(4) == 0) compare(label);
      }
      compare('final');
    });
  }
}
