import 'dart:io';
import 'dart:math';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

import '../../../support/book_records.dart';

const _names = ['飲食', '交通', '居家', '娛樂'];
const _tags = ['家用', '旅行'];
const _shops = ['便當店', '捷運', '咖啡'];

/// Whatever any command does to the book reaches the encrypted store: a
/// ledger read back after any run of changes holds exactly the records
/// the one that made them holds. A command that changes a record in
/// memory and forgets to hand it over shows here.
void main() {
  late Directory directory;
  late File file;
  final key = StorageKey.random();
  final clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 4, 4)));
  final today = DateTime.utc(2026, 10, 4);
  EncryptedDatabase? store;

  Future<Ledger> open() {
    store?.close();
    final opened = store = EncryptedDatabase.open(file, key);
    return SqlLedgerDataSource(opened, clock: clock).load();
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('round-trip-');
    file = File('${directory.path}/ledger.db');
  });

  tearDown(() {
    store?.close();
    store = null;
    directory.deleteSync(recursive: true);
  });

  for (final seed in [3, 11, 29, 47, 58, 71, 83, 97, 101, 2026]) {
    test('the book read back is the book written (seed $seed)', () async {
      final r = Random(seed);
      var serial = 0;
      var live = await open();
      T pick<T>(List<T> from) => from[r.nextInt(from.length)];

      live.entryCommands.addAll(
        const [],
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 50000),
          Account('cash', '現金', AccountKind.cash, 2000),
          Account('card', '卡', AccountKind.card, 0, closingDay: 20, dueDay: 5),
        ],
        categories: [
          for (final n in _names) Category(n, 'other', 0xFF000000),
          Category('薪水', 'salary', 0xFF2F7A65, income: true),
        ],
      );

      Entry spend(String id) {
        final kind = r.nextInt(4);
        final from = pick(['bank', 'cash', 'card']);
        return Entry(
          id: id,
          date: today.subtract(Duration(days: r.nextInt(60))),
          type: kind == 0
              ? EntryType.income
              : kind == 1
              ? EntryType.transfer
              : EntryType.expense,
          amount: 10 + r.nextInt(900),
          account: kind == 1 ? 'bank' : from,
          to: kind == 1 ? 'cash' : null,
          category: kind == 1 ? '' : (kind == 0 ? '薪水' : pick(_names)),
          merchant: kind == 1 ? '' : pick(_shops),
          tags: [if (r.nextBool()) pick(_tags)],
        );
      }

      Recurring item(String id) => Recurring(
        id: id,
        name: id,
        amount: 100 + r.nextInt(900),
        day: 1 + r.nextInt(28),
        account: 'bank',
        category: pick(_names),
        auto: r.nextBool(),
      );

      final undo = <Entry>[];
      for (var step = 0; step < 150; step++) {
        final entries = live.entries.all;
        final what = r.nextInt(29);
        switch (what) {
          case 0 || 1 || 2:
            final e = spend('e${serial++}');
            live.entryCommands.add(
              e,
              receipt: r.nextBool() ? '${e.id}.etr' : null,
            );
          case 3 when entries.isNotEmpty:
            final old = pick(entries);
            try {
              live.entryCommands.replace(spend(old.id), receipt: null);
            } on RecordRefused {
              // Replacing a purchase a later sale needs is refused.
            }
          case 4 when entries.isNotEmpty:
            if (live.entryCommands.remove(pick(entries).id) case final gone?) {
              undo.add(gone);
            }
          case 5 when undo.isNotEmpty:
            live.entryCommands.restore(undo.removeLast());
          case 6 when live.trash.all.isNotEmpty:
            live.entryCommands.restoreTrashed(pick(live.trash.all));
          case 7 when entries.length > 2:
            live.entryCommands.removeAll([pick(entries).id, pick(entries).id]);
          case 8 when entries.isNotEmpty:
            live.entryCommands.recategorize([pick(entries)], pick(_names));
          case 9 when entries.isNotEmpty:
            live.entryCommands.moveToAccount([
              pick(entries),
            ], pick(['bank', 'cash']));
          case 10:
            live.entryCommands.renameTag(
              pick(_tags),
              r.nextBool() ? pick(_tags) : '',
            );
          case 11:
            live.entryCommands.renameMerchant(pick(_shops), pick(_shops));
          case 12:
            final id = 'acct${serial++}';
            live.accountCommands.addAccount(
              Account(id, id, AccountKind.cash, 0),
            );
          case 13:
            final a = pick(live.accounts.all);
            live.accountCommands.updateAccount(a.copyWith(name: '${a.name}*'));
          case 14:
            live.accountCommands.setBalance(
              pick(['bank', 'cash']),
              r.nextInt(9000),
            );
          case 15:
            // The three the entries are written to stay: an entry into an
            // account the book does not have is refused (LOG-03).
            final gone = pick(live.accounts.all).id;
            if (!const {'bank', 'cash', 'card'}.contains(gone)) {
              live.accountCommands.removeAccount(gone);
            }
          case 16:
            live.accountCommands.placeAccounts([
              for (final a in live.accounts.all.reversed) a.id,
            ]);
          case 17:
            final c = pick(live.categories.forEntries(income: false));
            if (r.nextBool()) {
              live.categoryCommands.updateCategory(
                c.name,
                c.copyWith(name: '${c.name}${serial++}'),
              );
            } else {
              live.categoryCommands.updateCategory(
                c.name,
                c.copyWith(archived: !c.archived),
              );
            }
          case 18:
            final open = live.categories.forEntries(income: false);
            if (open.length > 2) {
              live.categoryCommands.mergeCategory(
                open.first.name,
                open.last.name,
              );
            }
          case 19:
            live.categoryCommands.placeCategories([
              for (final c in live.categories.all.reversed) c.name,
            ]);
          case 20:
            final on = r.nextBool()
                ? '#${pick(_tags)}'
                : pick(live.categories.all).name;
            if (r.nextBool()) {
              live.budgetCommands.setBudget(on, 100 + r.nextInt(9000));
            } else {
              live.budgetCommands.removeBudget(on);
            }
          case 21:
            if (live.recurring.all.isEmpty || r.nextBool()) {
              live.recurringCommands.saveRecurring(item('r${serial++}'));
            } else {
              live.recurringCommands.removeRecurring(
                pick(live.recurring.all).id,
              );
            }
          case 22 when live.recurring.all.isNotEmpty:
            if (r.nextBool()) {
              live.recurringCommands.confirm(pick(live.recurring.all));
            } else {
              live.recurringCommands.bookDue();
            }
          case 24:
            // A spending paid partly for someone, written as one group.
            final group = 'g${serial++}';
            final paid = spend('e${serial++}');
            live.entryCommands.save(
              [
                Entry(
                  id: paid.id,
                  date: paid.date,
                  type: EntryType.expense,
                  amount: 600,
                  account: 'bank',
                  category: pick(_names),
                  group: group,
                ),
                Entry(
                  id: 'e${serial++}',
                  date: paid.date,
                  type: EntryType.transfer,
                  amount: 200,
                  account: 'bank',
                  to: 'cash',
                  category: '',
                  group: group,
                ),
              ],
              receipt: r.nextBool() ? '$group.etr' : null,
              receiptOn: paid.id,
            );
          case 25:
            live.accountCommands.moveClose(
              'card',
              DateTime.utc(2026, 10, 20),
              DateTime.utc(2026, 10, 18 + r.nextInt(4)),
            );
          case 26 when entries.isNotEmpty:
            live.attachmentCommands.setReceipt(
              pick(entries).id,
              r.nextBool() ? 'p${serial++}.etr' : null,
            );
          case 27 when live.recurring.all.isNotEmpty:
            final it = pick(live.recurring.all);
            if (it.skipped.isNotEmpty) {
              live.recurringCommands.unskip(it, it.skipped.first);
            }
          case 28:
            final sell = r.nextInt(3) == 0;
            try {
              live.entryCommands.add(
                Entry(
                  id: 't${serial++}',
                  date: today.subtract(Duration(days: r.nextInt(30))),
                  type: sell ? EntryType.sell : EntryType.buy,
                  amount: 1000 + r.nextInt(5000),
                  account: 'bank',
                  holding: '2330',
                  shares: 1 + r.nextInt(5),
                ),
              );
            } on RecordRefused {
              // A sale of shares not held is refused; nothing is kept.
            }
          case 23:
            live.attachmentCommands.setDraft(
              pick(draftTabs),
              r.nextBool() ? '{"amount":${r.nextInt(99)}}' : null,
            );
        }
        if (step % 8 == 7 || step == 149) {
          await live.settled;
          // A command may refuse (a sale left short, a name taken); a
          // write the store could not keep is what must not happen.
          expect(
            live.problem.value,
            anyOf(isNull, isA<RecordRefused>(), isA<NameTaken>()),
            reason: 'step $step',
          );
          final kept = bookRecords(live);
          live = await open();
          final back = bookRecords(live);
          for (final kind in kept.keys) {
            expect(back[kind], kept[kind], reason: '$kind at step $step');
          }
        }
      }
    });
  }
}
