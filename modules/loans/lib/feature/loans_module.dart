import 'package:kernel/kernel.dart';
import 'package:ledger_entries/model.dart' show AccountKind;

/// The loans and debts module as the app's composition root takes it in:
/// what it adds to the contribution points, and nothing else. The app
/// reaches the module's feature only through those points
/// (`lib/src/app/modules.dart` is the one place that names it).
abstract final class LoansModule {
  /// Who the module's contributions are from.
  static const owner = OwnerId('loans');

  /// The balance sheet's row of the loans taken out.
  static const loansRow = 'loans.loans';

  /// The balance sheet's row of what people owe, or are owed (代墊).
  static const peopleRow = 'loans.people';

  /// Adds the module's contributions to [contributions]: it claims the
  /// loan accounts and the people's accounts for the balance sheet, which
  /// the journal values (an account's tag is its kind, as the book's
  /// accounts are posted).
  static void install(Contributions contributions) {
    contributions.on(sheetClaims)
      ..add(owner, SheetClaim(row: loansRow, claims: _kind(AccountKind.loan)))
      ..add(
        owner,
        SheetClaim(row: peopleRow, claims: _kind(AccountKind.receivable)),
      );
  }

  static bool Function(LedgerAccount) _kind(AccountKind kind) =>
      (account) => account.tag == kind.name;
}
