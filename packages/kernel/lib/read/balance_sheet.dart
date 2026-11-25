import '../model/accounts.dart';
import '../model/ids.dart';
import 'contributions.dart';

/// A module's row of the balance sheet: the accounts it [claims], under
/// the key [row]. The module only says which accounts are its; the
/// reader values them (as for net worth), so no module adds an amount of
/// its own and none can count an account another counts.
final class SheetClaim {
  const SheetClaim({required this.row, required this.claims});

  /// The row's key, such as `loans.loans`: a screen gives it its words.
  final String row;

  /// Whether an account of the balance sheet is this row's.
  final bool Function(LedgerAccount account) claims;
}

/// Where modules claim accounts for the balance sheet's rows.
const sheetClaims = ContributionPoint<SheetClaim>('sheet.claims');

/// A row of the balance sheet: who claimed it, its name, what its
/// accounts are worth in the book's currency (a liability below nothing)
/// and which accounts they are. The row no module claimed has no owner.
typedef SheetRow = ({
  OwnerId? owner,
  String row,
  int worth,
  List<AccountId> accounts,
});

/// The balance sheet at a day: a row per claim, in the order claimed,
/// and [unclaimed], the accounts no claim took, so the rows always add up
/// to [net]. An account two claims take counts in the first and is named
/// in [contested]: a module boundary to mend, never a figure counted
/// twice.
typedef BalanceSheet = ({
  List<SheetRow> rows,
  SheetRow unclaimed,
  int net,
  Map<AccountId, List<String>> contested,
  List<AccountId> unvalued,
});

/// The row of the accounts no module claims.
const unclaimedRow = '';
