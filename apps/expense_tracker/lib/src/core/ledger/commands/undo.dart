import '../models/models.dart';

/// How to take back a change just made, from the 復原 of the note that
/// tells it (D82): what can be undone is not asked first. Meant to run
/// once, right after; a record changed again since is left as it is.
typedef Undo = void Function();

/// What a change did to entries, kept so that [Undo] can put them back:
/// each entry as it was, and as the change left it, by id.
final class EntryImages {
  final _before = <String, Entry>{};
  final _after = <String, Entry>{};

  /// [change], noting each entry it changes.
  Entry? Function(Entry) noting(Entry? Function(Entry) change) => (e) {
    final next = change(e);
    if (next != null) {
      _before[e.id] = e;
      _after[e.id] = next;
    }
    return next;
  };

  /// The entry [e] was before the change, when it still is as the change
  /// left it; null for any other.
  Entry? back(Entry e) => identical(_after[e.id], e) ? _before[e.id] : null;

  /// Whether the change touched no entry.
  bool get isEmpty => _after.isEmpty;
}
