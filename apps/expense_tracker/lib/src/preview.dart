import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:bookkeeping/memory.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'session.dart';

/// A session kept in memory, for tests and the web preview. Only
/// `main_preview.dart` and tests may import this file; the production
/// entry never reaches it (code audit C-01).
AppSession memorySession({required WorkspaceId workspace, Clock? clock}) {
  final store = MemoryBookkeeping();
  return AppSession(
    workspace: workspace,
    clock: clock ?? SystemClock(),
    books: Bookkeeping(store),
    reads: _MemoryReads(store),
  );
}

/// A memory session with a few example accounts and entries.
Future<AppSession> previewSession({Clock? clock}) async {
  final session = memorySession(
    workspace: WorkspaceId(PublicId.generate()),
    clock: clock,
  );
  Money ntd(int dollars) => Money(session.twd, BigInt.from(dollars));
  await session.openAccount(
    session.begin(),
    '示範：現金',
    AccountKind.cash,
    opening: ntd(3000),
  );
  await session.openAccount(
    session.begin(),
    '示範：薪轉戶',
    AccountKind.bank,
    opening: ntd(52000),
  );
  final cash = session.accounts.firstWhere((a) => a.kind == AccountKind.cash);
  final today = session.today;
  for (final (flow, units) in [
    (CashFlow.expense, 120),
    (CashFlow.expense, 85),
    (CashFlow.income, 500),
  ]) {
    await session.record(session.begin(), flow, cash, ntd(units), today);
  }
  return session;
}

final class _MemoryReads implements LedgerReads {
  _MemoryReads(this._store);

  final MemoryBookkeeping _store;

  @override
  List<Account> accounts(WorkspaceId workspace) => _store.accounts(workspace);

  @override
  Money balance(Account account) => _store.balance(account);

  @override
  List<Posting> recent(WorkspaceId workspace, int limit) =>
      _store.postings(workspace).take(limit).toList();

  @override
  MonthSummary? month(WorkspaceId workspace, String month, Currency currency) {
    final total = _store.monthly(workspace, month)[currency.code];
    return total == null ? null : MonthSummary(total.income, total.expense);
  }
}
