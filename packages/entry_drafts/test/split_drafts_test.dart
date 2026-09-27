import 'dart:convert';

import 'package:entry_drafts/entry_drafts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final w = WorkspaceId(PublicId.generate());
  final account = PostingAccount(
    id: PublicId.generate(),
    workspace: w,
    currency: Currency('TWD', 2),
    expectedVersion: 3,
  );
  final cats = [PublicId.generate(), PublicId.generate()];
  EntryDraft draft({List<SplitFields>? rows}) => EntryDraft(
    id: PublicId.generate(),
    operation: OperationKey(w, OperationId(PublicId.generate())),
    fields: EntryFields(
      income: false,
      split: true,
      amount: '10',
      date: '2026-09-28',
      accountId: account.id,
      splits:
          rows ??
          [
            SplitFields(categoryId: cats[0], amount: '3.25'),
            SplitFields(categoryId: cats[1], amount: '6.75'),
          ],
    ),
  );
  test('raw incomplete split text round trips unchanged without a command', () {
    final d = draft(
      rows: [
        SplitFields(categoryId: cats[0], amount: '1+'),
        SplitFields(amount: ''),
      ],
    );
    final copy = EntryDraft.decode(d.encode());
    expect(copy.encode(), d.encode());
    expect(copy.fields.splits[0].amount, '1+');
    expect(copy.submission, null);
    expect(() => copy.fields.splits.clear(), throwsUnsupportedError);
  });
  test('frozen split stores each exact amount and version, never the whole total per row', () {
    final d = draft();
    final prepared = d.prepare(
      EntrySubmission(
        Posting.expense(
          id: d.id,
          operation: d.operation,
          date: BusinessDate(2026, 9, 28),
          account: account,
          amount: Money.parse(account.currency, '10'),
          allocations: [
            Allocation(
              cats[0],
              Money.parse(account.currency, '3.25'),
              expectedCategoryVersion: 2,
            ),
            Allocation(
              cats[1],
              Money.parse(account.currency, '6.75'),
              expectedCategoryVersion: 7,
            ),
          ],
        ),
      ),
    );
    final decoded = EntryDraft.decode(prepared.encode());
    expect(decoded.encode(), prepared.encode());
    expect(
      decoded.submission!.posting.allocations.map(
        (a) => a.amount.minorUnits.toInt(),
      ),
      [325, 675],
    );
    expect(
      decoded.submission!.posting.allocations.map(
        (a) => a.expectedCategoryVersion,
      ),
      [2, 7],
    );
    expect(() => decoded.submission!.toJson(), throwsFormatException);
    final json = jsonDecode(prepared.encode()) as List;
    json[0] = 'manual-entry-v1';
    expect(() => EntryDraft.decode(jsonEncode(json)), throwsFormatException);
    json[0] = 'manual-split-entry-v1';
    ((json[5] as List)[4] as List)[0][2] = '326';
    expect(
      () => EntryDraft.decode(jsonEncode(json)),
      throwsA(isA<LedgerException>()),
    );
  });
  test('split has a bounded staging footprint and cannot mix transfer or single category', () {
    expect(
      () => EntryFields(
        income: false,
        split: true,
        categoryId: cats[0],
        amount: '',
        date: '',
      ),
      throwsFormatException,
    );
    expect(
      () => EntryFields(
        income: false,
        split: true,
        transfer: true,
        amount: '',
        date: '',
      ),
      throwsFormatException,
    );
    expect(
      () => EntryFields(
        income: false,
        splits: [SplitFields(amount: '')],
        amount: '',
        date: '',
      ),
      throwsFormatException,
    );
    expect(
      () => draft(rows: List.generate(17, (_) => SplitFields(amount: '1'))),
      throwsFormatException,
    );
    final d = draft(
      rows: List.generate(
        16,
        (_) => SplitFields(categoryId: PublicId.generate(), amount: '界' * 128),
      ),
    );
    expect(utf8.encode(d.encode()).length, lessThan(16384));
    expect(EntryDraft.decode(d.encode()).fields.splits.length, 16);
  });
}
