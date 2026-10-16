part of 'ledger_store.dart';

/// Reads for loading a whole workspace at once, as the app does when the
/// ledger is unlocked.
extension BookQueries on LedgerStore {
  /// Every posting in [workspace], reversals included, oldest first.
  List<Posting> workspacePostings(WorkspaceId workspace) {
    final rows = _store.select(
      'SELECT payload FROM ledger_postings WHERE workspace = ? '
      'ORDER BY date, id',
      [workspace.toString()],
    );
    return [for (final row in rows) _decodePosting(row['payload'])];
  }

  /// The postings in [workspace] that a reversal, correction or deletion
  /// has undone.
  Set<PublicId> reversedPostings(WorkspaceId workspace) {
    final rows = _store.select(
      'SELECT reversal_of FROM ledger_postings '
      'WHERE workspace = ? AND reversal_of IS NOT NULL',
      [workspace.toString()],
    );
    return {
      for (final row in rows) PublicId.parse(row['reversal_of']! as String),
    };
  }

  /// The card charge behind each posted card purchase, refund or issuer
  /// adjustment in [workspace], by posting.
  Map<PublicId, PublicId> cardChargesByPosting(WorkspaceId workspace) =>
      _byPosting('card_charges', workspace);

  /// The card payment behind each payment transfer in [workspace], by
  /// posting.
  Map<PublicId, PublicId> cardPaymentsByPosting(WorkspaceId workspace) =>
      _byPosting('card_payments', workspace);

  /// Every budget plan in [workspace], whichever months it applies to,
  /// oldest month first.
  List<BudgetPlan> budgetPlans(WorkspaceId workspace) {
    final rows = _store.select(
      'SELECT payload FROM plan_budgets WHERE workspace = ? '
      'ORDER BY month, id',
      [workspace.toString()],
    );
    final codec = BudgetPlanCodec();
    return [for (final row in rows) codec.decode(row['payload']! as String)];
  }

  /// The recurring template behind each posting in [workspace] that
  /// confirmed one, by posting.
  Map<PublicId, PublicId> recurringByPosting(WorkspaceId workspace) {
    final rows = _store.select(
      'SELECT c.posting_id, c.template_id FROM plan_recurring_confirmed c '
      'JOIN plan_recurring r ON r.id = c.template_id WHERE r.workspace = ?',
      [workspace.toString()],
    );
    final ids = <PublicId, PublicId>{};
    for (final row in rows) {
      final posting = PublicId.parse(row['posting_id']! as String);
      ids[posting] = PublicId.parse(row['template_id']! as String);
    }
    return ids;
  }

  /// The trade records of investment account [accountId] as stored,
  /// oldest first; voided ones are left out.
  List<Map<String, Object?>> tradeRecords(PublicId accountId) {
    final rows = _store.select(
      'SELECT payload FROM invest_trades WHERE account_id = ? '
      "AND json_extract(payload, '\$.id') NOT IN "
      '(SELECT trade_id FROM invest_voids) ORDER BY seq',
      [accountId.value],
    );
    return [for (final row in rows) _json(row['payload'])];
  }

  /// The instrument listed as [symbol] on [market], if any.
  PublicId? listedInstrument(String market, String symbol) {
    final rows = _store.select(
      'SELECT instrument_id FROM invest_listings '
      'WHERE market = ? AND symbol = ?',
      [market, symbol],
    );
    if (rows.isEmpty) return null;
    return PublicId.parse(rows.single['instrument_id']! as String);
  }

  /// Whether a posting with [id] exists, live or reversed.
  bool hasPosting(PublicId id) {
    const sql = 'SELECT 1 FROM ledger_postings WHERE id = ?';
    return _store.select(sql, [id.value]).isNotEmpty;
  }

  Map<PublicId, PublicId> _byPosting(String table, WorkspaceId workspace) {
    final rows = _store.select(
      'SELECT c.id, c.posting_id FROM $table c '
      'JOIN ledger_accounts a ON a.id = c.card_id '
      'WHERE a.workspace = ? AND c.posting_id IS NOT NULL',
      [workspace.toString()],
    );
    final ids = <PublicId, PublicId>{};
    for (final row in rows) {
      final posting = PublicId.parse(row['posting_id']! as String);
      ids[posting] = PublicId.parse(row['id']! as String);
    }
    return ids;
  }
}
