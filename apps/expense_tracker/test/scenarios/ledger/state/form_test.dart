// Round 6: drafts and edit forms. A draft put aside and taken up again
// saves the same entry; opening an entry to edit and saving unchanged (or
// cancelling) changes nothing; same-day order after an undo.
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/entries/model/compose_draft.dart';
import 'package:expense_tracker/src/features/entries/model/compose_form.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/state_fingerprint.dart';

String noId(Entry e) {
  final j = Map<String, Object?>.from(jsonOf(e))
    ..remove('id')
    ..remove('group');
  return enc(j);
}

String describe(Entry e) => show(e);

void main() {
  test('DR1 a draft put aside and taken up again saves the same entries', () {
    final bad = <String>[];
    var tried = 0;
    for (final s in seeds.take(15)) {
      final l = generate(s, 120).ledger;
      final r = Random(s);
      final pool = [
        for (final e in l.entries.all)
          if (e.refundOf == null && e.recurring == null) e,
      ];
      for (var i = 0; i < 25 && pool.isNotEmpty; i++) {
        final e = pool[r.nextInt(pool.length)];
        // the form as the person left it
        final f1 = ComposeForm(l, type: e.type, draft: e);
        List<Entry> want;
        try {
          want = f1.buildAll();
        } catch (_) {
          continue;
        }
        tried++;
        // pause: the composer's _asDraft, kept as text
        final draft = ComposeDraft(f1.build(), f1.receipt, f1.lent, l.today);
        l.attachmentCommands.setDraft(f1.tab.name, draft.toJson());
        // resume: a fresh form of that tab takes the draft (composer_state._takeDraft)
        final d = ComposeDraft.read(l.drafts.of(f1.tab.name))!;
        final f2 = ComposeForm(
          l,
          type: switch (f1.tab) {
            ComposeMode.expense || ComposeMode.lend => EntryType.expense,
            ComposeMode.income => EntryType.income,
            ComposeMode.transfer => EntryType.transfer,
            ComposeMode.investment => e.type,
          },
        );
        f2.restore(d.entry, d.receipt);
        f2.date = d.dateOn(l.today);
        if (d.lent != null && f2.mode == ComposeMode.expense) f2.lent = d.lent;
        final got = f2.buildAll();
        l.attachmentCommands.setDraft(f1.tab.name, null);
        final a = [for (final x in want) noId(x)],
            b = [for (final x in got) noId(x)];
        if (a.join() != b.join()) {
          bad.add(
            'seed $s: ${describe(e)} -> want ${want.map(describe).toList()} got ${got.map(describe).toList()}',
          );
        }
      }
    }
    // ignore: avoid_print
    print(
      '[DR1 draft pause/restore] forms tried $tried, differing ${bad.length}: ${bad.take(4)}',
    );
    expect(bad, isEmpty);
  });

  test('DR2 a refund form put aside and taken up again is still a refund of the same purchase', () {
    final bad = <String>[];
    var tried = 0;
    for (final s in seeds.take(15)) {
      final l = generate(s, 120).ledger;
      final originals = [
        for (final e in l.entries.all)
          if (e.type == EntryType.expense &&
              !e.isRefund &&
              e.installments < 2 &&
              e.parts.isEmpty &&
              l.entryQueryService.refundable(e) > 1)
            e,
      ];
      if (originals.isEmpty) continue;
      final o = originals.first;
      final f1 = ComposeForm(l, type: EntryType.income, refunded: o);
      f1.amount = 1;
      final want = f1.build();
      tried++;
      final draft = ComposeDraft(want, f1.receipt, f1.lent, l.today);
      l.attachmentCommands.setDraft(f1.tab.name, draft.toJson());
      final d = ComposeDraft.read(l.drafts.of(f1.tab.name))!;
      // composer_state: only a form that is not a refund and not an edit takes a draft
      final f2 = ComposeForm(l, type: EntryType.income);
      f2.restore(d.entry, d.receipt);
      f2.date = d.dateOn(l.today);
      final got = f2.build();
      if (noId(want) != noId(got)) {
        bad.add(
          'seed $s: refund of ${describe(o)}: want refundOf=${want.refundOf == null ? null : 'orig'} cat ${want.category}, saved refundOf=${got.refundOf} cat ${got.category} amount ${got.amount}',
        );
      }
    }
    // ignore: avoid_print
    print(
      '[DR2 refund draft] tried $tried, differing ${bad.length}: ${bad.take(3)}',
    );
    expect(bad, isEmpty);
  });

  test('DR3 open to edit, save unchanged: same entry, same state; cancel changes nothing', () {
    final bad = <String>[];
    var tried = 0;
    var transferCat = 0;
    for (final s in seeds.take(15)) {
      final l = generate(s, 120).ledger;
      addRecurring(l);
      final r = Random(s);
      final all = l.entries.all;
      for (var i = 0; i < 25; i++) {
        final e = all[r.nextInt(all.length)];
        final s0 = state(l, order: true);
        final f = ComposeForm(l, type: e.type, editing: e);
        List<Entry> built;
        try {
          built = f.buildAll();
        } catch (err) {
          bad.add('seed $s: ${describe(e)}: build threw $err');
          continue;
        }
        tried++;
        // cancel: nothing was written
        final cancelled = diff(
          s0,
          state(l, order: true),
          an: 'before',
          bn: 'after open+cancel',
        );
        if (cancelled != null) {
          bad.add('seed $s CANCEL ${describe(e)}: $cancelled');
        }
        final members = e.group == null ? [e] : l.entryQueryService.groupOf(e);
        // A transfer's category is what the book keeps, by one rule
        // (D80): compared as it is.
        String norm(Entry x) => enc(jsonOf(x));

        final same =
            built.length == members.length &&
            {for (final b in built) norm(b)}
                .difference({for (final m in members) norm(m)})
                .isEmpty;
        if (e.type == EntryType.transfer &&
            e.category.isEmpty &&
            built.first.category.isNotEmpty) {
          transferCat++;
        }
        if (!same) {
          bad.add(
            'seed $s: ${describe(e)} reopened and rebuilt as ${built.map(describe).toList()}'
            ' (differing json keys: ${_keys(e, built.first)})',
          );
          continue;
        }
        try {
          l.entryCommands.save(built, replacing: f.openedIds);
        } catch (err) {
          bad.add('seed $s: saving unchanged ${describe(e)} refused: $err');
          continue;
        }
        final saved = diff(
          s0,
          state(l, order: true),
          an: 'before',
          bn: 'after save unchanged',
        );
        if (saved != null) bad.add('seed $s SAVE ${describe(e)}: $saved');
      }
    }
    // ignore: avoid_print
    print(
      '[DR3 edit form] opened $tried, differing ${bad.length}: ${bad.take(5)} (transfers with empty category saved as 轉帳: $transferCat)',
    );
    expect(bad, isEmpty);
  });

  test('K1 same day, same merchant: the suggested category after delete + undo', () {
    final l = emptyBook();
    DateTime d = day(2026, 10, 20);
    l.entryCommands.add(
      entryOf(
        'a',
        d,
        EntryType.expense,
        100,
        'bank',
        category: '飲食',
        merchant: '全家',
      ),
    );
    l.entryCommands.add(
      entryOf(
        'b',
        d,
        EntryType.expense,
        100,
        'bank',
        category: '交通',
        merchant: '全家',
      ),
    );
    final before = l.entryQueryService.categoryAt('全家');
    final removed = l.entryCommands.remove('a')!;
    l.entryCommands.restore(removed);
    final after = l.entryQueryService.categoryAt('全家');
    // ignore: avoid_print
    print(
      '[K1 suggestion after undo] categoryAt(全家) before $before, after delete+undo of the first entry $after',
    );
    expect(after, before);
  });

  test('K2 same day: the order the day shows after delete + undo', () {
    final l = emptyBook();
    DateTime d = day(2026, 10, 20);
    for (final id in ['a', 'b', 'c']) {
      l.entryCommands.add(
        entryOf(id, d, EntryType.expense, 100, 'bank', category: '飲食'),
      );
    }
    final before = [for (final e in l.entries.onDay(d)) e.id];
    final removed = l.entryCommands.remove('a')!;
    l.entryCommands.restore(removed);
    final after = [for (final e in l.entries.onDay(d)) e.id];
    // ignore: avoid_print
    print('[K2 day order] before $before, after delete+undo of a: $after');
    expect(after, before);
  });
}

String _keys(Entry a, Entry b) {
  final x = jsonOf(a), y = jsonOf(b);
  return [
    for (final k in {...x.keys, ...y.keys})
      if (enc(x[k]) != enc(y[k])) '$k ${enc(x[k])} -> ${enc(y[k])}',
  ].join(', ');
}
