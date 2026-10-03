import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:accounts/accounts.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

/// Kills a process in the middle of booking entries and checks that the
/// ledger it leaves is whole: every projection matches a rebuild from the
/// journal, and every acknowledged entry is there (health check G5-03,
/// G6-09).
void main() {
  late Directory directory;
  late File file;
  final key = StorageKey.random();
  final workspace = WorkspaceId(PublicId.generate());
  final twd = Currency.of('TWD');
  final first = PublicId.generate();
  final second = PublicId.generate();

  SqlCipherStore open([File? at]) =>
      SqlCipherStore.open(at ?? file, key, modules: [ledgerSchema]);

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('ledger-crash-');
    file = File('${directory.path}/ledger.db');
    final store = open();
    final books = Bookkeeping(LedgerStore(store));
    for (final (id, name) in [(first, '現金'), (second, '銀行')]) {
      await books.openAccount(
        OpenAccount(
          operation: OperationKey(workspace, OperationId(PublicId.generate())),
          accountId: id,
          name: name,
          kind: AccountKind.bank,
          currency: twd,
          openedOn: BusinessDate(2026, 9, 1),
          openingBalance: Money(twd, BigInt.from(100000)),
          openingPostingId: PublicId.generate(),
        ),
      );
    }
    store.close();
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('a killed writer leaves a ledger that rebuilds exactly', () async {
    final suffix = Platform.isWindows ? '.exe' : '';
    final worker = File('.dart_tool/worker/bundle/bin/posting_worker$suffix');
    final random = Random(20261004);
    var committed = 0;
    for (var round = 0; round < 6; round++) {
      final stopAfter = 1 + random.nextInt(30);
      final process = await Process.start(worker.absolute.path, [
        file.path,
        key.hex,
        '$workspace',
        first.value,
        second.value,
        '100000',
      ]);
      final output = process.stdout.transform(utf8.decoder);
      final lines = output.transform(const LineSplitter());
      var seen = 0;
      await for (final _ in lines) {
        committed++;
        if (++seen == stopAfter) {
          process.kill(ProcessSignal.sigkill);
          break;
        }
      }
      await process.exitCode;

      final store = open();
      expect(store.integrityCheck(), 'ok');
      final ledger = LedgerStore(store);
      // Every acknowledged command left its one posting, after the two
      // openings; a few more may have committed before the kill landed.
      final postings = ledger.recentPostings(workspace, limit: 1000000);
      expect(postings.length, greaterThanOrEqualTo(2 + committed));
      for (final account in ledger.accounts(workspace)) {
        final participant = PostingAccount(
          id: account.id,
          workspace: workspace,
          currency: twd,
          expectedVersion: account.version,
        );
        expect(
          ledger.balance(account),
          rebuildBalance(participant, ledger.postings(account.id)),
        );
      }
      final copy = open(File('${directory.path}/copy-$round.db'));
      await LedgerReplay.copy(from: store, to: LedgerStore(copy));
      expect(projectionRows(copy), projectionRows(store));
      copy.close();
      store.close();
    }
  });
}
