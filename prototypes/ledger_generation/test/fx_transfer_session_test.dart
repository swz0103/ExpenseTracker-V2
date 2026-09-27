import 'package:storage_generation_probe/fixture_catalog_protection.dart';

import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:validated_restore_probe/snapshot.dart';
import 'package:test/test.dart';

import 'session_test.dart' show op, ws, currency, account, ref, opening;

Money? listedReceived(List<LedgerEntry> rows) => rows.single.received;

void main() {
  final root = Directory('.dart_tool/fx-transfer-session-tests')
    ..createSync(recursive: true);
  late Directory work;
  late LedgerStore store;
  late Account a, b;
  Posting transfer({String fee = '1.25', PostingAccount? destination}) =>
      Posting.transfer(
        id: PublicId.generate(),
        operation: OperationKey(ws, op()),
        date: BusinessDate(2026, 9, 27),
        source: ref(a),
        destination: destination ?? ref(b),
        principal: Money.parse(currency, '20'),
        fee: Money.parse(currency, fee),
        received: Money.parse(Currency('JPY', 0), '95'),
      );
  setUp(() async {
    work = root.createTempSync('case-');
    final keys = FixtureKeySlots(Directory('${work.path}/keys'));
    store = LedgerStore(
      Directory('${work.path}/store'),
      keys,
      catalogProtection: fixtureCatalogProtection(keys),
      fxTransfersAware: true,
    );
    await store.initialize(op());
    a = account();
    b = Account.open(
      id: PublicId.generate(),
      workspace: ws,
      name: 'JPY',
      kind: AccountKind.bank,
      currency: Currency('JPY', 0),
      openedOn: a.openedOn,
    );
    await store.withSession((s) async {
      await s.createAccount(a, opening(a));
      await s.createAccount(
        b,
        Posting.opening(
          id: PublicId.generate(),
          operation: OperationKey(ws, op()),
          date: b.openedOn,
          account: ref(b),
          amount: Money.parse(b.currency, '100'),
        ),
      );
    });
  });
  tearDown(() {
    if (!work.absolute.path.startsWith(
      '${root.absolute.path}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    work.deleteSync(recursive: true);
  });
  test('one operation preserves both sides, fee reports, paginated detail and retry identity', () async {
    final p = transfer();
    await store.withSession((s) async {
      final results = await Future.wait(List.generate(12, (_) => s.post(p)));
      expect(results.where((r) => !r.replayed), hasLength(1));
      final rows = await s.accounts(ws);
      expect(
        rows.singleWhere((r) => r.account.id == a.id).balance.minorUnits,
        BigInt.from(7875),
      );
      expect(
        rows.singleWhere((r) => r.account.id == b.id).balance.minorUnits,
        BigInt.from(195),
      );
      final entry = (await s.entry(ws, p.id))!;
      expect(entry.destinationId, b.id);
      expect(entry.received, Money.parse(b.currency, '95'));
      expect(listedReceived(await s.entries(ws, limit: 1)), entry.received);
      expect(entry.fee!.minorUnits, BigInt.from(125));
      expect(entry.amount.minorUnits, BigInt.from(-2000));
      final listed = (await s.entries(ws, limit: 1)).single;
      expect(listed.id, entry.id);
      expect(listed.destinationId, b.id);
      expect(listed.fee, entry.fee);
      expect(await s.entries(ws, before: listed, limit: 1), hasLength(1));
    });
    final bytes = await store.snapshot();
    expect(validateSessionCapacity(bytes, fxTransfersAware: true), bytes);
    expect(
      () => SnapshotCodec(transfersAware: true).canonicalize(bytes),
      throwsA(isA<InvalidSnapshot>()),
    );
    final tables = (jsonDecode(utf8.decode(bytes)) as Map)['tables'] as Map;
    final event = (tables['events'] as List).singleWhere(
      (r) => r['id'] == p.id.value,
    );
    expect(event['income'], '0');
    expect(event['expense'], '125');
    expect(tables['legs'], hasLength(5));
    expect(tables['receipts'], hasLength(3));
    expect(tables['audit'], hasLength(3));
  });
  test('destination version/missing account failure changes neither side; queue still accepts zero fee', () async {
    final before = await store.snapshot();
    await store.withSession((s) async {
      for (final target in [
        PostingAccount(
          id: b.id,
          workspace: ws,
          currency: b.currency,
          expectedVersion: 2,
        ),
        PostingAccount(
          id: PublicId.generate(),
          workspace: ws,
          currency: b.currency,
          expectedVersion: 1,
        ),
      ]) {
        await expectLater(
          s.post(transfer(destination: target)),
          throwsA(anything),
        );
        expect(await s.snapshot(), before);
      }
      await s.post(transfer(fee: '0'));
    });
    final bytes = await store.snapshot();
    expect(validateSessionCapacity(bytes, fxTransfersAware: true), bytes);
    expect(
      ((jsonDecode(utf8.decode(bytes)) as Map)['tables'] as Map)['legs'],
      hasLength(4),
    );
  });
  test('portable admission rejects orphan/missing transfer legs and metadata is not silently applied', () async {
    final p = transfer();
    await store.withSession((s) async {
      final before = await s.snapshot();
      await expectLater(
        s.post(p, tags: [TagSelection(PublicId.generate(), 1)]),
        throwsUnsupportedError,
      );
      expect(await s.snapshot(), before);
      await s.post(p);
    });
    final parsed = jsonDecode(utf8.decode(await store.snapshot())) as Map;
    (parsed['tables']['legs'] as List).removeWhere(
      (l) => l['event_id'] == p.id.value && l['ordinal'] != '0',
    );
    expect(
      () => validateSessionCapacity(
        utf8.encode(jsonEncode(parsed)),
        fxTransfersAware: true,
      ),
      throwsA(isA<PreviewCapacity>()),
    );
  });
  test('tampered currency, FX basis/ratio, missing relation and receipt mismatch never replace active ledger', () async {
    final p = transfer();
    await store.withSession((s) => s.post(p));
    final before = await store.snapshot();
    final mutations = <void Function(Map)>[
      (t) => (t['event_fx'] as List).clear(),
      (t) {
        final row = (t['event_fx'] as List).single;
        final c = jsonDecode(row['context'] as String) as Map;
        c['basis'] = 'provider';
        row['context'] = jsonEncode(c);
      },
      (t) {
        final row = (t['event_fx'] as List).single;
        final c = jsonDecode(row['context'] as String) as Map;
        c['rate']['numerator'] = '96';
        row['context'] = jsonEncode(c);
      },
      (t) {
        final row = (t['legs'] as List).singleWhere(
          (r) => r['event_id'] == p.id.value && r['ordinal'] == '1',
        );
        row['amount'] = '96';
      },
      (t) {
        final row = (t['legs'] as List).singleWhere(
          (r) => r['event_id'] == p.id.value && r['ordinal'] == '1',
        );
        row['currency'] = 'USD';
      },
      (t) {
        final row = (t['receipts'] as List).singleWhere(
          (r) => r['result_id'] == p.id.value,
        );
        final data = jsonDecode(row['input'] as String) as List;
        row['input'] = jsonEncode(data[1]);
      },
      (t) {
        final row = (t['event_fx'] as List).single;
        row['event_id'] = PublicId.generate().value;
      },
    ];
    for (final mutate in mutations) {
      final parsed = jsonDecode(utf8.decode(before)) as Map;
      mutate(parsed['tables'] as Map);
      await expectLater(
        store.generations.install(jsonEncode(parsed), op()),
        throwsA(anything),
      );
      expect(await store.snapshot(), before);
    }
    await store.withSession((s) async {
      final changed = Posting.transfer(
        id: PublicId.generate(),
        operation: p.operation,
        date: p.date,
        source: ref(a),
        destination: ref(b),
        principal: Money.parse(currency, '20'),
        received: Money.parse(b.currency, '96'),
        fee: Money.parse(currency, '1.25'),
      );
      await expectLater(s.post(changed), throwsA(anything));
      expect(await s.snapshot(), before);
      expect((await s.post(p)).replayed, isTrue);
    });
  });
}
