import 'dart:convert';

import 'package:entry_drafts/entry_drafts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final ws = WorkspaceId(PublicId.generate()), c = Currency('TWD', 2);
  PostingAccount account(int version) => PostingAccount(
    id: PublicId.generate(),
    workspace: ws,
    currency: version == 7 ? Currency('JPY', 0) : c,
    expectedVersion: version,
  );
  final source = account(3), dest = account(7);
  EntryDraft draft() => EntryDraft(
    id: PublicId.generate(),
    operation: OperationKey(ws, OperationId(PublicId.generate())),
    fields: EntryFields(
      income: false,
      transfer: true,
      amount: '12+',
      fee: '.',
      received: '7+',
      date: '2026-',
      accountId: source.id,
      destinationId: dest.id,
    ),
  );
  test('partial transfer draft and frozen both-account versions round trip without loss', () {
    final d = draft();
    expect(EntryDraft.decode(d.encode()).encode(), d.encode());
    final frozen = d.prepare(
      EntrySubmission(
        Posting.transfer(
          id: d.id,
          operation: d.operation,
          date: BusinessDate(2026, 9, 27),
          source: source,
          destination: dest,
          principal: Money.parse(c, '900719925474.09'),
          fee: Money.parse(c, '1.23'),
          received: Money.parse(Currency('JPY', 0), '9007199254740993'),
        ),
      ),
    );
    final decoded = EntryDraft.decode(frozen.encode());
    expect(decoded.encode(), frozen.encode());
    expect(
      decoded.submission!.posting.legs.map((l) => l.account.expectedVersion),
      [3, 7, 3],
    );
    expect(decoded.submission!.posting.reportIncome.minorUnits, BigInt.zero);
    expect(() => decoded.edit(d.fields), throwsStateError);
  });
  test('transfer fields reject income metadata and oversize fee; ordinary drafts reject transfer fields', () {
    for (final fields in [
      () => EntryFields(income: true, transfer: true, amount: '', date: ''),
      () => EntryFields(
        income: false,
        transfer: true,
        amount: '',
        date: '',
        tags: [source.id],
      ),
      () => EntryFields(
        income: false,
        transfer: true,
        amount: '',
        date: '',
        fee: 'x' * 129,
      ),
      () => EntryFields(
        income: false,
        amount: '',
        date: '',
        destinationId: dest.id,
      ),
    ]) {
      expect(fields, throwsFormatException);
    }
  });
  test('wrong draft kind, unknown version and currency mismatch cannot decode as transfer', () {
    final d = draft();
    final frozen = d.prepare(
      EntrySubmission(
        Posting.transfer(
          id: d.id,
          operation: d.operation,
          date: BusinessDate(2026, 9, 27),
          source: source,
          destination: dest,
          principal: Money.parse(c, '2'),
          received: Money.parse(Currency('JPY', 0), '1'),
        ),
      ),
    );
    final data = jsonDecode(frozen.encode()) as List;
    data[0] = 'manual-entry-v1';
    expect(() => EntryDraft.decode(jsonEncode(data)), throwsA(anything));
    data[0] = 'manual-fx-transfer-v1';
    data[5][3][1] = 'TWD';
    data[5][3][2] = 2;
    expect(() => EntryDraft.decode(jsonEncode(data)), throwsA(anything));
  });
}
