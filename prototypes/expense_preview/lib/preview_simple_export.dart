part of 'preview_engine.dart';

/// A deliberately narrow interchange view, never a restorable ledger backup.
/// Accounts, opening balances, categories, tags, merchants, deleted events and
/// note history are outside format v1. The UI must disclose those omissions.
final class SimpleExportReview {
  const SimpleExportReview(
    this.batch, {
    required this.openingCount,
    required this.unsupportedCount,
  });

  final SimpleTransactionBatch batch;
  final int openingCount;
  final int unsupportedCount;

  int get includedCount => batch.records.length;
  String toJson() => SimpleTransactionCodec.encodeJson(batch);
  String toCsv() => SimpleTransactionCodec.encodeCsv(batch);
}

extension SimpleExportEngine on PreviewEngine {
  Future<SimpleExportReview> reviewSimpleExport() => _exclusive((epoch) async {
    _require();
    await _requireNoDraft();
    final session = _session!;
    final rows = <SimpleTransaction>[];
    var openings = 0;
    var unsupported = 0;
    LedgerEntry? before;
    while (true) {
      final page = await session.entries(
        _workspace!,
        before: before,
        limit: 100,
      );
      _check(epoch);
      for (final entry in page) {
        if (entry.kind == PostingKind.opening) {
          openings++;
          continue;
        }
        if ((entry.kind != PostingKind.income &&
                entry.kind != PostingKind.expense) ||
            entry.correctedBy != null ||
            entry.reversedBy != null ||
            entry.refundOf != null ||
            entry.reversalOf != null ||
            entry.tombstoneReason != null) {
          unsupported++;
          continue;
        }
        final signed = entry.amount.minorUnits;
        if (entry.kind == PostingKind.income && signed <= BigInt.zero ||
            entry.kind == PostingKind.expense && signed >= BigInt.zero) {
          throw const ExchangeException('invalid_ledger_amount');
        }
        rows.add(
          SimpleTransaction(
            sourceRecordId: entry.id,
            date: entry.date,
            kind: entry.kind,
            accountId: entry.accountId,
            amount: Money(
              entry.amount.currency,
              entry.kind == PostingKind.expense ? -signed : signed,
            ),
            note: entry.note.text,
          ),
        );
      }
      if (page.length < 100) break;
      before = page.last;
    }
    if (rows.isEmpty) throw const ExchangeException('empty_export');
    _check(epoch);
    return SimpleExportReview(
      SimpleTransactionBatch(_workspace!, rows),
      openingCount: openings,
      unsupportedCount: unsupported,
    );
  });
}
