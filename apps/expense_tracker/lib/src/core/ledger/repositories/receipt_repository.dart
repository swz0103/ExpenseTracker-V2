/// What the screens may ask of the receipt photos.
abstract interface class ReceiptReader {
  /// The photo of the entry with [id]; null when none.
  String? of(String id);

  /// Every photo kept, deleted entries' included.
  Iterable<String> get files;
}

/// The photo of each entry's receipt, by entry id: a file name the phone
/// keeps. Plain state; the ledger decides when a change is kept.
final class ReceiptRepository implements ReceiptReader {
  ReceiptRepository([Map<String, String> from = const {}])
    : _byEntry = {...from};

  final Map<String, String> _byEntry;

  @override
  String? of(String id) => _byEntry[id];

  /// Gives the entry with [id] the photo [file], or takes its photo away
  /// when null. Whether that changed anything.
  bool set(String id, String? file) {
    if (_byEntry[id] == file) return false;
    if (file == null) {
      _byEntry.remove(id);
    } else {
      _byEntry[id] = file;
    }
    return true;
  }

  @override
  Iterable<String> get files => _byEntry.values;

  /// Takes the photos of [other], as when the book is read again.
  void replaceWith(ReceiptRepository other) {
    _byEntry
      ..clear()
      ..addAll(other._byEntry);
  }
}
