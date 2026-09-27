import 'dart:convert';

import 'package:entry_drafts/entry_drafts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final ws = WorkspaceId(PublicId.generate()),
      original = PublicId.generate(),
      category = PublicId.generate();
  final c = Currency('TWD', 2);
  for (final foreign in [false, true]) {
    test(
      'refund $foreign raw and frozen payload keeps source, selections and exact currencies',
      () {
        final a = PostingAccount(
          id: PublicId.generate(),
          workspace: ws,
          currency: foreign ? Currency('JPY', 0) : c,
          expectedVersion: 7,
        );
        final d = EntryDraft(
          id: PublicId.generate(),
          operation: OperationKey(ws, OperationId(PublicId.generate())),
          fields: EntryFields(
            income: false,
            refundOf: original,
            amount: '2+',
            date: '2026-',
            accountId: a.id,
            received: foreign ? '31+' : null,
            splits: [SplitFields(categoryId: category, amount: '2+')],
          ),
        );
        expect(EntryDraft.decode(d.encode()).encode(), d.encode());
        final command = Posting.refund(
          id: d.id,
          operation: d.operation,
          date: BusinessDate(2026, 9, 28),
          account: a,
          originalId: original,
          amount: Money.parse(c, '2'),
          received: foreign ? Money.parse(a.currency, '310') : null,
          allocations: [
            Allocation(
              category,
              Money.parse(c, '2'),
              expectedCategoryVersion: 3,
            ),
          ],
        );
        final frozen = d.prepare(
          EntrySubmission(
            command,
            tags: [TagSelection(PublicId.generate(), 2)],
            merchant: MerchantSelection(PublicId.generate(), 4),
          ),
        );
        final decoded = EntryDraft.decode(frozen.encode());
        expect(decoded.encode(), frozen.encode());
        expect(decoded.submission!.posting.refundOf, original);
        expect(decoded.submission!.posting.reportExpense, Money.parse(c, '-2'));
        expect(
          decoded.submission!.posting.legs.single.account.expectedVersion,
          7,
        );
        final data = jsonDecode(frozen.encode()) as List;
        data[4][0] = PublicId.generate().value;
        expect(
          () => EntryDraft.decode(jsonEncode(data)),
          throwsFormatException,
        );
        data[0] = 'manual-entry-v1';
        expect(() => EntryDraft.decode(jsonEncode(data)), throwsA(anything));
      },
    );
  }
  test('refund raw fields reject unrelated editable metadata and transfer controls', () {
    for (final make in [
      () => EntryFields(income: true, refundOf: original, amount: '', date: ''),
      () => EntryFields(
        income: false,
        transfer: true,
        refundOf: original,
        amount: '',
        date: '',
      ),
      () => EntryFields(
        income: false,
        split: true,
        refundOf: original,
        amount: '',
        date: '',
      ),
      () => EntryFields(
        income: false,
        tags: [category],
        refundOf: original,
        amount: '',
        date: '',
      ),
      () => EntryFields(
        income: false,
        merchantId: category,
        refundOf: original,
        amount: '',
        date: '',
      ),
    ]) {
      expect(make, throwsFormatException);
    }
  });
}
