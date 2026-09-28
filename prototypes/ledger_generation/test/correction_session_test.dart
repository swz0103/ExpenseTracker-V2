import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:ledger_generation_probe/safety_backup.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/correction-session-tests')
    ..createSync(recursive: true);
  const password = 'synthetic-correction-backup-only';
  final currency = Currency('USD', 2);
  final date = BusinessDate(2026, 9, 28);
  late Directory work;
  late FixtureKeySlots keys;
  late WorkspaceId workspace;
  late Account account;
  late Posting original;
  late PostingCorrection proposal;

  OperationId operationId() => OperationId(PublicId.generate());
  OperationKey op() => OperationKey(workspace, operationId());
  Money money(String n) => Money.parse(currency, n);
  PostingAccount ref() => PostingAccount(
    id: account.id,
    workspace: workspace,
    currency: currency,
    expectedVersion: account.version,
  );
  LedgerStore store({bool corrections = true}) => LedgerStore(
    Directory('${work.path}/store'),
    keys,
    catalogProtection: fixtureCatalogProtection(keys),
    notesAware: !corrections,
    correctionsAware: corrections,
  );
  LedgerStore destination(String name) {
    final slots = FixtureKeySlots(Directory('${work.path}/$name-keys'));
    return LedgerStore(
      Directory('${work.path}/$name'),
      slots,
      catalogProtection: fixtureCatalogProtection(slots),
      correctionsAware: true,
    );
  }

  Future<void> seed(LedgerStore target) async {
    await target.initialize(operationId());
    await target.withSession((session) async {
      await session.createAccount(
        account,
        Posting.opening(
          id: PublicId.generate(),
          operation: op(),
          date: date,
          account: ref(),
          amount: money('100'),
        ),
      );
      await session.post(original);
    });
  }

  setUp(() {
    work = root.createTempSync('case-');
    keys = FixtureKeySlots(Directory('${work.path}/keys'));
    workspace = WorkspaceId(PublicId.generate());
    account = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'synthetic',
      kind: AccountKind.bank,
      currency: currency,
      openedOn: date,
    );
    original = Posting.expense(
      id: PublicId.generate(),
      operation: op(),
      date: date,
      account: ref(),
      amount: money('10'),
    );
    proposal = PostingCorrection(
      original: original,
      replacement: Posting.expense(
        id: PublicId.generate(),
        operation: op(),
        date: BusinessDate(2026, 10, 1),
        account: ref(),
        amount: money('7'),
      ),
      reversalId: PublicId.generate(),
      reversalOperation: op(),
      reason: 'corrected amount',
    );
  });
  tearDown(() {
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    )) {
      throw StateError('Unsafe cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test('schema 13 correction restores independently with password and recovery key', () async {
    final active = store();
    await seed(active);
    late List<int> sessionSnapshot;
    await active.withSession((session) async {
      expect((await session.correct(proposal)).replayed, false);
      expect((await session.correct(proposal)).replayed, true);
      expect((await session.accounts(workspace)).single.balance, money('93'));
      sessionSnapshot = await session.snapshot();
    });
    final before = await active.snapshot();
    expect(sessionSnapshot, before);
    final backup = await active.backup(password);
    for (final method in ['password', 'recovery']) {
      final restored = destination(method);
      await restored.restore(
        backup.envelope,
        operationId(),
        password: method == 'password' ? password : null,
        recoveryKey: method == 'recovery' ? backup.recoveryKey : null,
      );
      expect(await restored.snapshot(), before);
      await restored.withSession((session) async {
        expect((await session.correct(proposal)).replayed, true);
        expect((await session.accounts(workspace)).single.balance, money('93'));
      });
    }
  });

  test(
    'schema 12 to 13 upgrade keeps old DB and both verified safety credentials',
    () async {
      final old = store(corrections: false);
      await seed(old);
      final oldReceipt = (await old.generations.current())!.receipt;
      final before = await old.snapshot();
      final credential = await old.backup(password);
      final target = store();
      final backupId = PublicId.generate();
      final request = await planCorrectionUpgrade(
        target,
        operationId(),
        backupId,
      );
      final backupDirectory = Directory('${work.path}/safety')..createSync();
      await expectLater(
        upgradeCorrections(
          target,
          request,
          backupDirectory,
          password: password,
          recoveryKey: credential.recoveryKey,
          checkpoint: (point) {
            if (point == 'table:event_corrections')
              throw StateError('injected');
          },
        ),
        throwsA(isA<GenerationUnavailable>()),
      );
      expect(await target.snapshot(), before);
      final safety = File('${backupDirectory.path}/${backupId.value}.envelope');
      final envelope = await safety.readAsString();
      expect(
        await EnvelopeCodec().openWithPassword(envelope, password),
        before,
      );
      expect(
        await EnvelopeCodec().openWithRecovery(
          envelope,
          credential.recoveryKey,
        ),
        before,
      );
      await upgradeCorrections(
        target,
        request,
        backupDirectory,
        password: password,
        recoveryKey: credential.recoveryKey,
      );
      expect(
        await target.snapshot(),
        SnapshotCodec(correctionsAware: true).canonicalize(before),
      );
      expect(
        utf8.encode(
          await LedgerPayload(notesAware: true).inspect(
            target.generations.databaseFile(oldReceipt.generation),
            await keys.read(oldReceipt.slot),
            oldReceipt,
          ),
        ),
        before,
      );
      await target.withSession((session) async {
        await session.correct(proposal);
        expect((await session.accounts(workspace)).single.balance, money('93'));
      });
    },
  );

  test(
    'activity pages retain a chain of original, reversals and replacements',
    () async {
      final active = store();
      await seed(active);
      final next = PostingCorrection(
        original: proposal.replacement,
        replacement: Posting.expense(
          id: PublicId.generate(),
          operation: op(),
          date: BusinessDate(2026, 10, 2),
          account: ref(),
          amount: money('5'),
        ),
        reversalId: PublicId.generate(),
        reversalOperation: op(),
        reason: 'second correction',
      );
      await active.withSession((session) async {
        await session.correct(proposal);
        await session.correct(next);
        final expected = {
          original.id,
          proposal.reversal.id,
          proposal.replacement.id,
          next.reversal.id,
          next.replacement.id,
        };
        for (final selected in [
          original.id,
          proposal.replacement.id,
          next.replacement.id,
        ]) {
          final ids = <PublicId>[];
          LedgerActivityCursor? cursor;
          for (;;) {
            final page = await session.activity(
              workspace,
              selected,
              before: cursor,
              limit: 2,
            );
            if (page.isEmpty) break;
            ids.addAll(page.map((row) => row.entry.id));
            cursor = page.last.cursor;
          }
          expect(ids.toSet(), expected);
          expect(ids, hasLength(expected.length));
        }
        final history = await session.activity(
          workspace,
          original.id,
          limit: 10,
        );
        expect(
          history
              .singleWhere((row) => row.entry.id == original.id)
              .correctionRole,
          CorrectionActivityRole.original,
        );
        expect(
          history
              .singleWhere((row) => row.entry.id == proposal.reversal.id)
              .correctionRole,
          CorrectionActivityRole.reversal,
        );
        expect(
          history
              .singleWhere((row) => row.entry.id == next.replacement.id)
              .correctionRole,
          CorrectionActivityRole.replacement,
        );
        expect(
          (await session.entry(workspace, original.id))!.correctedBy,
          proposal.replacement.id,
        );
        expect(
          (await session.entry(
            workspace,
            proposal.replacement.id,
          ))!.correctedBy,
          next.replacement.id,
        );
        expect((await session.accounts(workspace)).single.balance, money('95'));
      });
    },
  );
}
