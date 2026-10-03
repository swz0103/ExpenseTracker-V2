import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:bookkeeping/memory.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  final twd = Currency.iso('TWD');
  final workspace = WorkspaceId(PublicId.generate());
  final day = BusinessDate(2026, 10, 3);
  Money ntd(int units) => Money(twd, BigInt.from(units));
  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));

  late MemoryBookkeeping store;
  late Bookkeeping<MemoryBookkeepingTransaction> books;

  setUp(() {
    store = MemoryBookkeeping();
    books = Bookkeeping(store);
  });

  Future<PublicId> open(String name, {int opening = 0}) async {
    final id = PublicId.generate();
    await books.openAccount(
      OpenAccount(
        operation: op(),
        accountId: id,
        name: name,
        kind: AccountKind.bank,
        currency: twd,
        openedOn: day,
        openingBalance: opening == 0 ? null : ntd(opening),
        openingPostingId: opening == 0 ? null : PublicId.generate(),
      ),
    );
    return id;
  }

  Account account(PublicId id) =>
      store.accounts(workspace).singleWhere((a) => a.id == id);

  test('commands update balances and monthly totals', () async {
    final bank = await open('銀行', opening: 50000);
    final wallet = await open('錢包');
    final lunch = await books.recordCashFlow(
      RecordCashFlow(
        operation: op(),
        postingId: PublicId.generate(),
        flow: CashFlow.expense,
        account: AccountRef(bank, 1),
        date: day,
        amount: ntd(180),
      ),
    );
    await books.recordTransfer(
      RecordTransfer(
        operation: op(),
        postingId: PublicId.generate(),
        source: AccountRef(bank, 1),
        destination: AccountRef(wallet, 1),
        date: day,
        principal: ntd(2000),
      ),
    );
    await books.reversePosting(
      ReversePosting(
        operation: op(),
        reversalId: PublicId.generate(),
        originalId: lunch.value,
        date: day,
      ),
    );
    expect(store.balance(account(bank)), ntd(48000));
    expect(store.balance(account(wallet)), ntd(2000));
    expect(store.monthly(workspace, '2026-10')['TWD']!.expense, ntd(0));
    expect(store.postings(workspace), hasLength(4));
  });

  test('a failed command leaves nothing behind', () async {
    final bank = await open('銀行');
    final events = store.eventCount;
    await expectLater(
      books.recordCashFlow(
        RecordCashFlow(
          operation: op(),
          postingId: PublicId.generate(),
          flow: CashFlow.expense,
          account: AccountRef(bank, 9),
          date: day,
          amount: ntd(1),
        ),
      ),
      throwsA(
        const AppFailure(FailureKind.conflict, 'account.versionConflict'),
      ),
    );
    expect(store.eventCount, events);
    expect(store.postings(workspace), isEmpty);
  });
}
