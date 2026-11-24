// The golden prints (postings_golden.json) stand for what the
// posting rules post. A rule nobody posts in the kept books can change
// without the prints (or any test of the books) noticing, and a print that
// leaves out a field of a posting cannot see it change.
import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/journal_keeper.dart'
    show journalRules;
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kernel/kernel.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import 'awkward_book.dart' show openKept;
import '../../../core/ledger/journal/posted_book.dart';

final _clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 4, 4)));

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('gold-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  Future<Map<String, Ledger>> books() async {
    final out = <String, Ledger>{};
    final dirs =
        Directory('test/fixtures/books')
            .listSync()
            .whereType<Directory>()
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final d in dirs) {
      final version = d.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final copy = Directory('${scratch.path}/$version')..createSync();
      for (final f in Directory('${d.path}/vault').listSync()) {
        if (f is File) f.copySync('${copy.path}/${f.uri.pathSegments.last}');
      }
      final open = await LedgerVault(
        copy,
        codec: KeyringCodec(minimumPassword: 6),
      ).unlockWithPassword('fixture password');
      addTearDown(open.close);
      out[version] = await SqlLedgerDataSource(
        open.store,
        clock: _clock,
      ).load();
    }
    out['awkward'] = await openKept(
      Directory.systemTemp.createTempSync('gold-a-'),
    );
    return out;
  }

  test('the kept books post a refund that cancels instalments, and a refund '
      'given back by its purchase\'s split', () async {
    var cancelling = 0, splitRefunds = 0;
    for (final MapEntry(value: l) in (await books()).entries) {
      final accounts = {for (final a in l.accounts.all) a.id: a};
      for (final e in l.entries.all) {
        final of = e.refundOf;
        if (of == null) continue;
        if (e.amountParts.length >= 2) splitRefunds++;
        final p = l.entries.byId(of);
        final from = accounts[e.account];
        if (p != null &&
            from != null &&
            from.kind == AccountKind.card &&
            from.cancelledBy(e, p, l.entries.refundsOf(of)).isNotEmpty) {
          cancelling++;
        }
      }
    }
    expect(
      cancelling,
      greaterThan(0),
      reason:
          'no golden book holds a refund that cancels instalments: the '
          'cancelledInstalments amender can change without any print moving',
    );
    expect(
      splitRefunds,
      greaterThan(0),
      reason:
          'no golden book holds a refund split over categories (Earning parts)',
    );
  });

  test(
    'a posting\'s print shows its seq (book order among the intents of a day)',
    () {
      Posting at(int seq) => Posting(
        intent: const IntentId('a'),
        line: 0,
        account: const AccountId('x'),
        amount: 1,
        currency: const CurrencyCode('TWD'),
        date: Day.stored(20260101),
        seq: seq,
      );
      expect('${at(1)}', isNot('${at(2)}'));
    },
  );

  test('new prints are refused unless journalRules or the print rose', () {
    final kept = {
      'journalRules': journalRules,
      'printShape': goldenPrintShape,
      'print': 'aaaa',
    };
    expect(mayKeepPrint(kept, 'aaaa'), isTrue);
    expect(mayKeepPrint(kept, 'bbbb'), isFalse);
    expect(
      mayKeepPrint({...kept, 'journalRules': journalRules - 1}, 'bbbb'),
      isTrue,
    );
    expect(
      mayKeepPrint({...kept, 'printShape': goldenPrintShape - 1}, 'bbbb'),
      isTrue,
    );
  });

  test('the print shows the account tree and each intent\'s streams', () {
    final line = accountLine(
      const LedgerAccount(
        id: AccountId('x'),
        cls: AccountClass.asset,
        name: 'X',
        owner: OwnerId('o'),
      ),
    );
    expect(line, startsWith('account x asset X o parent null'));
  });
}
