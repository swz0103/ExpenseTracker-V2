import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:modular_persistence_probe/workflows.dart'
    show OperationConflict;
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/account-lifecycle-session-tests')
    ..createSync(recursive: true);
  final twd = Currency('TWD', 2);
  late Directory work;
  late WorkspaceId workspace;
  late LedgerStore store;
  late FixtureKeySlots keys;

  OperationId op() => OperationId(PublicId.generate());
  OperationKey operation() => OperationKey(workspace, op());
  PostingAccount ref(Account account) => PostingAccount(
    id: account.id,
    workspace: workspace,
    currency: account.currency,
    expectedVersion: account.version,
  );

  LedgerStore openStore() => LedgerStore(
    Directory('${work.path}/store'),
    keys,
    catalogProtection: fixtureCatalogProtection(keys),
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: true,
    creditCardsAware: true,
    cardStatementsAware: true,
    cardAuthorizationsAware: true,
  );

  setUp(() async {
    work = root.createTempSync('case-');
    workspace = WorkspaceId(PublicId.generate());
    keys = FixtureKeySlots(Directory('${work.path}/keys'));
    store = openStore();
    await store.initialize(op());
  });

  tearDown(() {
    final base = root.resolveSymbolicLinksSync();
    final target = work.resolveSymbolicLinksSync();
    if (!target.startsWith('$base${Platform.pathSeparator}')) {
      throw StateError('Unsafe synthetic cleanup');
    }
    work.deleteSync(recursive: true);
  });

  Future<void> create(
    LedgerSession session,
    Account account,
    String opening, {
    CreditCardTerms? terms,
  }) => session.createAccount(
    account,
    Posting.opening(
      id: PublicId.generate(),
      operation: operation(),
      date: account.openedOn,
      account: ref(account),
      amount: Money.parse(account.currency, opening),
    ),
    cardTerms: terms,
  );

  test(
    'lifecycle commands are versioned idempotent and survive reopen',
    () async {
      final account = Account.open(
        id: PublicId.generate(),
        workspace: workspace,
        name: 'Everyday',
        kind: AccountKind.cash,
        currency: twd,
        openedOn: BusinessDate(2026, 1, 1),
      );
      final successor = Account.open(
        id: PublicId.generate(),
        workspace: workspace,
        name: 'Successor',
        kind: AccountKind.bank,
        currency: twd,
        openedOn: BusinessDate(2026, 1, 1),
      );
      final rename = operation();
      await store.withSession((session) async {
        await create(session, account, '0');
        await create(session, successor, '0');

        final renamed = await session.renameAccount(
          rename,
          account.id,
          1,
          'Daily cash',
        );
        expect(renamed.replayed, isFalse);
        expect(
          (await session.renameAccount(
            rename,
            account.id,
            1,
            'Daily cash',
          )).replayed,
          isTrue,
        );
        await expectLater(
          session.renameAccount(rename, account.id, 1, 'Different'),
          throwsA(isA<OperationConflict>()),
        );
        await expectLater(
          session.setAccountNetWorthInclusion(
            operation(),
            account.id,
            1,
            false,
          ),
          throwsA(
            isA<AccountException>().having(
              (error) => error.code,
              'code',
              AccountError.versionConflict,
            ),
          ),
        );

        var current = (await session.accounts(workspace))
            .singleWhere((row) => row.account.id == account.id)
            .account;
        expect((current.name, current.version), ('Daily cash', 2));
        await session.setAccountNetWorthInclusion(
          operation(),
          current.id,
          current.version,
          false,
        );
        current = (await session.accounts(workspace))
            .singleWhere((row) => row.account.id == account.id)
            .account;
        expect(current.includeInNetWorth, isFalse);

        await session.archiveAccount(operation(), current.id, current.version);
        current = (await session.accounts(workspace))
            .singleWhere((row) => row.account.id == account.id)
            .account;
        expect(current.state, AccountState.archived);
        await session.reactivateAccount(
          operation(),
          current.id,
          current.version,
        );
        current = (await session.accounts(workspace))
            .singleWhere((row) => row.account.id == account.id)
            .account;
        await session.closeAccount(
          operation(),
          current.id,
          current.version,
          date: BusinessDate(2026, 10, 2),
          reason: 'Moved to successor',
          successorId: successor.id,
        );
        await session.snapshot();
      });

      store = openStore();
      await store.withSession((session) async {
        var restored = (await session.accounts(workspace))
            .singleWhere((row) => row.account.id == account.id)
            .account;
        expect(restored.state, AccountState.closed);
        expect(restored.successorId, successor.id);
        expect(restored.closingReason, 'Moved to successor');
        expect(restored.includeInNetWorth, isFalse);
        await session.reactivateAccount(
          operation(),
          restored.id,
          restored.version,
        );
        restored = (await session.accounts(workspace))
            .singleWhere((row) => row.account.id == account.id)
            .account;
        expect(restored.state, AccountState.active);
        expect(restored.closedOn, BusinessDate(2026, 10, 2));
        await session.closeAccount(
          operation(),
          restored.id,
          restored.version,
          date: BusinessDate(2026, 10, 3),
          reason: 'Closed again',
        );
        await session.snapshot();
      });

      store = openStore();
      await store.withSession((session) async {
        final restored = (await session.accounts(workspace))
            .singleWhere((row) => row.account.id == account.id)
            .account;
        expect(restored.state, AccountState.closed);
        expect(restored.closedOn, BusinessDate(2026, 10, 3));
        expect(restored.closingReason, 'Closed again');
        expect(restored.successorId, isNull);
      });
    },
  );

  test(
    'close rejects non-zero balance and pending card authorization',
    () async {
      final funded = Account.open(
        id: PublicId.generate(),
        workspace: workspace,
        name: 'Funded',
        kind: AccountKind.bank,
        currency: twd,
        openedOn: BusinessDate(2026, 1, 1),
      );
      final card = Account.open(
        id: PublicId.generate(),
        workspace: workspace,
        name: 'Pending card',
        kind: AccountKind.creditCard,
        currency: twd,
        openedOn: BusinessDate(2026, 1, 1),
      );
      await store.withSession((session) async {
        await create(session, funded, '1');
        await create(
          session,
          card,
          '0',
          terms: CreditCardTerms(
            workspace: workspace,
            cardId: card.id,
            currency: twd,
            closingDay: 28,
            dueDay: 15,
          ),
        );
        await expectLater(
          session.closeAccount(
            operation(),
            funded.id,
            funded.version,
            date: BusinessDate(2026, 10, 2),
            reason: 'Should fail',
          ),
          throwsA(
            isA<AccountException>().having(
              (error) => error.code,
              'code',
              AccountError.nonZeroBalance,
            ),
          ),
        );
        await session.authorizeCardPurchase(
          CardCharge.pending(
            id: PublicId.generate(),
            workspace: workspace,
            cardId: card.id,
            kind: CardChargeKind.purchase,
            authorizedOn: BusinessDate(2026, 10, 1),
            authorizedAmount: Money.parse(twd, '10'),
          ),
          op(),
        );
        await expectLater(
          session.closeAccount(
            operation(),
            card.id,
            card.version,
            date: BusinessDate(2026, 10, 2),
            reason: 'Should fail',
          ),
          throwsA(
            isA<AccountException>().having(
              (error) => error.code,
              'code',
              AccountError.unsettledItems,
            ),
          ),
        );
        final rows = await session.accounts(workspace);
        expect(
          rows.where((row) => row.account.state == AccountState.active),
          hasLength(2),
        );
      });
    },
  );
}
