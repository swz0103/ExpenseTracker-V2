import 'dart:convert';

import 'package:entry_drafts/entry_drafts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final ws = WorkspaceId(PublicId.generate()),
      c = Currency('USD', 2),
      date = BusinessDate(2026, 9, 28);
  OperationKey op() => OperationKey(ws, OperationId(PublicId.generate()));
  PostingAccount account(Currency currency) => PostingAccount(
    id: PublicId.generate(),
    workspace: ws,
    currency: currency,
    expectedVersion: 7,
  );
  final a = account(c), b = account(Currency('JPY', 0));
  for (final transfer in [false, true]) {
    test(
      'reversal frozen roundtrip retains split/FX source and partial raw reason $transfer',
      () {
        final p = transfer
            ? Posting.transfer(
                id: PublicId.generate(),
                operation: op(),
                date: date,
                source: a,
                destination: b,
                principal: Money.parse(c, '2'),
                received: Money.parse(b.currency, '310'),
                fee: Money.parse(c, '0.01'),
              )
            : Posting.expense(
                id: PublicId.generate(),
                operation: op(),
                date: date,
                account: a,
                amount: Money.parse(c, '2'),
                allocations: [
                  for (var i = 0; i < 2; i++)
                    Allocation(
                      PublicId.generate(),
                      Money.parse(c, '1'),
                      expectedCategoryVersion: 3,
                    ),
                ],
              );
        final d = EntryDraft(
          id: PublicId.generate(),
          operation: op(),
          fields: EntryFields(
            income: false,
            amount: '',
            date: '2026-',
            reversalOf: p.id,
            reversalReason: ' 尚未完成 ',
          ),
        );
        expect(EntryDraft.decode(d.encode()).encode(), d.encode());
        final frozen = d.prepare(
          EntrySubmission(
            Posting.reversal(
              id: d.id,
              operation: d.operation,
              date: date,
              original: p,
              reason: '尚未完成',
            ),
            tags: transfer ? [] : [TagSelection(PublicId.generate(), 2)],
          ),
        );
        expect(EntryDraft.decode(frozen.encode()).encode(), frozen.encode());
        final bad = jsonDecode(frozen.encode()) as List;
        bad[4][0] = PublicId.generate().value;
        expect(() => EntryDraft.decode(jsonEncode(bad)), throwsFormatException);
        bad[0] = 'manual-entry-v1';
        expect(() => EntryDraft.decode(jsonEncode(bad)), throwsA(anything));
      },
    );
  }
  test('reversal fields cannot hide editable money or account and metadata controls', () {
    final id = PublicId.generate();
    for (final make in [
      () => EntryFields(income: true, amount: '', date: '', reversalOf: id),
      () => EntryFields(income: false, amount: '1', date: '', reversalOf: id),
      () => EntryFields(
        income: false,
        amount: '',
        date: '',
        reversalOf: id,
        accountId: id,
      ),
      () => EntryFields(
        income: false,
        amount: '',
        date: '',
        reversalOf: id,
        refundOf: id,
      ),
      () => EntryFields(
        income: false,
        amount: '',
        date: '',
        reversalOf: id,
        reversalReason: '字' * 257,
      ),
      () => EntryFields(
        income: false,
        amount: '',
        date: '',
        reversalReason: 'reason',
      ),
    ])
      expect(make, throwsFormatException);
  });
}
