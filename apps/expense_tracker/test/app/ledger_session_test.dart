import 'dart:convert';
import 'dart:typed_data';

import 'package:expense_tracker/src/app/ledger_session.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/quarantine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';

/// Opening a ledger: load it, apply the inbox, check it, book what is
/// due, each step on its own so one failing leaves the others running.
void main() {
  final today = DateTime.utc(2026, 10, 12);

  Recurring item(String id, int day, {bool auto = false}) => Recurring(
    id: id,
    name: id,
    amount: 500,
    day: day,
    account: 'bank',
    category: '居家',
    auto: auto,
    start: DateTime.utc(2026, 10, day),
  );

  Ledger book({List<Recurring>? recurring, List<Entry> entries = const []}) =>
      Ledger(
        today: today,
        accounts: const [Account('bank', '銀行', AccountKind.bank, 50000)],
        categories: [Category('居家', 'home', 0xFF5B8DB0)],
        entries: entries,
        holdings: const [],
        budgets: const [],
        recurring: recurring ?? [item('rent', 5)],
      );

  InboxItem confirm(String id, String day) => (
    name: '$id-$day.json',
    plain: Uint8List.fromList(
      utf8.encode('{"kind":"confirm","recurring":"$id","day":"$day"}'),
    ),
  );

  /// An inbox holding [items], which notes what was taken out.
  (Future<InboxSource> Function(), List<String>) inbox(List<InboxItem> items) {
    final removed = <String>[];
    return (
      () async => (
        read: () async => items,
        remove: (String name) async => removed.add(name),
      ),
      removed,
    );
  }

  List<String> logged(void Function() run) {
    final before = ErrorLog.instance.entries.length;
    run();
    final all = ErrorLog.instance.entries;
    return [for (final (_, text) in all.take(all.length - before)) text];
  }

  test('without an inbox the book opens with nothing to tell', () async {
    final ledger = book();
    final start = await LedgerSession(load: () async => ledger).open();
    expect(start.ledger, same(ledger));
    expect(start.inbox, isNull);
    expect(start.booked, 0);
  });

  test('the rows set aside as the book loaded are told', () async {
    final ledger = book();
    const aside = [
      QuarantinedRow('entry', 'e9', QuarantineReason.newer, version: 3),
    ];
    final start = await LedgerSession(
      load: () async => ledger,
      quarantined: () => aside,
    ).open();
    expect(start.ledger, same(ledger));
    expect(start.quarantined, aside);
  });

  test('the inbox books its confirmations and is emptied', () async {
    final ledger = book();
    final (open, removed) = inbox([confirm('rent', '2026-10-05')]);
    final start = await LedgerSession(
      load: () async => ledger,
      inbox: open,
    ).open();
    expect(start.inbox?.booked, 1);
    expect(ledger.entries.all.single.recurring, 'rent');
    expect(removed, ['rent-2026-10-05.json']);
  });

  test('an empty inbox tells nothing', () async {
    final (open, removed) = inbox(const []);
    final start = await LedgerSession(
      load: () async => book(),
      inbox: open,
    ).open();
    expect(start.inbox, isNull);
    expect(removed, isEmpty);
  });

  test('an inbox that cannot be opened is logged, and the book still opens '
      'and books what is due', () async {
    final ledger = book(recurring: [item('rent', 5, auto: true)]);
    final before = ErrorLog.instance.entries.length;
    final start = await LedgerSession(
      load: () async => ledger,
      inbox: () async => throw StateError('sealed for another ledger'),
    ).open();
    expect(start.inbox, isNull);
    expect(start.booked, 1);
    expect(ErrorLog.instance.entries.length, before + 1);
    expect(ErrorLog.instance.entries.first.$2, contains('收件匣'));
  });

  test('items marked to book themselves are booked once their day came', () {
    final ledger = book(
      recurring: [item('rent', 5, auto: true), item('gym', 20, auto: true)],
    );
    final session = LedgerSession(load: () async => ledger);
    expect(session.bookDue(ledger), 1);
    // Booked once: coming back the same day books nothing more.
    expect(session.bookDue(ledger), 0);
  });

  test('a record naming an account the book lacks is logged once a kind', () {
    final orphan = Entry(
      id: 'e1',
      date: today,
      type: EntryType.expense,
      amount: 100,
      account: 'gone',
      category: '居家',
    );
    final ledger = book(entries: [orphan, orphan.withId('e2')]);
    final notes = logged(
      () => LedgerSession(load: () async => ledger).checkIntegrity(ledger),
    );
    expect(notes.where((n) => n.contains('帳本健檢')), hasLength(1));
  });

  group('the inbox while the ledger stays open', () {
    /// What happened, in order: each change kept, each item taken out.
    late List<String> steps;
    late _Disk disk;

    Ledger kept() => Ledger(
      today: today,
      accounts: const [Account('bank', '銀行', AccountKind.bank, 50000)],
      categories: [Category('居家', 'home', 0xFF5B8DB0)],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: [item('rent', 5)],
      dataSource: disk,
    );

    (Future<InboxSource> Function(), List<String>) logged(
      List<InboxItem> items, {
      bool removeFails = false,
    }) {
      final removed = <String>[];
      return (
        () async => (
          read: () async => [
            for (final i in items)
              if (!removed.contains(i.name)) i,
          ],
          remove: (String name) async {
            if (removeFails) throw const FileSystemLike('app stopped');
            steps.add('removed $name');
            removed.add(name);
          },
        ),
        removed,
      );
    }

    setUp(() {
      steps = [];
      disk = _Disk(steps, () => kept());
    });

    test('REM-01: coming back books what was confirmed on a notification '
        'meanwhile', () async {
      final ledger = kept();
      final (open, removed) = logged([confirm('rent', '2026-10-05')]);
      final back = await LedgerSession(
        load: () async => ledger,
        inbox: open,
      ).resume(ledger);
      expect(back.inbox?.booked, 1);
      expect(ledger.entries.all.single.recurring, 'rent');
      expect(removed, ['rent-2026-10-05.json']);
    });

    test(
      'REM-02: an item is taken out only once its booking is kept',
      () async {
        final ledger = kept();
        final (open, _) = logged([confirm('rent', '2026-10-05')]);
        await LedgerSession(
          load: () async => ledger,
          inbox: open,
        ).resume(ledger);
        expect(steps, ['kept rent', 'removed rent-2026-10-05.json']);
      },
    );

    test('REM-02: a booking the book refuses leaves the item, booked once '
        'when next read', () async {
      final ledger = kept();
      final (open, removed) = logged([confirm('rent', '2026-10-05')]);
      final session = LedgerSession(load: () async => ledger, inbox: open);
      disk.failNext = 1;
      final refused = await session.resume(ledger);
      expect(refused.inbox, isNull);
      expect(removed, isEmpty);
      // The book was read back without the booking.
      expect(ledger.entries.all, isEmpty);

      final again = await session.resume(ledger);
      expect(again.inbox?.booked, 1);
      expect(removed, ['rent-2026-10-05.json']);
      expect([for (final e in ledger.entries.all) e.recurring], ['rent']);
    });

    test('REM-02: stopped after the booking was kept and before the item '
        'was taken out, the next read books nothing twice', () async {
      final ledger = kept();
      final items = [confirm('rent', '2026-10-05')];
      final (stopped, _) = logged(items, removeFails: true);
      await LedgerSession(load: () async => ledger, inbox: stopped).open();
      expect(ledger.entries.all, hasLength(1));

      final (open, removed) = logged(items);
      final start = await LedgerSession(
        load: () async => ledger,
        inbox: open,
      ).open();
      expect(start.inbox?.booked, 0);
      expect(removed, ['rent-2026-10-05.json']);
      expect(ledger.entries.all, hasLength(1));
    });

    test('two reads at once take each item once', () async {
      final ledger = kept();
      final (open, removed) = logged([confirm('rent', '2026-10-05')]);
      final session = LedgerSession(load: () async => ledger, inbox: open);
      final both = await Future.wait([
        session.readInbox(ledger),
        session.readInbox(ledger),
      ]);
      expect([for (final o in both) o?.booked], [1, null]);
      expect(removed, ['rent-2026-10-05.json']);
      expect(ledger.entries.all, hasLength(1));
    });
  });
}

/// A failure of the phone's files, as when the app is stopped.
final class FileSystemLike implements Exception {
  const FileSystemLike(this.message);
  final String message;
}

/// Where the ledger keeps its changes: notes each in [steps], refuses the
/// next [failNext], and reads back a book as [load] makes it.
final class _Disk implements LedgerDataSource {
  _Disk(this.steps, this._fresh);

  final List<String> steps;
  final Ledger Function() _fresh;
  var failNext = 0;

  @override
  Future<void> keep(WriteBatch batch) async {
    await Future<void>.delayed(Duration.zero);
    if (failNext > 0) {
      failNext--;
      throw const DataSourceException('disk full');
    }
    steps.add('kept ${[for (final e in batch.entries) e.recurring].join(',')}');
  }

  @override
  Future<Ledger> load() async => _fresh();
}
