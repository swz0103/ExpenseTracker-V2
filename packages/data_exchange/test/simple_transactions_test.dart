import 'dart:convert';

import 'package:data_exchange/data_exchange.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final twd = Currency('TWD', 2);
  final jpy = Currency('JPY', 0);
  final workspace = WorkspaceId(PublicId.generate());
  final cash = PublicId.generate();
  final bank = PublicId.generate();

  SimpleTransaction row({
    PostingKind kind = PostingKind.expense,
    String note = '',
    Currency? currency,
    PublicId? account,
  }) => SimpleTransaction(
    sourceRecordId: PublicId.generate(),
    date: BusinessDate(2026, 9, 28),
    kind: kind,
    accountId: account ?? cash,
    amount: Money(currency ?? twd, BigInt.from(12345)),
    note: note,
  );

  test('JSON and CSV preserve exact identities, currency scales and notes', () {
    final batch = SimpleTransactionBatch(workspace, [
      row(note: '=SUM(1,1), "早餐"\r\n下一行'),
      row(kind: PostingKind.income, currency: jpy, account: bank),
    ]);
    for (final pair in [
      (SimpleTransactionCodec.encodeJson, SimpleTransactionCodec.decodeJson),
      (SimpleTransactionCodec.encodeCsv, SimpleTransactionCodec.decodeCsv),
    ]) {
      final encoded = pair.$1(batch);
      final decoded = pair.$2(encoded);
      expect(decoded.sourceWorkspace, workspace);
      expect(decoded.records, hasLength(2));
      for (var i = 0; i < 2; i++) {
        expect(
          decoded.records[i].sourceRecordId,
          batch.records[i].sourceRecordId,
        );
        expect(decoded.records[i].accountId, batch.records[i].accountId);
        expect(decoded.records[i].date, batch.records[i].date);
        expect(decoded.records[i].kind, batch.records[i].kind);
        expect(decoded.records[i].amount, batch.records[i].amount);
        expect(decoded.records[i].note, batch.records[i].note);
      }
    }
    final csv = SimpleTransactionCodec.encodeCsv(batch);
    expect(csv, contains('""=SUM(1,1)'));
    expect(csv, contains('\r\n'));
  });

  test(
    'JSON rejects unknown version, malformed money and repeated source ID',
    () {
      final good = jsonDecode(
        SimpleTransactionCodec.encodeJson(
          SimpleTransactionBatch(workspace, [row()]),
        ),
      ) as Map<String, dynamic>;
      expect(
        () => SimpleTransactionCodec.decodeJson(
          jsonEncode({...good, 'version': 2}),
        ),
        throwsA(isA<ExchangeException>()),
      );
      final records = good['records'] as List;
      final first = records.single as Map<String, dynamic>;
      for (final changed in [
        {...first, 'currency': 'WRONG'},
        {...first, 'scale': -1},
        {...first, 'minorUnits': '0'},
        {...first, 'date': '2026-02-30'},
        {...first, 'kind': 'transfer'},
        {...first, 'extra': 'silent data loss'},
      ]) {
        expect(
          () => SimpleTransactionCodec.decodeJson(
            jsonEncode({
              ...good,
              'records': [changed],
            }),
          ),
          throwsA(isA<ExchangeException>()),
        );
      }
      expect(
        () => SimpleTransactionCodec.decodeJson(
          jsonEncode({
            ...good,
            'records': [first, first],
          }),
        ),
        throwsA(
          isA<ExchangeException>().having((error) => error.row, 'row', 2),
        ),
      );
      expect(
        () => SimpleTransactionCodec.decodeJson(
          jsonEncode({
            ...good,
            'records': [
              {...first, 'minorUnits': '0'},
            ],
          }),
        ),
        throwsA(
          isA<ExchangeException>().having((error) => error.row, 'row', 1),
        ),
      );
    },
  );

  test('CSV rejects mixed workspaces, extra columns and malformed quoting', () {
    final csv = SimpleTransactionCodec.encodeCsv(
      SimpleTransactionBatch(workspace, [row(), row()]),
    );
    final other = WorkspaceId(PublicId.generate());
    expect(
      () => SimpleTransactionCodec.decodeCsv(
        csv.replaceFirst(workspace.toString(), other.toString()),
      ),
      throwsA(isA<ExchangeException>()),
    );
    expect(
      () => SimpleTransactionCodec.decodeCsv(
        csv.replaceFirst('note_json', 'unknown'),
      ),
      throwsA(isA<ExchangeException>()),
    );
    expect(
      () => SimpleTransactionCodec.decodeCsv('$csv"unterminated'),
      throwsA(isA<ExchangeException>()),
    );
    expect(
      () => SimpleTransactionCodec.decodeCsv(
        csv.replaceFirst(',expense,', ',expense,extra,'),
      ),
      throwsA(isA<ExchangeException>()),
    );
  });

  test('empty JSON remains explicit; CSV cannot lose its source workspace', () {
    final empty = SimpleTransactionBatch(workspace, []);
    expect(
      SimpleTransactionCodec.decodeJson(
        SimpleTransactionCodec.encodeJson(empty),
      ).records,
      isEmpty,
    );
    expect(
      () => SimpleTransactionCodec.encodeCsv(empty),
      throwsA(isA<ExchangeException>()),
    );
  });

  test('bounded staging rejects overlong notes, nonpositive amounts and oversized input', () {
    expect(() => row(note: '界' * 1366), throwsA(isA<ExchangeException>()));
    expect(
      () => SimpleTransaction(
        sourceRecordId: PublicId.generate(),
        date: BusinessDate(2026, 9, 28),
        kind: PostingKind.income,
        accountId: cash,
        amount: Money(twd, BigInt.zero),
      ),
      throwsA(isA<ExchangeException>()),
    );
    expect(
      () => SimpleTransactionCodec.decodeJson(
        ' ' * (SimpleTransactionCodec.maxBytes + 1),
      ),
      throwsA(isA<ExchangeException>()),
    );
  });

  test('batch capacity and unsupported financial kinds fail before import', () {
    expect(
      () => SimpleTransactionBatch(workspace, [
        for (var i = 0; i <= SimpleTransactionBatch.maxRecords; i++) row(),
      ]),
      throwsA(isA<ExchangeException>()),
    );
    expect(
      () => row(kind: PostingKind.transfer),
      throwsA(isA<ExchangeException>()),
    );
  });
}
