import 'dart:convert';

/// The photo of each entry's receipt, by entry id: a file name the phone
/// keeps. Plain state; the ledger decides when a change is kept.
final class Receipts {
  Receipts([Map<String, String> from = const {}]) : _byEntry = {...from};

  final Map<String, String> _byEntry;

  /// The photo of the entry with [id]; null when none.
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

  /// Every photo kept, deleted entries' included.
  Iterable<String> get files => _byEntry.values;

  /// Takes the photos of [other], as when the book is read again.
  void replaceWith(Receipts other) {
    _byEntry
      ..clear()
      ..addAll(other._byEntry);
  }
}

/// The forms put aside in the composer, as JSON by tab, kept across a
/// restart of the app. Plain state, like [Receipts].
final class Drafts {
  Drafts([Map<String, String> from = const {}]) : _byTab = {...from};

  final Map<String, String> _byTab;

  String? of(String tab) => _byTab[tab];

  /// Keeps the form put aside on [tab], or clears it when [json] is null.
  /// Whether that changed anything.
  bool set(String tab, String? json) {
    if (_byTab[tab] == json) return false;
    if (json == null) {
      _byTab.remove(tab);
    } else {
      _byTab[tab] = json;
    }
    return true;
  }

  /// The receipt photos the forms put aside have chosen, so they are not
  /// swept away before the form is taken up again.
  Iterable<String> get receipts sync* {
    for (final json in _byTab.values) {
      try {
        final file = (jsonDecode(json) as Map<String, Object?>)['receipt'];
        if (file is String) yield file;
      } on Object {
        // A form that cannot be read keeps no photo.
      }
    }
  }

  void replaceWith(Drafts other) {
    _byTab
      ..clear()
      ..addAll(other._byTab);
  }
}
