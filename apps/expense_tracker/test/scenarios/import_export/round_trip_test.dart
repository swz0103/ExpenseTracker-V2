import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/import_export/model/import_export.dart';
import 'package:expense_tracker/src/features/import_export/ui/import_page.dart'
    show importBookOf;
import 'package:flutter_test/flutter_test.dart';

import '../../baseline/baseline_ledger.dart';

/// N4: books made at random (seeded) and written out with [toCsv], read
/// back into a book of the same accounts, categories and recurring items
/// with no entries, come back the same: every entry with its id, its
/// group, the refund it gives and the purchase it gives back, its
/// recurring link, its mark and day-trade flag, its amount in its own
/// currency and its worth in NT$. `ROUND_TRIP_BOOKS=2000` for a longer
/// run.
void main() {
  final books =
      int.tryParse(Platform.environment['ROUND_TRIP_BOOKS'] ?? '') ?? 150;

  test('$books random books export and import as themselves', () {
    final r = Random(9104);
    for (var i = 0; i < books; i++) {
      final entries = _RandomBook(r).entries();
      final csv = toCsv(_book().accounts, entries);
      final target = _book();
      final found = importCsv(importBookOf(target), csv, fallback: 'bank');
      expect(found.problems, isEmpty, reason: 'book $i\n$csv');
      expect(found.accounts, isEmpty);
      expect(found.categories, isEmpty);
      addImport(target.entryCommands, found);
      expect(
        {for (final e in target.entries.all) e.id: _fields(e)},
        {for (final e in entries) e.id: _fields(e)},
        reason: 'book $i\n$csv',
      );
      // And the file it writes is the file it was read from.
      expect(toCsv(target.accounts, target.entries.all), csv);
    }
  });

  test('$books random books import into a book already holding some of '
      'them, some forged, without touching what it holds (review 37 3)', () {
    final r = Random(3737);
    for (var i = 0; i < books; i++) {
      final written = _RandomBook(r).entries();
      final forged = i.isOdd;
      final entries = forged ? _forge(r, written) : written;
      final csv = toCsv(_book().accounts, entries);
      final target = _book(_someOf(r, written));
      // Some of what it holds deleted: their ids and groups in the trash.
      for (final e in [...target.entries.all]) {
        if (r.nextInt(4) == 0 && target.entries.refundsOf(e.id).isEmpty) {
          target.entryCommands.remove(e.id);
        }
      }
      final held = {for (final e in target.entries.all) e.id: _fields(e)};
      final groups = {
        for (final e in target.entries.all)
          if (e.group case final g?) g,
        for (final t in target.trash.all)
          if (t.entry.group case final g?) g,
      };
      final trashed = {for (final t in target.trash.all) t.entry.id};
      final why = 'book $i${forged ? ' (forged)' : ''}\n$csv';

      final found = importCsv(importBookOf(target), csv, fallback: 'bank');
      expect(found.accounts, isEmpty, reason: why);
      expect(found.categories, isEmpty, reason: why);
      addImport(target.entryCommands, found);

      // Nothing it held changed or went.
      expect(
        {
          for (final id in held.keys)
            id: switch (target.entries.byId(id)) {
              final e? => _fields(e),
              null => null,
            },
        },
        held,
        reason: why,
      );
      for (final e in found.entries) {
        // No group of the book, or of its trash, gained a member.
        expect(groups, isNot(contains(e.group)), reason: '${e.id}: $why');
        // No id of the trash came back on another entry.
        expect(trashed, isNot(contains(e.id)), reason: '${e.id}: $why');
        // A recurring link is to an item the book has.
        if (e.recurring case final id?) {
          expect(target.recurring.byId(id), isNotNull, reason: why);
        }
      }
      // Every refund gives back spending in the book, on an account of
      // its currency, the card itself for card spending, never more than
      // the spending was.
      final given = <String, int>{};
      for (final e in target.entries.all) {
        final of = e.refundOf;
        if (of == null) continue;
        final original = target.entries.byId(of);
        expect(original, isNotNull, reason: '${e.id}: $why');
        expect(original!.isRefund, isFalse, reason: '${e.id}: $why');
        expect(original.type, EntryType.expense, reason: '${e.id}: $why');
        final paid = target.account(original.account);
        expect(
          target.account(e.account).currency,
          paid.currency,
          reason: '${e.id}: $why',
        );
        if (paid.kind == AccountKind.card) {
          expect(e.account, original.account, reason: '${e.id}: $why');
        }
        given[of] = (given[of] ?? 0) + e.amount;
        expect(given[of]!, lessThanOrEqualTo(original.amount), reason: why);
      }
      // Read again, the file adds nothing more.
      final again = importCsv(importBookOf(target), csv, fallback: 'bank');
      expect(again.entries, isEmpty, reason: why);
    }
  });
}

/// About half of [entries], each refund with the spending it gives back,
/// and no trades: a book that holds them as it would once they were kept.
List<Entry> _someOf(Random r, List<Entry> entries) {
  final kept = <String>{};
  return [
    for (final e in entries)
      if (!e.isInvestment &&
          (e.refundOf == null || kept.contains(e.refundOf)) &&
          r.nextBool() &&
          kept.add(e.id))
        e,
  ];
}

/// [entries] as a hand-edited file may have them: refunds moved to
/// another account or currency, or made to give back a refund, and links
/// to recurring items the book does not have.
List<Entry> _forge(Random r, List<Entry> entries) {
  const accounts = ['bank', 'cash', 'card', 'usd'];
  final refunds = [
    for (final e in entries)
      if (e.isRefund) e.id,
  ];
  return [
    for (final e in entries)
      switch (r.nextInt(4)) {
        0 when e.isRefund => _refundAs(
          e,
          account: accounts[r.nextInt(accounts.length)],
          r: r,
        ),
        1 when e.isRefund && refunds.length > 1 => _refundAs(
          e,
          refundOf: refunds.firstWhere((id) => id != e.id),
          r: r,
        ),
        2 when !e.isInvestment => e.withLinks(
          group: e.group,
          recurring: 'gone',
          mark: e.mark,
          dayTrade: e.dayTrade,
        ),
        _ => e,
      },
  ];
}

/// The refund [e] on [account], with a worth at home when that is
/// foreign, or of [refundOf].
Entry _refundAs(
  Entry e, {
  String? account,
  String? refundOf,
  required Random r,
}) {
  final on = account ?? e.account;
  return Entry(
    id: e.id,
    date: e.date,
    type: e.type,
    amount: e.amount,
    account: on,
    category: e.category,
    parts: e.parts,
    tags: e.tags,
    note: e.note,
    refundOf: refundOf ?? e.refundOf,
    home: on == 'usd' ? e.home ?? 1 + r.nextInt(1000) : null,
  );
}

const _today = (2026, 10, 20);

Ledger _book([List<Entry> entries = const []]) => ledgerOf(
  entries: entries,
  today: day(_today.$1, _today.$2, _today.$3),
  accounts: const [
    Account('bank', '銀行', AccountKind.bank, 0),
    Account('cash', '現金', AccountKind.cash, 0),
    Account('card', '信用卡', AccountKind.card, 0, closingDay: 20, dueDay: 5),
    Account('usd', '美元帳戶', AccountKind.bank, 0, currency: 'USD'),
    Account('recv', '代墊款', AccountKind.receivable, 0),
  ],
  categories: [
    Category('飲食', 'food', 0xFF111111),
    Category('居家', 'home', 0xFF222222),
    Category('交通', 'car', 0xFF333333),
    Category('薪水', 'salary', 0xFF444444, income: true),
  ],
  recurring: const [
    Recurring(
      id: 'rent',
      name: '房租',
      amount: 12500,
      day: 1,
      account: 'bank',
      category: '居家',
    ),
  ],
);

/// Every field of [e], to compare entries whole.
List<Object?> _fields(Entry e) => [
  e.id,
  e.date,
  e.type,
  e.amount,
  e.account,
  e.category,
  e.note,
  e.to,
  e.holding,
  e.shares,
  e.recurring,
  e.merchant,
  e.tags,
  e.parts,
  e.fee,
  e.tax,
  e.refundOf,
  e.installments,
  e.average,
  e.split,
  e.home,
  e.received,
  e.group,
  e.dayTrade,
  e.mark,
];

/// A book of entries as the composer writes them, days going forward.
final class _RandomBook {
  _RandomBook(this.r);

  final Random r;
  final _entries = <Entry>[];
  var _day = 0;
  var _ids = 0;
  final _held = <String, int>{};

  static const _notes = [
    '',
    '午餐',
    'a,b',
    '他說 "好"',
    '兩\n行',
    '=1+1',
    '-5 元',
    "'引號",
  ];
  static const _shops = ['', '全聯', '早餐店, 二號'];
  static const _tags = ['家用', '出差 台北', '早餐'];

  T _pick<T>(List<T> from) => from[r.nextInt(from.length)];

  String _id() => r.nextBool() ? 'e${_ids++}' : 'id-${_ids++}-x';

  DateTime _next() {
    _day += r.nextInt(3);
    return DateTime.utc(2026, 1, 1).add(Duration(days: _day));
  }

  List<String> _someTags() => [
    for (final t in _tags)
      if (r.nextInt(4) == 0) t,
  ];

  List<Entry> entries() {
    final count = 1 + r.nextInt(25);
    while (_entries.length < count) {
      switch (r.nextInt(9)) {
        case 0 || 1 || 2:
          _spend();
        case 3:
          _earn();
        case 4:
          _refund();
        case 5:
          _transfer();
        case 6:
          _together();
        case 7:
          _trade();
        default:
          _dividend();
      }
    }
    return _entries;
  }

  void _spend() {
    final account = _pick(['bank', 'cash', 'card', 'usd']);
    final amount = 1 + r.nextInt(50000);
    final foreign = account == 'usd';
    final split = !foreign && amount > 1 && r.nextInt(4) == 0;
    final first = split ? 1 + r.nextInt(amount - 1) : 0;
    final parts = split
        ? [('飲食', first), ('居家', amount - first)]
        : const <(String, int)>[];
    final onCard = account == 'card';
    _entries.add(
      Entry(
        id: _id(),
        date: _next(),
        type: EntryType.expense,
        amount: amount,
        account: account,
        category: split ? '飲食' : _pick(['飲食', '居家', '交通']),
        parts: parts,
        note: _pick(_notes),
        merchant: _pick(_shops),
        tags: _someTags(),
        installments: onCard && r.nextInt(4) == 0 ? 3 + r.nextInt(10) : 0,
        home: foreign ? 1 + r.nextInt(100000) : null,
        recurring: !foreign && r.nextInt(5) == 0 ? 'rent' : null,
        mark: switch (r.nextInt(6)) {
          0 when onCard => EntryMark.annualFee,
          1 when !foreign => EntryMark.invoice,
          _ => null,
        },
      ),
    );
  }

  void _earn() {
    final account = _pick(['bank', 'card', 'usd']);
    final amount = 1 + r.nextInt(80000);
    _entries.add(
      Entry(
        id: _id(),
        date: _next(),
        type: EntryType.income,
        amount: amount,
        account: account,
        category: '薪水',
        note: _pick(_notes),
        tags: _someTags(),
        home: account == 'usd' ? 1 + r.nextInt(100000) : null,
        mark: account == 'card' && r.nextBool() ? EntryMark.reward : null,
      ),
    );
  }

  /// A refund of some of what is left of a spending before it, as the
  /// composer writes it (D62, D65).
  void _refund() {
    final date = _next();
    final open = [
      for (final e in _entries)
        if (e.type == EntryType.expense && !e.isRefund && _left(e) > 0) e,
    ];
    if (open.isEmpty) return;
    final original = _pick(open);
    final left = _left(original);
    final amount = 1 + r.nextInt(left);
    final share = refundShare(
      original,
      amount,
      earlier: [
        for (final e in _entries)
          if (e.refundOf == original.id) e,
      ],
    );
    _entries.add(
      Entry(
        id: _id(),
        date: date,
        type: EntryType.income,
        amount: amount,
        account: original.account,
        category: share.category,
        parts: share.parts,
        tags: share.tags,
        note: _pick(_notes),
        refundOf: original.id,
        home: original.account == 'usd' ? share.home : null,
      ),
    );
  }

  int _left(Entry e) =>
      e.amount -
      _entries
          .where((f) => f.refundOf == e.id)
          .fold(0, (sum, f) => sum + f.amount);

  void _transfer() {
    final (from, to) = _pick(const [
      ('bank', 'cash'),
      ('bank', 'recv'),
      ('bank', 'card'),
      ('bank', 'usd'),
      ('usd', 'bank'),
      ('cash', 'bank'),
    ]);
    final crossing = (from == 'usd') != (to == 'usd');
    final fee = from == 'usd' || to == 'card' || r.nextBool()
        ? 0
        : r.nextInt(30);
    _entries.add(
      TransferDrafts.between(
        id: _id(),
        date: _next(),
        amount: 1 + r.nextInt(100000),
        from: from,
        to: to,
        note: _pick(_notes),
        fee: fee,
        received: crossing ? 1 + r.nextInt(100000) : null,
      ),
    );
  }

  /// A dinner paid for oneself and a friend: a spending and a transfer
  /// to the friend, one group (一起記).
  void _together() {
    final date = _next();
    final group = 'g${_ids++}';
    _entries
      ..add(
        Entry(
          id: _id(),
          date: date,
          type: EntryType.expense,
          amount: 1 + r.nextInt(5000),
          account: 'bank',
          category: '飲食',
          merchant: _pick(_shops),
          group: group,
        ),
      )
      ..add(
        TransferDrafts.between(
          id: _id(),
          date: date,
          amount: 1 + r.nextInt(5000),
          from: 'bank',
          to: 'recv',
        ).inGroup(group),
      );
  }

  void _trade() {
    final code = _pick(['2330', '0050']);
    final held = _held[code] ?? 0;
    final sell = held > 0 && r.nextBool();
    final shares = sell ? 1 + r.nextInt(held) : 1 + r.nextInt(2000);
    _held[code] = held + (sell ? -shares : shares);
    _entries.add(
      Entry(
        id: _id(),
        date: _next(),
        type: sell ? EntryType.sell : EntryType.buy,
        amount: 1 + r.nextInt(500000),
        account: 'bank',
        category: investmentCategory,
        note: _pick(_notes),
        holding: code,
        shares: shares,
        fee: r.nextInt(100),
        tax: sell ? r.nextInt(500) : 0,
        average: sell && r.nextBool(),
        dayTrade: sell && r.nextInt(3) == 0,
      ),
    );
  }

  void _dividend() {
    final code = _pick(['2330', '0050']);
    final held = _held[code] ?? 0;
    final kind = held == 0 ? 0 : r.nextInt(4);
    // 0 cash, 1 stock, 2 split, 3 a capital reduction.
    final shares = switch (kind) {
      1 => 1 + r.nextInt(100),
      2 => held,
      3 => -(1 + r.nextInt(held)),
      _ => 0,
    };
    _held[code] = held + shares;
    final amount = kind == 1 || kind == 2 ? 0 : 1 + r.nextInt(20000);
    _entries.add(
      Entry(
        id: _id(),
        date: _next(),
        type: EntryType.dividend,
        amount: amount,
        account: 'bank',
        category: dividendCategory,
        note: _pick(_notes),
        holding: code,
        shares: shares,
        // The premium withheld is at most the dividend.
        tax: kind == 0 ? r.nextInt(min(100, amount + 1)) : 0,
        split: kind == 2,
      ),
    );
  }
}
