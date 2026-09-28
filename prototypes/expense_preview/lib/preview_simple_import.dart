part of 'preview_engine.dart';

/// A review is bound to the unlocked session that read the target accounts.
/// Selecting a document never posts it; the caller must explicitly confirm.
final class SimpleImportReview {
  SimpleImportReview._(this.preview, this._owner, this._session, this._epoch);

  final SimpleImportPreview preview;
  final PreviewEngine _owner;
  final LedgerSession _session;
  final int _epoch;
}

extension SimpleImportEngine on PreviewEngine {
  Future<SimpleImportReview> reviewSimpleImport(
    String document, {
    required bool csv,
    required Map<PublicId, PublicId> accountMapping,
  }) => _exclusive((epoch) async {
    _require();
    final session = _session!;
    final batch = csv
        ? SimpleTransactionCodec.decodeCsv(document)
        : SimpleTransactionCodec.decodeJson(document);
    final accounts = await session.accounts(_workspace!);
    _check(epoch);
    final byId = {
      for (final summary in accounts) summary.account.id: summary.account,
    };
    final mapped = <PublicId, Account>{};
    for (final entry in accountMapping.entries) {
      final account = byId[entry.value];
      if (account == null) {
        throw const ExchangeException('target_account_missing');
      }
      mapped[entry.key] = account;
    }
    final preview = SimpleImportPreview.prepare(
      batch: batch,
      destinationWorkspace: _workspace!,
      accountMapping: mapped,
    );
    _check(epoch);
    return SimpleImportReview._(preview, this, session, epoch);
  });

  Future<SimpleImportResult> confirmSimpleImport(SimpleImportReview review) =>
      _exclusive((epoch) async {
        _require();
        if (!identical(review._owner, this) ||
            !identical(review._session, _session) ||
            review._epoch != epoch ||
            review.preview.destinationWorkspace != _workspace) {
          throw PreviewInvalid();
        }
        await _requireNoDraft();
        _check(epoch);
        _importActive = true;
        try {
          final result = await _session!.importSimple(review.preview);
          _check(epoch);
          return result;
        } finally {
          _importActive = false;
        }
      });
}
