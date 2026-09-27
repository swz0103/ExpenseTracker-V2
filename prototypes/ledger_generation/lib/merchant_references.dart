part of 'ledger_store.dart';

final class SavedMerchantReference {
  const SavedMerchantReference(this.id, this.version, this.sequence);
  final PublicId id;
  final int version, sequence;
}

extension MerchantReferences on LedgerSession {
  Future<SavedMerchantReference?> merchantFor(
    WorkspaceId workspace,
    PublicId event,
  ) => _enqueue(() async {
    if (!_db.merchantsAware)
      throw UnsupportedError('Merchants require schema 7.');
    final rows = await _db
        .customSelect(
          'SELECT merchant_id,merchant_version,merchant_sequence FROM event_merchants WHERE workspace=? AND event_id=? ORDER BY merchant_id',
          variables: [
            Variable.withString(workspace.toString()),
            Variable.withString(event.value),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    final row = rows.single;
    return SavedMerchantReference(
      PublicId.parse(row.read<String>('merchant_id')),
      row.read<int>('merchant_version'),
      row.read<int>('merchant_sequence'),
    );
  });
}
