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
  final root = Directory('.dart_tool/simple-import-tests')
    ..createSync(recursive: true);
  final targetWorkspace = WorkspaceId(PublicId.generate());
  final sourceWorkspace = WorkspaceId(PublicId.generate());
  final sourceCash = PublicId.generate();
  final sourceBank = PublicId.generate();
  final twd = Currency('TWD', 2);
  late Directory work;
  late LedgerStore store;
  late Account cash;
  late Account bank;

  LedgerStore target(String name) {
    final keys = FixtureKeySlots(Directory('${work.path}/$name-keys'));
    return LedgerStore(
      Directory('${work.path}/$name'),
      keys,
      catalogProtection: fixtureCatalogProtection(keys),
      notesAware: true,
    );
  }

  Account account(String name) => Account.open(
    id: PublicId.generate(),
    workspace: targetWorkspace,
    name: name,
    kind: AccountKind.bank,
    currency: twd,
    openedOn: BusinessDate(2020, 1, 1),
  );

  Posting opening(Account account) => Posting.opening(
    id: PublicId.generate(),
    operation: OperationKey(targetWorkspace, OperationId(PublicId.generate())),
    date: account.openedOn,
    account: PostingAccount(
      id: account.id,
      workspace: targetWorkspace,
      currency: twd,
      expectedVersion: account.version,
    ),
    amount: Money(twd, BigInt.from(10000)),
  );

  SimpleTransaction row(
    PostingKind kind,
    PublicId sourceAccount,
    int units, {
    PublicId? id,
    String note = '',
  }) => SimpleTransaction(
    sourceRecordId: id ?? PublicId.generate(),
    date: BusinessDate(2026, 9, 28),
    kind: kind,
    accountId: sourceAccount,
    amount: Money(twd, BigInt.from(units)),
    note: note,
  );

  SimpleImportPreview preview(
    SimpleTransactionBatch batch, {
    Account? bankSnapshot,
  }) => SimpleImportPreview.prepare(
    batch: batch,
    destinationWorkspace: targetWorkspace,
    accountMapping: {sourceCash: cash, sourceBank: bankSnapshot ?? bank},
  );

  setUp(() async {
    work = root.createTempSync('case-');
    store = target('source');
    await store.initialize(OperationId(PublicId.generate()));
    cash = account('Cash');
    bank = account('Bank');
    await store.withSession((session) async {
      await session.createAccount(cash, opening(cash));
      await session.createAccount(bank, opening(bank));
    });
  });

  tearDown(() {
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    )) {
      throw StateError('Unsafe test cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test(
    'whole batch writes exact entries and notes once across retry and restore',
    () async {
      final batch = SimpleTransactionBatch(sourceWorkspace, [
        row(PostingKind.income, sourceCash, 250, note: 'Imported income'),
        row(PostingKind.expense, sourceBank, 75),
      ]);
      final review = preview(
        SimpleTransactionCodec.decodeJson(
          SimpleTransactionCodec.encodeJson(batch),
        ),
      );
      final csvReview = preview(
        SimpleTransactionCodec.decodeCsv(
          SimpleTransactionCodec.encodeCsv(batch),
        ),
      );
      late List<PublicId> ids;
      await store.withSession((session) async {
        final first = await session.importSimple(review);
        ids = first.entryIds;
        expect(first.inserted, 2);
        expect(first.replayed, 0);
        expect(
          (await session.entry(targetWorkspace, ids.first))!.kind,
          PostingKind.income,
        );
        expect(
          (await session.entryNote(targetWorkspace, ids.first)).text,
          'Imported income',
        );
        final before = await session.snapshot();
        final replay = await session.importSimple(csvReview);
        expect(replay.entryIds, ids);
        expect(replay.inserted, 0);
        expect(replay.replayed, 2);
        expect(await session.snapshot(), before);
        final accounts = await session.accounts(targetWorkspace);
        expect(
          accounts
              .firstWhere((a) => a.account.id == cash.id)
              .balance
              .minorUnits,
          BigInt.from(10250),
        );
        expect(
          accounts
              .firstWhere((a) => a.account.id == bank.id)
              .balance
              .minorUnits,
          BigInt.from(9925),
        );
      });
      final snapshot = await store.snapshot();
      final tables =
          (jsonDecode(utf8.decode(snapshot)) as Map)['tables'] as Map;
      final contexts = (tables['events'] as List)
          .map((event) => event['source_context'] as String)
          .where((value) => value.startsWith('import-simple-v1:'))
          .toList();
      expect(contexts, hasLength(2));
      final restored = target('restored');
      await restored.generations.install(
        utf8.decode(snapshot),
        OperationId(PublicId.generate()),
      );
      await restored.withSession((session) async {
        final replay = await session.importSimple(review);
        expect(replay.entryIds, ids);
        expect(replay.replayed, 2);
        expect(await session.snapshot(), snapshot);
      });
    },
  );

  test(
    'same source identity with changed content aborts without new writes',
    () async {
      final sourceId = PublicId.generate();
      final first = SimpleTransactionBatch(sourceWorkspace, [
        row(PostingKind.expense, sourceCash, 10, id: sourceId),
      ]);
      await store.withSession((session) async {
        await session.importSimple(preview(first));
        final before = await session.snapshot();
        final changed = SimpleTransactionBatch(sourceWorkspace, [
          row(PostingKind.expense, sourceCash, 11, id: sourceId),
        ]);
        await expectLater(
          session.importSimple(preview(changed)),
          throwsA(
            isA<ExchangeException>()
                .having((error) => error.code, 'code', 'source_conflict')
                .having((error) => error.row, 'row', 1),
          ),
        );
        expect(await session.snapshot(), before);
      });
    },
  );

  test(
    'mixed retry only inserts new source rows and preserves old identity',
    () async {
      final prior = row(PostingKind.income, sourceCash, 120);
      final fresh = row(PostingKind.expense, sourceBank, 30);
      await store.withSession((session) async {
        final old = await session.importSimple(
          preview(SimpleTransactionBatch(sourceWorkspace, [prior])),
        );
        final mixed = await session.importSimple(
          preview(SimpleTransactionBatch(sourceWorkspace, [prior, fresh])),
        );
        expect(mixed.inserted, 1);
        expect(mixed.replayed, 1);
        expect(mixed.entryIds.first, old.entryIds.single);
        expect(mixed.entryIds.last, isNot(old.entryIds.single));
        final again = await session.importSimple(
          preview(SimpleTransactionBatch(sourceWorkspace, [prior, fresh])),
        );
        expect(again.entryIds, mixed.entryIds);
        expect(again.replayed, 2);
      });
    },
  );

  test(
    'a stale second account rolls back the first posting and retry succeeds',
    () async {
      final batch = SimpleTransactionBatch(sourceWorkspace, [
        row(PostingKind.income, sourceCash, 100),
        row(PostingKind.expense, sourceBank, 50),
      ]);
      final stale = Account.restore(
        id: bank.id,
        workspace: bank.workspace,
        name: bank.name,
        kind: bank.kind,
        currency: bank.currency,
        openedOn: bank.openedOn,
        includeInNetWorth: bank.includeInNetWorth,
        version: bank.version + 1,
        state: bank.state,
      );
      await store.withSession((session) async {
        final before = await session.snapshot();
        await expectLater(
          session.importSimple(preview(batch, bankSnapshot: stale)),
          throwsA(
            isA<ExchangeException>()
                .having((error) => error.code, 'code', 'target_versionConflict')
                .having((error) => error.row, 'row', 2),
          ),
        );
        expect(await session.snapshot(), before);
        final result = await session.importSimple(preview(batch));
        expect(result.inserted, 2);
        expect(result.replayed, 0);
      });
    },
  );
}
