import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'database.dart';
import 'merchants_adapter.dart';

Future<int?> validatePostingMerchant(
  ProbeDatabase db,
  Posting posting,
  MerchantSelection? merchant,
) async {
  if (merchant == null) return null;
  if (!db.merchantsAware ||
      ![PostingKind.income, PostingKind.expense].contains(posting.kind)) {
    throw UnsupportedError('Merchant requires schema 7 and income or expense.');
  }
  final adapter = MerchantsAdapter(db);
  (await adapter.read(posting.operation.workspace)).requireSelection(
    workspace: posting.operation.workspace,
    id: merchant.id,
    expectedVersion: merchant.expectedVersion,
  );
  return adapter.currentSequence(posting.operation.workspace);
}

Future<void> insertPostingMerchant(
  ProbeDatabase db,
  WorkspaceId workspace,
  PublicId event,
  MerchantSelection? merchant,
  int? sequence,
) async {
  if (merchant == null) return;
  await db.customStatement('INSERT INTO event_merchants VALUES(?,?,?,?,?)', [
    workspace.toString(),
    event.value,
    merchant.id.value,
    merchant.expectedVersion,
    sequence,
  ]);
}
