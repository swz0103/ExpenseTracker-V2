import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:ledger_vault/ledger_vault.dart';
import 'package:reports/reports.dart';

import 'session.dart';

/// A session on the encrypted ledger of this device. Not for the web.
AppSession vaultSession(OpenVault vault, {Clock? clock}) => AppSession(
  workspace: vault.workspace,
  clock: clock ?? SystemClock(),
  books: Bookkeeping(vault.ledger),
  reads: _SqlReads(vault.ledger),
);

final class _SqlReads implements LedgerReads {
  _SqlReads(this._ledger);

  final LedgerStore _ledger;

  @override
  List<Account> accounts(WorkspaceId workspace) => _ledger.accounts(workspace);

  @override
  Money balance(Account account) => _ledger.balance(account);

  @override
  List<Posting> recent(WorkspaceId workspace, int limit) =>
      _ledger.recentPostings(workspace, limit: limit);

  @override
  MonthSummary month(WorkspaceId workspace, int year, int month) {
    final home = _ledger.homeMonthly(workspace, ReportMonth(year, month));
    return MonthSummary(
      home.total.income,
      home.total.expense,
      unvalued: home.unvalued,
    );
  }

  @override
  NetWorth netWorth(WorkspaceId workspace) {
    final (:total, :unvalued) = _ledger.netWorth(workspace);
    return NetWorth(total, unvalued);
  }
}
