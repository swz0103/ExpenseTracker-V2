import 'package:ledger_entries/model.dart' show Entry;

/// An entry deleted on [on], kept for a while to be restored.
final class Trashed {
  const Trashed(this.entry, this.on, {this.order});

  final Entry entry;
  final DateTime on;

  /// Where the entry stood in the order written, for it to come back to
  /// (D75); null when not known, and it comes back last.
  final int? order;
}
