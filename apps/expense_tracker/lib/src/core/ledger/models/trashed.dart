import 'entry.dart';

/// An entry deleted on [on], kept for a while to be restored.
final class Trashed {
  const Trashed(this.entry, this.on);

  final Entry entry;
  final DateTime on;
}
