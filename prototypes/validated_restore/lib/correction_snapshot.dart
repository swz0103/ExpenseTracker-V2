part of 'snapshot.dart';

/// A portable correction must link the exact original, inverse, replacement,
/// and the two independent financial receipts. Other reversals may stand alone.
typedef _CorrectionReceiptLink = ({
  String original,
  String reversal,
  String replacement,
  String role,
});

Future<Map<(String, String), _CorrectionReceiptLink>>
_validateCorrectionHistory(
  ProbeDatabase db,
  List<QueryRow> events,
  Map<(String, String), ({String original, String reason})> reversalLinks,
) async {
  final byId = {
    for (final event in events)
      (event.read<String>('workspace'), event.read<String>('id')): event,
  };
  final receipts = <(String, String), List<QueryRow>>{};
  final links = <(String, String), _CorrectionReceiptLink>{};
  for (final row
      in await db
          .customSelect(
            'SELECT r.workspace,r.operation_id,r.result_id,a.entity_id,a.kind FROM receipts r JOIN audit a ON a.workspace=r.workspace AND a.operation_id=r.operation_id',
          )
          .get()) {
    // A later note revision or tombstone may reuse the event as its result ID.
    // Only the event's financial posting receipt proves a correction link.
    if (!const {
      'ledger.income',
      'ledger.expense',
      'ledger.transfer',
      'ledger.reversal',
    }.contains(row.read<String>('kind'))) {
      continue;
    }
    (receipts[(
              row.read<String>('workspace'),
              row.read<String>('result_id'),
            )] ??=
            [])
        .add(row);
  }
  for (final row
      in await db.customSelect('SELECT * FROM event_corrections').get()) {
    final ws = row.read<String>('workspace');
    final originalId = row.read<String>('original_id');
    final reversalId = row.read<String>('reversal_id');
    final replacementId = row.read<String>('replacement_id');
    final original = byId[(ws, originalId)];
    final inverse = byId[(ws, reversalId)];
    final replacement = byId[(ws, replacementId)];
    if (original == null ||
        inverse == null ||
        replacement == null ||
        ![
          'income',
          'expense',
          'transfer',
        ].contains(original.read<String>('kind')) ||
        inverse.read<String>('kind') != 'reversal' ||
        replacement.read<String>('kind') != original.read<String>('kind') ||
        inverse.read<String>('business_date') !=
            original.read<String>('business_date') ||
        reversalLinks[(ws, reversalId)]?.original != originalId) {
      throw const InvalidSnapshot();
    }
    final originalReceipt = receipts[(ws, originalId)];
    final inverseReceipt = receipts[(ws, reversalId)];
    final replacementReceipt = receipts[(ws, replacementId)];
    if (originalReceipt?.length != 1 ||
        inverseReceipt?.length != 1 ||
        replacementReceipt?.length != 1) {
      throw const InvalidSnapshot();
    }
    final originalOperation = originalReceipt!.single.read<String>(
      'operation_id',
    );
    final inverseOperation = inverseReceipt!.single.read<String>(
      'operation_id',
    );
    final replacementOperation = replacementReceipt!.single.read<String>(
      'operation_id',
    );
    if (originalOperation == inverseOperation ||
        originalOperation == replacementOperation ||
        inverseOperation == replacementOperation ||
        originalReceipt.single.read<String>('entity_id') != originalId ||
        originalReceipt.single.read<String>('kind') !=
            'ledger.${original.read<String>('kind')}' ||
        inverseReceipt.single.read<String>('entity_id') != reversalId ||
        inverseReceipt.single.read<String>('kind') != 'ledger.reversal' ||
        replacementReceipt.single.read<String>('entity_id') != replacementId ||
        replacementReceipt.single.read<String>('kind') !=
            'ledger.${replacement.read<String>('kind')}') {
      throw const InvalidSnapshot();
    }
    if (links.containsKey((ws, reversalId)) ||
        links.containsKey((ws, replacementId))) {
      throw const InvalidSnapshot();
    }
    links[(ws, reversalId)] = (
      original: originalId,
      reversal: reversalId,
      replacement: replacementId,
      role: 'reversal',
    );
    links[(ws, replacementId)] = (
      original: originalId,
      reversal: reversalId,
      replacement: replacementId,
      role: 'replacement',
    );
  }
  return links;
}
