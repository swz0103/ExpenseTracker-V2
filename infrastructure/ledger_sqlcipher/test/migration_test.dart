import 'dart:io';

import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

/// Upgrades a ledger that already holds data, step by step, the way an
/// installed app meets a new release.
void main() {
  late Directory directory;
  late File file;
  final key = StorageKey.random();

  setUp(() {
    directory = Directory.systemTemp.createTempSync('ledger-migration-');
    file = File('${directory.path}/ledger.db');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  SqlCipherStore openAt(int steps) => SqlCipherStore.open(
    file,
    key,
    modules: [
      SchemaModule('ledger', ledgerSchema.migrations.sublist(0, steps)),
    ],
  );

  test('steps 8 to 10 keep trades, their order and their guards', () async {
    final old = openAt(7);
    await old.write((t) async {
      for (final id in ['p1', 'p2']) {
        t.execute(
          'INSERT INTO ledger_postings (id, workspace, kind, date, payload) '
          "VALUES (?, 'w', 'investmentBuy', '2026-10-01', '{}')",
          [id],
        );
      }
      for (final posting in ['p1', 'p2']) {
        t.execute(
          'INSERT INTO invest_trades '
          '(account_id, instrument_id, posting_id, payload) '
          "VALUES ('acct', 'inst', ?, ?)",
          [posting, '{"id":"$posting"}'],
        );
      }
    });
    final before = old.select('SELECT * FROM invest_trades ORDER BY seq');
    old.close();

    final store = SqlCipherStore.open(file, key, modules: [ledgerSchema]);
    addTearDown(store.close);
    expect(store.moduleVersion('ledger'), ledgerSchema.migrations.length);
    expect(store.select('SELECT * FROM invest_trades ORDER BY seq'), before);
    final columns = store.select('PRAGMA table_info(card_payments)');
    expect([for (final c in columns) c['name']], contains('voided'));
    expect(store.select('SELECT * FROM invest_voids'), isEmpty);
    expect(store.integrityCheck(), 'ok');

    // The rebuilt table is still append-only, and new rows continue the
    // sequence; a split may now have no posting.
    await expectLater(
      store.write((t) async {
        t.execute("UPDATE invest_trades SET payload = 'x'");
      }),
      throwsA(
        isA<SqliteException>().having(
          (e) => e.message,
          'message',
          contains('immutable'),
        ),
      ),
    );
    await store.write((t) async {
      t.execute(
        'INSERT INTO invest_trades '
        '(account_id, instrument_id, posting_id, payload) '
        "VALUES ('acct', 'inst', NULL, '{}')",
      );
    });
    final seqs = [
      for (final row in store.select('SELECT seq FROM invest_trades'))
        row['seq'],
    ];
    expect(seqs, [before[0]['seq'], before[1]['seq'], 3]);
  });
}
