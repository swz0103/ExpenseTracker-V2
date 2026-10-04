import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:flutter/foundation.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

/// Income and expense of one month in one currency.
final class MonthSummary {
  const MonthSummary(this.income, this.expense);

  final Money income;
  final Money expense;
}

/// The identity of one user action: its operation key and the ids it
/// creates. See [AppSession.begin].
final class Submission {
  Submission._(this.operation, this.id, this.secondId);

  final OperationKey operation;

  /// The new account or posting.
  final PublicId id;

  /// The opening posting of a new account.
  final PublicId secondId;
}

/// What the screens read: the encrypted ledger on the phone
/// (`vault_session.dart`), memory in the web preview (`preview.dart`).
abstract interface class LedgerReads {
  List<Account> accounts(WorkspaceId workspace);

  Money balance(Account account);

  /// Newest first.
  List<Posting> recent(WorkspaceId workspace, int limit);

  /// Totals for `YYYY-MM` in [currency], if anything was booked.
  MonthSummary? month(WorkspaceId workspace, String month, Currency currency);
}

/// The app's single entry to bookkeeping. Screens read from it and send
/// commands through it; it notifies listeners after every commit.
final class AppSession extends ChangeNotifier {
  AppSession({
    required this.workspace,
    required this.clock,
    required Bookkeeping<BookkeepingTransaction> books,
    required LedgerReads reads,
  }) : _books = books,
       _reads = reads;

  final WorkspaceId workspace;
  final Clock clock;
  final Bookkeeping<BookkeepingTransaction> _books;
  final LedgerReads _reads;

  final twd = Currency.of('TWD');

  BusinessDate get today => clock.today();

  List<Account> get accounts =>
      _reads.accounts(workspace)..sort((a, b) => a.name.compareTo(b.name));

  List<Account> get activeAccounts => [
    for (final account in accounts)
      if (account.state == AccountState.active) account,
  ];

  Money balanceOf(Account account) => _reads.balance(account);

  Money get netWorth {
    var total = Money(twd, BigInt.zero);
    for (final account in accounts) {
      if (account.currency == twd && account.includeInNetWorth) {
        total += balanceOf(account);
      }
    }
    return total;
  }

  List<Posting> get recent => _reads.recent(workspace, 30);

  Account? accountOf(PublicId id) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  MonthSummary monthTotal(int year, int month) {
    final key = '$year-${month.toString().padLeft(2, '0')}';
    return _reads.month(workspace, key, twd) ??
        MonthSummary(Money(twd, BigInt.zero), Money(twd, BigInt.zero));
  }

  /// Identifies one user action. Take it when a form opens and pass the
  /// same one to every retry: a retry after an unclear result then returns
  /// the recorded outcome instead of booking twice (health check G4-10).
  Submission begin() =>
      Submission._(_operation(), PublicId.generate(), PublicId.generate());

  Future<void> openAccount(
    Submission submission,
    String name,
    AccountKind kind, {
    Money? opening,
    Currency? currency,
  }) => _run(
    () => _books.openAccount(
      OpenAccount(
        operation: submission.operation,
        accountId: submission.id,
        name: name,
        kind: kind,
        currency: currency ?? opening?.currency ?? twd,
        openedOn: today,
        openingBalance: opening,
        openingPostingId: opening == null ? null : submission.secondId,
      ),
    ),
  );

  Future<void> record(
    Submission submission,
    CashFlow flow,
    Account account,
    Money amount,
    BusinessDate date,
  ) => _run(
    () => _books.recordCashFlow(
      RecordCashFlow(
        operation: submission.operation,
        postingId: submission.id,
        flow: flow,
        account: AccountRef(account.id, account.rulesVersion),
        date: date,
        amount: amount,
      ),
    ),
  );

  Future<void> transfer(
    Submission submission,
    Account from,
    Account to,
    Money amount,
  ) => _run(
    () => _books.recordTransfer(
      RecordTransfer(
        operation: submission.operation,
        postingId: submission.id,
        source: AccountRef(from.id, from.rulesVersion),
        destination: AccountRef(to.id, to.rulesVersion),
        date: today,
        principal: amount,
      ),
    ),
  );

  /// Undoes an entry on its own date, so its month's totals change and no
  /// other month's do (health check G1-05).
  Future<void> reverse(Submission submission, Posting posting) => _run(
    () => _books.reversePosting(
      ReversePosting(
        operation: submission.operation,
        reversalId: submission.id,
        originalId: posting.id,
        date: posting.date,
      ),
    ),
  );

  OperationKey _operation() =>
      OperationKey(workspace, OperationId(PublicId.generate()));

  Future<void> _run(Future<Object?> Function() command) async {
    try {
      await command();
    } finally {
      notifyListeners();
    }
  }
}
