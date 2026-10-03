import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

Matcher fails(NoteError code) =>
    throwsA(isA<NoteException>().having((e) => e.code, 'code', code));

void main() {
  final entry = PublicId.generate();

  test('a note changes only from the revision it was written against', () {
    const empty = EntryNote(0, '');
    final first = NoteChange(entry, 0, '午餐和同事').apply(empty);
    expect(first.revision, 1);
    expect(first.text, '午餐和同事');
    expect(
      () => NoteChange(entry, 0, '別的').apply(first),
      fails(NoteError.conflict),
    );
    expect(
      () => NoteChange(entry, 1, '午餐和同事').apply(first),
      fails(NoteError.unchanged),
    );
    expect(NoteChange(entry, 1, '').apply(first).revision, 2);
  });

  test('text and revision bounds are enforced', () {
    expect(NoteChange(entry, 0, '字' * 1024).text.runes.length, 1024);
    expect(
      () => NoteChange(entry, 0, '字' * 1025),
      fails(NoteError.invalidText),
    );
    expect(
      () => NoteChange(entry, 0, 'a\u0000b'),
      fails(NoteError.invalidText),
    );
    expect(
      () => NoteChange(entry, 0, String.fromCharCode(0xd800)),
      fails(NoteError.invalidText),
    );
    expect(() => NoteChange(entry, -1, ''), fails(NoteError.invalidRevision));
    expect(
      () => NoteChange(entry, 2147483647, ''),
      fails(NoteError.invalidRevision),
    );
  });

  test('stored input round trips and anything else is refused', () {
    final change = NoteChange(entry, 3, '備註');
    final again = NoteChange.fromInput(change.input);
    expect(again.input, change.input);
    for (final input in [
      ['note-v2', entry.value, 3, '備註'],
      ['note-v1', entry.value, '3', '備註'],
      'note-v1',
    ]) {
      expect(() => NoteChange.fromInput(input), fails(NoteError.invalidText));
    }
  });
}
