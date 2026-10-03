import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:bookkeeping/memory.dart';
import 'package:flutter/foundation.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

/// The app's single entry to bookkeeping. Screens read from it and send
/// commands through it; it notifies listeners after every commit.
///
/// This first version keeps data in memory. The Android build will open the
/// SQLCipher store behind the same calls.
final class AppSession extends ChangeNotifier {
  AppSession({required this.workspace, required this.clock})
    : _store = MemoryBookkeeping() {
    _books = Bookkeeping(_store);
  }

  /// A preview with a few example accounts and entries.
  factory AppSession.preview({Clock? clock}) {
    final session = AppSession(
      workspace: WorkspaceId(PublicId.generate()),
      clock: clock ?? SystemClock(),
    );
    session._seed();
    return session;
  }

  final WorkspaceId workspace;
  final Clock clock;
  final MemoryBookkeeping _store;
  late final Bookkeeping<MemoryBookkeepingTransaction> _books;
  Future<void> _seeding = Future.value();

  /// Completes once the example data is in place.
  Future<void> get ready => _seeding;

  final twd = Currency.iso('TWD');

  BusinessDate get today {
    final now = clock.now().value.toLocal();
    return BusinessDate(now.year, now.month, now.day);
  }

  List<Account> get accounts =>
      _store.accounts(workspace)..sort((a, b) => a.name.compareTo(b.name));

  List<Account> get activeAccounts => [
    for (final account in accounts)
      if (account.state == AccountState.active) account,
  ];

  Money balanceOf(Account account) => _store.balance(account);

  Money get netWorth {
    var total = Money(twd, BigInt.zero);
    for (final account in accounts) {
      if (account.currency == twd && account.includeInNetWorth) {
        total += balanceOf(account);
      }
    }
    return total;
  }

  List<Posting> get recent => _store.postings(workspace).take(30).toList();

  Account? accountOf(PublicId id) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  MonthTotal monthTotal(int year, int month) {
    final key = '$year-${month.toString().padLeft(2, '0')}';
    return _store.monthly(workspace, key)['TWD'] ??
        MonthTotal(Money(twd, BigInt.zero), Money(twd, BigInt.zero));
  }

  Future<void> openAccount(String name, AccountKind kind, Money? opening) =>
      _run(
        () => _books.openAccount(
          OpenAccount(
            operation: _operation(),
            accountId: PublicId.generate(),
            name: name,
            kind: kind,
            currency: twd,
            openedOn: today,
            openingBalance: opening,
            openingPostingId: opening == null ? null : PublicId.generate(),
          ),
        ),
      );

  Future<void> record(
    CashFlow flow,
    Account account,
    Money amount,
    BusinessDate date,
  ) => _run(
    () => _books.recordCashFlow(
      RecordCashFlow(
        operation: _operation(),
        postingId: PublicId.generate(),
        flow: flow,
        account: AccountRef(account.id, account.version),
        date: date,
        amount: amount,
      ),
    ),
  );

  Future<void> transfer(Account from, Account to, Money amount) => _run(
    () => _books.recordTransfer(
      RecordTransfer(
        operation: _operation(),
        postingId: PublicId.generate(),
        source: AccountRef(from.id, from.version),
        destination: AccountRef(to.id, to.version),
        date: today,
        principal: amount,
      ),
    ),
  );

  Future<void> reverse(Posting posting) => _run(
    () => _books.reversePosting(
      ReversePosting(
        operation: _operation(),
        reversalId: PublicId.generate(),
        originalId: posting.id,
        date: today,
      ),
    ),
  );

  OperationKey _operation() =>
      OperationKey(workspace, OperationId(PublicId.generate()));

  Future<void> _run(Future<Object?> Function() command) async {
    await _seeding;
    try {
      await command();
    } finally {
      notifyListeners();
    }
  }

  void _seed() {
    _seeding = () async {
      Money ntd(int dollars) => Money(twd, BigInt.from(dollars * 100));
      await _books.openAccount(_open('示範：現金', AccountKind.cash, ntd(3000)));
      await _books.openAccount(_open('示範：薪轉戶', AccountKind.bank, ntd(52000)));
      final cash = accounts.firstWhere((a) => a.kind == AccountKind.cash);
      for (final (flow, units) in [
        (CashFlow.expense, 120),
        (CashFlow.expense, 85),
        (CashFlow.income, 500),
      ]) {
        await _books.recordCashFlow(
          RecordCashFlow(
            operation: _operation(),
            postingId: PublicId.generate(),
            flow: flow,
            account: AccountRef(cash.id, cash.version),
            date: today,
            amount: ntd(units),
          ),
        );
      }
      notifyListeners();
    }();
  }

  OpenAccount _open(String name, AccountKind kind, Money opening) =>
      OpenAccount(
        operation: _operation(),
        accountId: PublicId.generate(),
        name: name,
        kind: kind,
        currency: twd,
        openedOn: today,
        openingBalance: opening,
        openingPostingId: PublicId.generate(),
      );
}
