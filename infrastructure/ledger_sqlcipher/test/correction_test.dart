import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

final twd = Currency.iso('TWD');
final august = BusinessDate(2026, 8, 15);

Money ntd(int units) => Money(twd, BigInt.from(units));

Matcher fails(FailureKind kind, String diagnostic) =>
    throwsA(AppFailure(kind, diagnostic));

void main() {
  late Directory directory;
  late SqlCipherStore store;
  late LedgerStore ledger;
  late Bookkeeping<SqlBookkeeping> books;
  late PublicId cash;
  late PublicId food;
  final workspace = WorkspaceId(PublicId.generate());

  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));

  AccountRef ref() => AccountRef(cash, 1);

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('ledger-correct-');
    store = SqlCipherStore.open(
      File('${directory.path}/ledger.db'),
      StorageKey.random(),
      modules: [ledgerSchema],
    );
    ledger = LedgerStore(store);
    books = Bookkeeping(ledger);
    cash = PublicId.generate();
    await books.openAccount(
      OpenAccount(
        operation: op(),
        accountId: cash,
        name: '現金',
        kind: AccountKind.cash,
        currency: twd,
        openedOn: BusinessDate(2026, 1, 1),
        openingBalance: ntd(10000),
        openingPostingId: PublicId.generate(),
      ),
    );
    food = PublicId.generate();
    await books.changeCatalog(
      ChangeCatalog(
        operation: op(),
        catalog: CatalogType.category,
        change: CreateEntry(food, '餐飲', kind: CategoryKind.expense),
      ),
    );
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<PublicId> expense(int units) async {
    final outcome = await books.recordCashFlow(
      RecordCashFlow(
        operation: op(),
        postingId: PublicId.generate(),
        flow: CashFlow.expense,
        account: ref(),
        date: august,
        amount: ntd(units),
        allocations: [CategoryShare(food, 1, ntd(units))],
      ),
    );
    return outcome.value;
  }

  Future<PublicId> correct(PublicId original, int units) async {
    final outcome = await books.correctCashFlow(
      CorrectCashFlow(
        operation: op(),
        replacementId: PublicId.generate(),
        originalId: original,
        reversalId: PublicId.generate(),
        account: ref(),
        date: august,
        amount: ntd(units),
        allocations: [CategoryShare(food, 1, ntd(units))],
      ),
    );
    return outcome.value;
  }

  test('a correction fixes the original month in place', () async {
    final dinner = await expense(1000);
    await correct(dinner, 800);
    expect(ledger.balance(ledger.accounts(workspace).single), ntd(9200));
    expect(ledger.monthly(workspace, '2026-08')['TWD']!.expense, ntd(800));
    final totals = ledger.categoryTotals(workspace, '2026-08');
    expect(totals[(food, 'TWD')]!.expense, ntd(800));
    await expectLater(
      correct(dinner, 700),
      fails(FailureKind.conflict, 'posting.already-reversed'),
    );
    final account = PostingAccount(
      id: cash,
      workspace: workspace,
      currency: twd,
      expectedVersion: 1,
    );
    expect(rebuildBalance(account, ledger.postings(cash)), ntd(9200));
  });

  test('deleting removes a posting from its own month', () async {
    final taxi = await expense(350);
    await books.deletePosting(
      DeletePosting(
        operation: op(),
        reversalId: PublicId.generate(),
        originalId: taxi,
      ),
    );
    expect(ledger.monthly(workspace, '2026-08')['TWD']!.expense, ntd(0));
    expect(ledger.balance(ledger.accounts(workspace).single), ntd(10000));
  });

  test('notes are revised with optimistic checks', () async {
    final lunch = await expense(120);
    Future<int> note(int expected, String text) async {
      final outcome = await books.setNote(
        SetNote(
          operation: op(),
          postingId: lunch,
          expectedRevision: expected,
          text: text,
        ),
      );
      return outcome.value;
    }

    expect(await note(0, '和同事'), 1);
    expect(await note(1, '和同事午餐'), 2);
    await expectLater(
      note(1, '改不到'),
      fails(FailureKind.conflict, 'note.conflict'),
    );
    await expectLater(
      note(2, '和同事午餐'),
      fails(FailureKind.rejected, 'note.unchanged'),
    );
    expect(ledger.note(lunch).text, '和同事午餐');
  });
}
