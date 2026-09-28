import 'dart:convert';

import 'package:entry_drafts/entry_drafts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final workspace = WorkspaceId(PublicId.generate());
  final usd = Currency('USD', 2), jpy = Currency('JPY', 0);
  final date = BusinessDate(2026, 9, 28);
  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));
  PostingAccount account(Currency currency) => PostingAccount(
    id: PublicId.generate(),
    workspace: workspace,
    currency: currency,
    expectedVersion: 2,
  );
  final a = account(usd), b = account(jpy);

  for (final transfer in [false, true]) {
    test(
      'correction draft freezes a complete ${transfer ? 'FX' : 'expense'} pair',
      () {
        final original = transfer
            ? Posting.transfer(
                id: PublicId.generate(),
                operation: op(),
                date: date,
                source: a,
                destination: b,
                principal: Money.parse(usd, '10'),
                received: Money.parse(jpy, '1500'),
                fee: Money.parse(usd, '0.10'),
              )
            : Posting.expense(
                id: PublicId.generate(),
                operation: op(),
                date: date,
                account: a,
                amount: Money.parse(usd, '10'),
                allocations: [
                  Allocation(
                    PublicId.generate(),
                    Money.parse(usd, '10'),
                    expectedCategoryVersion: 3,
                  ),
                ],
              );
        final draft = EntryDraft(
          id: PublicId.generate(),
          operation: op(),
          fields: EntryFields(
            income: false,
            transfer: transfer,
            correctionOf: original.id,
            correctionReason: '金額輸入錯誤',
            amount: '7',
            date: '2026-10-01',
            accountId: a.id,
            destinationId: transfer ? b.id : null,
            fee: transfer ? '0.05' : '0',
            received: transfer ? '1100' : null,
          ),
        );
        expect(EntryDraft.decode(draft.encode()).encode(), draft.encode());
        final replacement = transfer
            ? Posting.transfer(
                id: draft.id,
                operation: draft.operation,
                date: BusinessDate(2026, 10, 1),
                source: a,
                destination: b,
                principal: Money.parse(usd, '7'),
                received: Money.parse(jpy, '1100'),
                fee: Money.parse(usd, '0.05'),
              )
            : Posting.expense(
                id: draft.id,
                operation: draft.operation,
                date: BusinessDate(2026, 10, 1),
                account: a,
                amount: Money.parse(usd, '7'),
              );
        final frozen = draft.prepareCorrection(
          CorrectionSubmission(
            PostingCorrection(
              original: original,
              replacement: replacement,
              reversalId: PublicId.generate(),
              reversalOperation: op(),
              reason: draft.fields.correctionReason,
            ),
          ),
        );
        expect(EntryDraft.decode(frozen.encode()).encode(), frozen.encode());
        final wrongOriginal = jsonDecode(frozen.encode()) as List;
        wrongOriginal[4][0] = PublicId.generate().value;
        expect(
          () => EntryDraft.decode(jsonEncode(wrongOriginal)),
          throwsFormatException,
        );
        final wrongRole = jsonDecode(frozen.encode()) as List;
        wrongRole[5][0] = 'ordinary-event';
        expect(
          () => EntryDraft.decode(jsonEncode(wrongRole)),
          throwsFormatException,
        );
      },
    );
  }

  test('correction fields cannot mix other commands or unbounded reason', () {
    final id = PublicId.generate();
    for (final make in [
      () => EntryFields(
        income: false,
        amount: '1',
        date: '',
        correctionReason: 'x',
      ),
      () => EntryFields(
        income: false,
        amount: '1',
        date: '',
        correctionOf: id,
        refundOf: id,
      ),
      () => EntryFields(
        income: false,
        amount: '1',
        date: '',
        correctionOf: id,
        correctionReason: '字' * 257,
      ),
    ]) {
      expect(make, throwsFormatException);
    }
  });

  test('maximum split, tags and reason fit the encrypted draft bound', () {
    final categories = [for (var i = 0; i < 16; i++) PublicId.generate()];
    final tagIds = [for (var i = 0; i < 16; i++) PublicId.generate()];
    final allocations = [
      for (final id in categories)
        Allocation(id, Money.parse(usd, '1'), expectedCategoryVersion: 1),
    ];
    Posting expense(PublicId id, OperationKey operation) => Posting.expense(
      id: id,
      operation: operation,
      date: date,
      account: a,
      amount: Money.parse(usd, '16'),
      allocations: allocations,
    );
    final original = expense(PublicId.generate(), op());
    final draft = EntryDraft(
      id: PublicId.generate(),
      operation: op(),
      fields: EntryFields(
        income: false,
        split: true,
        correctionOf: original.id,
        correctionReason: '字' * 256,
        amount: '16',
        date: date.toString(),
        accountId: a.id,
        splits: [
          for (final id in categories) SplitFields(categoryId: id, amount: '1'),
        ],
        tags: tagIds,
      ),
    );
    final frozen = draft.prepareCorrection(
      CorrectionSubmission(
        PostingCorrection(
          original: original,
          replacement: expense(draft.id, draft.operation),
          reversalId: PublicId.generate(),
          reversalOperation: op(),
          reason: draft.fields.correctionReason,
        ),
        tags: [for (final id in tagIds) TagSelection(id, 1)],
      ),
    );
    final encoded = frozen.encode();
    expect(utf8.encode(encoded).length, lessThanOrEqualTo(16384));
    expect(EntryDraft.decode(encoded).encode(), encoded);
  });
}
