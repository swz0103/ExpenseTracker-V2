import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'simple_transactions.dart';

/// A read-only account mapping review. The commit path must load account state
/// again inside its transaction; a preview is never authority to write.
final class SimpleImportPreview {
  SimpleImportPreview._(
    this.sourceWorkspace,
    this.destinationWorkspace,
    List<SimpleImportRow> rows,
    Map<Currency, BigInt> incomeUnits,
    Map<Currency, BigInt> expenseUnits,
  ) : rows = List.unmodifiable(rows),
      incomeUnits = Map.unmodifiable(incomeUnits),
      expenseUnits = Map.unmodifiable(expenseUnits);

  static SimpleImportPreview prepare({
    required SimpleTransactionBatch batch,
    required WorkspaceId destinationWorkspace,
    required Map<PublicId, Account> accountMapping,
  }) {
    if (batch.records.isEmpty) {
      throw const ExchangeException('empty_import');
    }
    if (batch.sourceWorkspace == destinationWorkspace) {
      throw const ExchangeException('same_workspace_import');
    }
    final rows = <SimpleImportRow>[];
    final income = <Currency, BigInt>{};
    final expense = <Currency, BigInt>{};
    for (var i = 0; i < batch.records.length; i++) {
      final source = batch.records[i];
      final target = accountMapping[source.accountId];
      if (target == null) {
        throw ExchangeException('account_mapping_missing', i + 1);
      }
      if (target.workspace != destinationWorkspace) {
        throw ExchangeException('target_workspace_mismatch', i + 1);
      }
      try {
        target.requirePosting(
          workspace: destinationWorkspace,
          currency: source.amount.currency,
          expectedVersion: target.version,
          date: source.date,
        );
      } on AccountException catch (error) {
        throw ExchangeException('target_${error.code.name}', i + 1);
      }
      rows.add(SimpleImportRow(i + 1, source, target));
      final totals = source.kind == PostingKind.income ? income : expense;
      totals.update(
        source.amount.currency,
        (prior) => prior + source.amount.minorUnits,
        ifAbsent: () => source.amount.minorUnits,
      );
    }
    return SimpleImportPreview._(
      batch.sourceWorkspace,
      destinationWorkspace,
      rows,
      income,
      expense,
    );
  }

  final WorkspaceId sourceWorkspace;
  final WorkspaceId destinationWorkspace;
  final List<SimpleImportRow> rows;

  /// BigInt totals can exceed a single Money value without rounding or wrap.
  final Map<Currency, BigInt> incomeUnits;
  final Map<Currency, BigInt> expenseUnits;
}

final class SimpleImportRow {
  const SimpleImportRow(this.number, this.source, this.targetAccount);

  /// One-based source row number, independent of CSV's header line.
  final int number;
  final SimpleTransaction source;
  final Account targetAccount;
}
