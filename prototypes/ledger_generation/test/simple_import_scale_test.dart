import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:data_exchange/data_exchange.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:test/test.dart';

void main() {
  test(
    '4999 imported rows fill the ledger and retry or overflow stays exact',
    () async {
      final root = Directory('.dart_tool/simple-import-scale-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('case-');
      final timer = Stopwatch()..start();
      try {
        final keys = FixtureKeySlots(Directory('${work.path}/keys'));
        final store = LedgerStore(
          Directory('${work.path}/ledger'),
          keys,
          catalogProtection: fixtureCatalogProtection(keys),
          notesAware: true,
        );
        await store.initialize(OperationId(PublicId.generate()));
        final workspace = WorkspaceId(PublicId.generate());
        final sourceWorkspace = WorkspaceId(PublicId.generate());
        final sourceAccount = PublicId.generate();
        final currency = Currency('TWD', 2);
        final account = Account.open(
          id: PublicId.generate(),
          workspace: workspace,
          name: 'Scale cash',
          kind: AccountKind.bank,
          currency: currency,
          openedOn: BusinessDate(2020, 1, 1),
        );
        final reference = PostingAccount(
          id: account.id,
          workspace: workspace,
          currency: currency,
          expectedVersion: account.version,
        );
        await store.withSession((session) async {
          await session.createAccount(
            account,
            Posting.opening(
              id: PublicId.generate(),
              operation: OperationKey(
                workspace,
                OperationId(PublicId.generate()),
              ),
              date: account.openedOn,
              account: reference,
              amount: Money(currency, BigInt.from(10000)),
            ),
          );
        });
        final rows = List.generate(
          4999,
          (_) => SimpleTransaction(
            sourceRecordId: PublicId.generate(),
            date: BusinessDate(2026, 9, 28),
            kind: PostingKind.income,
            accountId: sourceAccount,
            amount: Money(currency, BigInt.one),
          ),
        );
        SimpleImportPreview mapped(SimpleTransactionBatch batch) =>
            SimpleImportPreview.prepare(
              batch: batch,
              destinationWorkspace: workspace,
              accountMapping: {sourceAccount: account},
            );
        final batch = SimpleTransactionBatch(sourceWorkspace, rows);
        final encoded = SimpleTransactionCodec.encodeJson(batch);
        final decoded = SimpleTransactionCodec.decodeJson(encoded);
        final parseMs = timer.elapsedMilliseconds;
        expect(decoded.records, hasLength(4999));

        final review = mapped(decoded);
        final previewMs = timer.elapsedMilliseconds - parseMs;
        late List<PublicId> firstIds;
        await store.withSession((session) async {
          final result = await session.importSimple(review);
          expect(result.inserted, 4999);
          expect(result.replayed, 0);
          firstIds = result.entryIds;
        });
        final writeMs = timer.elapsedMilliseconds - parseMs - previewMs;
        expect(firstIds.toSet(), hasLength(4999));
        expect(
          await store.balance(reference),
          Money(currency, BigInt.from(14999)),
        );
        final fullSnapshot = await store.snapshot();
        await store.withSession((session) async {
          final replay = await session.importSimple(review);
          expect(replay.inserted, 0);
          expect(replay.replayed, 4999);
          expect(replay.entryIds, firstIds);
        });
        final replayMs =
            timer.elapsedMilliseconds - parseMs - previewMs - writeMs;
        expect(await store.snapshot(), fullSnapshot);

        final overflow = SimpleTransactionBatch(sourceWorkspace, [
          ...rows,
          SimpleTransaction(
            sourceRecordId: PublicId.generate(),
            date: BusinessDate(2026, 9, 28),
            kind: PostingKind.expense,
            accountId: sourceAccount,
            amount: Money(currency, BigInt.one),
          ),
        ]);
        final overflowReview = mapped(
          SimpleTransactionCodec.decodeCsv(
            SimpleTransactionCodec.encodeCsv(overflow),
          ),
        );
        await store.withSession((session) async {
          await expectLater(
            session.importSimple(overflowReview),
            throwsA(isA<PreviewCapacity>()),
          );
        });
        expect(await store.snapshot(), fullSnapshot);
        expect(
          await store.balance(reference),
          Money(currency, BigInt.from(14999)),
        );
        File('.dart_tool/simple-import-scale-result.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'recordedUtc': DateTime.now().toUtc().toIso8601String(),
            'platform': Platform.operatingSystemVersion,
            'dart': Platform.version,
            'formatRows': 5000,
            'importedRows': 4999,
            'openingEvents': 1,
            'ledgerEvents': 5000,
            'sourceBytes': utf8.encode(encoded).length,
            'snapshotBytes': fullSnapshot.length,
            'parseMs': parseMs,
            'previewMs': previewMs,
            'writeMs': writeMs,
            'replayMs': replayMs,
            'totalMs': timer.elapsedMilliseconds,
            'overflowAtomic': true,
            'replayExact': true,
            'deviceTested': false,
          }),
          flush: true,
        );
      } finally {
        final rootPath = root.resolveSymbolicLinksSync();
        final workPath = work.resolveSymbolicLinksSync();
        if (!workPath.startsWith('$rootPath${Platform.pathSeparator}')) {
          throw StateError('Unsafe test cleanup');
        }
        work.deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
