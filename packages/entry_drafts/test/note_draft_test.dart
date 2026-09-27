import 'package:entry_drafts/entry_drafts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final id = PublicId.generate(), event = PublicId.generate();
  final op = OperationKey(
    WorkspaceId(PublicId.generate()),
    OperationId(PublicId.generate()),
  );
  EntryFields fields(String text, {int revision = 0}) => EntryFields(
    income: false,
    amount: '',
    date: '',
    noteOf: event,
    noteRevision: revision,
    noteText: text,
  );
  test(
    'raw and frozen note drafts retain Unicode whitespace and clear versions',
    () {
      for (final text in ['  備註\n🙂  ', '🙂' * 1024, '\u0001' * 1024, '']) {
        final d = EntryDraft(
          id: id,
          operation: op,
          fields: fields(text, revision: 1),
        );
        final frozen = d.prepareNote(NoteChange(event, 1, text));
        expect(EntryDraft.decode(d.encode()).encode(), d.encode());
        expect(EntryDraft.decode(frozen.encode()).encode(), frozen.encode());
        expect(frozen.isPrepared, true);
        expect(() => frozen.edit(fields('other')), throwsStateError);
        expect(
          () => d.prepareNote(NoteChange(event, 0, text)),
          throwsFormatException,
        );
        expect(
          () => d.prepareNote(NoteChange(PublicId.generate(), 1, text)),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'invalid scalar text, versions, no-op and mixed financial modes fail',
    () {
      for (final text in ['🙂' * 1025, '\u0000', String.fromCharCode(0xd800)]) {
        expect(() => fields(text), throwsA(isA<NoteException>()));
      }
      expect(() => NoteChange(event, -1, 'x'), throwsA(isA<NoteException>()));
      expect(
        () => NoteChange(event, 0, '').apply(const EntryNote(0, '')),
        throwsA(isA<NoteException>()),
      );
      expect(
        () => NoteChange(event, 0, 'x').apply(const EntryNote(1, 'y')),
        throwsA(isA<NoteException>()),
      );
      expect(
        () => EntryFields(income: true, amount: '1', date: '', noteOf: event),
        throwsFormatException,
      );
      expect(
        () => EntryFields(
          income: false,
          amount: '',
          date: '',
          noteText: 'orphan',
        ),
        throwsFormatException,
      );
    },
  );
}
