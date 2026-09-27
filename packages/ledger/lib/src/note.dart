import 'package:foundation_values/foundation_values.dart';

enum NoteError {
  invalidText,
  invalidRevision,
  conflict,
  unchanged,
  missingEntry,
}

final class NoteException implements Exception {
  const NoteException(this.code);
  final NoteError code;
  @override
  String toString() => 'NoteException(${code.name})';
}

/// Version zero denotes an entry that has never had a note.
final class EntryNote {
  const EntryNote(this.revision, this.text);
  final int revision;
  final String text;
}

final class NoteChange {
  NoteChange(this.entryId, this.expectedRevision, this.text) {
    if (expectedRevision < 0 || expectedRevision >= 2147483647) {
      throw const NoteException(NoteError.invalidRevision);
    }
    validateText(text);
  }
  static const maxCharacters = 1024;
  static void validateText(String text) {
    if (text.runes.length > maxCharacters ||
        text.runes.any((r) => r == 0 || (r >= 0xd800 && r <= 0xdfff))) {
      throw const NoteException(NoteError.invalidText);
    }
  }

  factory NoteChange.fromInput(Object? input) => switch (input) {
    ['note-v1', String id, int revision, String text] => NoteChange(
      PublicId.parse(id),
      revision,
      text,
    ),
    _ => throw const NoteException(NoteError.invalidText),
  };
  final PublicId entryId;
  final int expectedRevision;
  final String text;
  List<Object> get input => ['note-v1', entryId.value, expectedRevision, text];
  EntryNote apply(EntryNote previous) {
    if (previous.revision != expectedRevision)
      throw const NoteException(NoteError.conflict);
    if (previous.text == text) throw const NoteException(NoteError.unchanged);
    return EntryNote(expectedRevision + 1, text);
  }
}
