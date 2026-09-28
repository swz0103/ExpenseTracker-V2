part of 'snapshot.dart';

typedef _TombstoneLink = ({String original, String reason, Object facts});

/// Validate the authority marker independently of its operation receipt.
/// The receipt loop later consumes each exact operation and rejects extras.
Future<Map<(String, String), _TombstoneLink>> _validateTombstoneHistory(
  ProbeDatabase db,
) async {
  final links = <(String, String), _TombstoneLink>{};
  for (final row
      in await db.customSelect('SELECT * FROM event_tombstones').get()) {
    final ws = row.read<String>('workspace');
    final original = row.read<String>('event_id');
    final operation = row.read<String>('operation_id');
    final reason = row.read<String>('reason');
    if (reason != reason.trim() || reason.runes.length > 256) {
      throw const InvalidSnapshot();
    }
    final ReversalSourceRecord source;
    try {
      source = await readReversalSource(
        db,
        WorkspaceId.parse(ws),
        PublicId.parse(original),
        allowTombstoned: true,
      );
    } catch (_) {
      throw const InvalidSnapshot();
    }
    if (source.posting.operation.operation.toString() == operation ||
        links.containsKey((ws, operation))) {
      throw const InvalidSnapshot();
    }
    links[(ws, operation)] = (
      original: original,
      reason: reason,
      facts: immutablePostingFacts(source.posting),
    );
  }
  return links;
}
