import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/journal/parity.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';
import 'package:kernel/kernel.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import 'posted_book.dart';

/// The books each version of the app kept (test/fixtures/books), opened
/// as the app opens them.
const _books = 'test/fixtures/books';
const _password = 'fixture password';
final _clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 4, 4)));

void printParity(String what, Parity p) {
  // ignore: avoid_print
  print(
    '$what: ${p.figures} figures, '
    '${p is OutOfParity ? p.differences.length : 0} differ; shapes ${p.shapes}',
  );
}

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('parity-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  final versions = [
    for (final d in Directory(_books).listSync().whereType<Directory>())
      d.uri.pathSegments.where((s) => s.isNotEmpty).last,
  ]..sort();

  for (final version in versions) {
    test('the book kept by $version: every figure from its postings', () async {
      final copy = Directory('${scratch.path}/vault')..createSync();
      for (final f in Directory('$_books/$version/vault').listSync()) {
        if (f is File) f.copySync('${copy.path}/${f.uri.pathSegments.last}');
      }
      final open = await LedgerVault(
        copy,
        codec: KeyringCodec(minimumPassword: 6),
      ).unlockWithPassword(_password);
      addTearDown(open.close);
      final ledger = await SqlLedgerDataSource(
        open.store,
        clock: _clock,
      ).load();
      expectGoldenPostings(version, await post(ledger));
      final parity = await parityOf(ledger);
      printParity(version, parity);
      expect(parity, isA<InParity>(), reason: _said(parity));
      expect(parity.figures, greaterThan(100));
      // The same from the file's own tables (D51's store), not only from
      // memory.
      open.store.journal.transaction(open.store.journal.clear);
      final kept = await parityOf(ledger, into: open.store.journal);
      expect(kept, isA<InParity>(), reason: _said(kept));
      expect(kept.figures, parity.figures);
    });
  }

  test('the demo book: every figure from its postings', () async {
    final parity = await parityOf(demoLedger());
    printParity('demo', parity);
    expect(parity, isA<InParity>(), reason: _said(parity));
    expect(parity.figures, greaterThan(1000));
    final file = EncryptedDatabase.open(
      File('${scratch.path}/demo.db'),
      StorageKey.random(),
    );
    addTearDown(file.close);
    final kept = await parityOf(demoLedger(), into: file.journal);
    expect(kept, isA<InParity>(), reason: _said(kept));
    expect(kept.figures, parity.figures);
  });

  test('the check can fail: one intent taken away and it says where', () async {
    final ledger = demoLedger();
    final b = await post(ledger);
    final lunch = ledger.entries.all.firstWhere(
      (e) => e.type.name == 'expense' && e.installments < 2,
    );
    expect(b.journal.delete(IntentId(lunch.id)), isA<Written>());
    final parity = await checkParity(
      today: figuresOf(ledger),
      reader: b.reader,
    );
    final out = parity as OutOfParity;
    expect(
      out.differences.map((d) => (d.figure, d.subject)),
      contains((Figure.balance, lunch.account)),
    );
  });
}

String _said(Parity p) => switch (p) {
  InParity() => '',
  OutOfParity(:final differences) => differences.take(20).join('\n'),
};
