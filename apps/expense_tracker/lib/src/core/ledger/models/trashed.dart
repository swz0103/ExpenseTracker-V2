import 'package:ledger_entries/model.dart' show Entry;

/// An entry deleted on [on], kept for a while to be restored.
final class Trashed {
  const Trashed(this.entry, this.on, {this.order, this.letGo});

  final Entry entry;
  final DateTime on;

  /// Where the entry stood in the order written, for it to come back to
  /// (D75); null when not known, and it comes back last.
  final int? order;

  /// The day of its recurring item the entry settled when it was deleted,
  /// which the deletion let go; null when it settled none, or when it was
  /// deleted before this was kept. Putting the entry back takes that day
  /// off the let-go days again, and no other.
  final DateTime? letGo;
}
