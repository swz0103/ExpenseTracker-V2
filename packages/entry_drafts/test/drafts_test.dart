import 'dart:convert';

import 'package:entry_drafts/entry_drafts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final ws = WorkspaceId(PublicId.generate());
  EntryDraft draft(EntryFields fields) => EntryDraft(
    id: PublicId.generate(),
    operation: OperationKey(ws, OperationId(PublicId.generate())),
    fields: fields,
  );
  test('incomplete and invalid financial text round trips without posting', () {
    final d = draft(EntryFields(income: false, amount: '12.', date: '2026-'));
    expect(EntryDraft.decode(d.encode()).encode(), d.encode());
    expect(d.submission, isNull);
    expect(d.edit(EntryFields(income: true, amount: '', date: '')).id, d.id);
  });
  test('bounds and duplicate tags reject, input collections are immutable', () {
    final id = PublicId.generate();
    expect(
      () => EntryFields(income: false, amount: 'x' * 129, date: ''),
      throwsFormatException,
    );
    expect(
      () => EntryFields(income: false, amount: '', date: 'x' * 33),
      throwsFormatException,
    );
    expect(
      () => EntryFields(income: false, amount: '', date: '', tags: [id, id]),
      throwsFormatException,
    );
    expect(
      () => EntryFields(
        income: false,
        amount: '',
        date: '',
        tags: List.generate(17, (_) => PublicId.generate()),
      ),
      throwsFormatException,
    );
    final tags = [id];
    final f = EntryFields(income: false, amount: '', date: '', tags: tags);
    tags.clear();
    expect(f.tags, [id]);
    expect(() => f.tags.clear(), throwsUnsupportedError);
  });
  test(
    'frozen command preserves identity, versions and exact minor amount',
    () {
      final d = draft(
        EntryFields(
          income: true,
          amount: '900719925474.09',
          date: '2026-09-27',
        ),
      );
      final currency = Currency('TWD', 2);
      final amount = Money.parse(currency, d.fields.amount);
      final p = Posting.income(
        id: d.id,
        operation: d.operation,
        date: BusinessDate(2026, 9, 27),
        account: PostingAccount(
          id: PublicId.generate(),
          workspace: ws,
          currency: currency,
          expectedVersion: 3,
        ),
        amount: amount,
        allocations: [
          Allocation(PublicId.generate(), amount, expectedCategoryVersion: 7),
        ],
      );
      final prepared = d.prepare(
        EntrySubmission(
          p,
          tags: [TagSelection(PublicId.generate(), 4)],
          merchant: MerchantSelection(PublicId.generate(), 9),
        ),
      );
      final read = EntryDraft.decode(prepared.encode());
      expect(read.encode(), prepared.encode());
      expect(
        read.submission!.posting.reportIncome.minorUnits,
        amount.minorUnits,
      );
      expect(() => read.edit(d.fields), throwsStateError);
    },
  );
  test(
    'unknown versions, extra fields and invalid submitted shapes reject',
    () {
      final d = draft(EntryFields(income: false, amount: '', date: ''));
      final values = jsonDecode(d.encode()) as List;
      expect(
        () => EntryDraft.decode(jsonEncode([...values, 1])),
        throwsFormatException,
      );
      values[0] = 'manual-entry-v2';
      expect(
        () => EntryDraft.decode(jsonEncode(values)),
        throwsFormatException,
      );
      expect(() => EntryDraft.decode(' ' * 16385), throwsFormatException);
    },
  );
}
