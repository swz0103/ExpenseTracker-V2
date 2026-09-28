import 'dart:convert';

import 'package:entry_drafts/entry_drafts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final workspace = WorkspaceId(PublicId.generate());
  final usd = Currency('USD', 2), jpy = Currency('JPY', 0);
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
      'deletion draft freezes ${transfer ? 'FX transfer' : 'split expense'} and rejects tampering',
      () {
        final original = transfer
            ? Posting.transfer(
                id: PublicId.generate(),
                operation: op(),
                date: BusinessDate(2026, 9, 28),
                source: a,
                destination: b,
                principal: Money.parse(usd, '10'),
                received: Money.parse(jpy, '1500'),
                fee: Money.parse(usd, '0.10'),
              )
            : Posting.expense(
                id: PublicId.generate(),
                operation: op(),
                date: BusinessDate(2026, 9, 28),
                account: a,
                amount: Money.parse(usd, '10'),
                allocations: [
                  Allocation(
                    PublicId.generate(),
                    Money.parse(usd, '4'),
                    expectedCategoryVersion: 3,
                  ),
                  Allocation(
                    PublicId.generate(),
                    Money.parse(usd, '6'),
                    expectedCategoryVersion: 3,
                  ),
                ],
              );
        final draft = EntryDraft(
          id: original.id,
          operation: op(),
          fields: EntryFields(
            income: false,
            amount: '',
            date: '',
            tombstoneOf: original.id,
            tombstoneReason: '重複',
          ),
        );
        expect(EntryDraft.decode(draft.encode()).encode(), draft.encode());
        final frozen = draft.prepareTombstone(
          TombstoneSubmission(
            PostingTombstone(
              original: original,
              operation: draft.operation,
              reason: draft.fields.tombstoneReason,
            ),
          ),
        );
        expect(EntryDraft.decode(frozen.encode()).encode(), frozen.encode());
        final wrongId = jsonDecode(frozen.encode()) as List;
        wrongId[4][0] = PublicId.generate().value;
        expect(
          () => EntryDraft.decode(jsonEncode(wrongId)),
          throwsFormatException,
        );
        final wrongOperation = jsonDecode(frozen.encode()) as List;
        wrongOperation[5][1] = draft.operation.operation.toString();
        expect(
          () => EntryDraft.decode(jsonEncode(wrongOperation)),
          throwsA(isA<LedgerException>()),
        );
      },
    );
  }
  test('deletion draft cannot carry another operation or oversized reason', () {
    final id = PublicId.generate();
    expect(
      () => EntryFields(income: false, amount: '1', date: '', tombstoneOf: id),
      throwsFormatException,
    );
    expect(
      () => EntryFields(
        income: false,
        amount: '',
        date: '',
        tombstoneOf: id,
        tombstoneReason: 'x' * 257,
      ),
      throwsFormatException,
    );
  });
}
