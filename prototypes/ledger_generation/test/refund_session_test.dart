import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:test/test.dart';

import 'session_test.dart' show op, ws, currency, account, ref, opening;

void main() {
  final root = Directory('.dart_tool/refund-session-tests')
    ..createSync(recursive: true);
  late Directory work;
  late LedgerStore store;
  late Account a, b;
  late PublicId food, travel, tag, merchant;
  late Posting original;
  Money m(String n) => Money.parse(currency, n);
  OperationKey operation() => OperationKey(ws, op());
  Allocation alloc(PublicId id, String n) =>
      Allocation(id, m(n), expectedCategoryVersion: 1);
  Posting refund({
    String amount = '2',
    String foodAmount = '2',
    String? travelAmount,
    PostingAccount? destination,
    String? received,
    PublicId? source,
    OperationKey? operationKey,
  }) => Posting.refund(
    id: PublicId.generate(),
    operation: operationKey ?? operation(),
    date: BusinessDate(2026, 9, 28),
    account: destination ?? ref(a),
    originalId: source ?? original.id,
    amount: m(amount),
    received: received == null ? null : Money.parse(b.currency, received),
    allocations: [
      if (foodAmount != '0') alloc(food, foodAmount),
      if (travelAmount != null) alloc(travel, travelAmount),
    ],
  );
  Future<dynamic> post(LedgerSession s, Posting p) => s.post(
    p,
    tags: [TagSelection(tag, 1)],
    merchant: MerchantSelection(merchant, 1),
  );
  setUp(() async {
    work = root.createTempSync('case-');
    final keys = FixtureKeySlots(Directory('${work.path}/keys'));
    store = LedgerStore(
      Directory('${work.path}/store'),
      keys,
      catalogProtection: fixtureCatalogProtection(keys),
      refundsAware: true,
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
    food = PublicId.generate();
    travel = PublicId.generate();
    tag = PublicId.generate();
    merchant = PublicId.generate();
    original = Posting.expense(
      id: PublicId.generate(),
      operation: operation(),
      date: BusinessDate(2026, 9, 27),
      account: ref(a),
      amount: m('10'),
      allocations: [alloc(food, '6'), alloc(travel, '4')],
    );
    await store.withSession((s) async {
      await s.createAccount(a, opening(a));
      await s.createAccount(
        b,
        Posting.opening(
          id: PublicId.generate(),
          operation: operation(),
          date: b.openedOn,
          account: ref(b),
          amount: Money.parse(b.currency, '0'),
        ),
      );
      await s.createCategory(operation(), food, 'food', CategoryKind.expense);
      await s.createCategory(
        operation(),
        travel,
        'travel',
        CategoryKind.expense,
      );
      await s.createTag(operation(), tag, 'tag');
      await s.createMerchant(operation(), merchant, 'merchant');
      await post(s, original);
    });
  });
  tearDown(() {
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    work.deleteSync(recursive: true);
  });
  test('atomic partial/FX/full refunds retain source metadata and duplicate operations replay once', () async {
    final first = refund();
    await store.withSession((s) async {
      final results = await Future.wait(
        List.generate(12, (_) => post(s, first)),
      );
      expect(results.where((r) => !r.replayed), hasLength(1));
      await s.archiveCategory(operation(), food, 1, archived: true);
      await s.archiveTag(operation(), tag, 1, archived: true);
      await s.archiveMerchant(operation(), merchant, 1, archived: true);
      final last = refund(
        amount: '8',
        foodAmount: '4',
        travelAmount: '4',
        destination: ref(b),
        received: '1234',
      );
      await post(s, last);
      expect((await s.refundStatus(ws, original.id)).budget.remaining, m('0'));
      final entry = (await s.entry(ws, last.id))!;
      expect(entry.refundOf, original.id);
      expect(entry.refunded, m('8'));
      expect(entry.amount, Money.parse(b.currency, '1234'));
      expect((await s.entries(ws, limit: 1)).single.refundOf, original.id);
      expect((await post(s, first)).replayed, true);
      final before = await s.snapshot();
      await expectLater(post(s, refund()), throwsA(isA<LedgerException>()));
      expect(await s.snapshot(), before);
      expect(
        (await s.accounts(ws)).singleWhere((r) => r.account.id == a.id).balance,
        m('92'),
      );
      expect(
        (await s.accounts(ws)).singleWhere((r) => r.account.id == b.id).balance,
        Money.parse(b.currency, '1234'),
      );
    });
    final bytes = await store.snapshot();
    expect(validateSessionCapacity(bytes, refundsAware: true), bytes);
    final targetKeys = FixtureKeySlots(Directory('${work.path}/target-keys'));
    final target = LedgerStore(
      Directory('${work.path}/target'),
      targetKeys,
      catalogProtection: fixtureCatalogProtection(targetKeys),
      refundsAware: true,
    );
    await target.generations.install(utf8.decode(bytes), op());
    expect(await target.snapshot(), bytes);
  });
  test('over-category, changed operation, missing source and altered metadata roll back fully', () async {
    final p = refund();
    await store.withSession((s) async {
      await post(s, p);
      final before = await s.snapshot();
      for (final bad in [
        refund(amount: '5', foodAmount: '5'),
        refund(source: PublicId.generate()),
        refund(amount: '3', foodAmount: '3', operationKey: p.operation),
      ]) {
        await expectLater(post(s, bad), throwsA(anything));
        expect(await s.snapshot(), before);
      }
      await expectLater(s.post(refund()), throwsA(isA<LedgerException>()));
      expect(await s.snapshot(), before);
      expect((await post(s, p)).replayed, true);
    });
  });
  test('tampered source/amount/date/attribution/receipt/FX never replaces active generation', () async {
    final p = refund(destination: ref(b), received: '300');
    await store.withSession((s) => post(s, p));
    final before = await store.snapshot();
    final mutations = <void Function(Map)>[
      (t) => (t['event_refunds'] as List).clear(),
      (t) => (t['event_refunds'] as List).single['original_id'] = p.id.value,
      (t) => (t['event_refunds'] as List).single['original_id'] =
          PublicId.generate().value,
      (t) => (t['events'] as List).singleWhere(
        (r) => r['id'] == p.id.value,
      )['expense'] = '-700',
      (t) => (t['events'] as List).singleWhere(
        (r) => r['id'] == p.id.value,
      )['business_date'] = '2026-09-26',
      (t) => (t['events'] as List).singleWhere(
        (r) => r['id'] == p.id.value,
      )['income'] = '200',
      (t) => (t['event_tags'] as List).removeWhere(
        (r) => r['event_id'] == p.id.value,
      ),
      (t) => (t['event_merchants'] as List).removeWhere(
        (r) => r['event_id'] == p.id.value,
      ),
      (t) => (t['allocations'] as List).singleWhere(
        (r) => r['event_id'] == p.id.value,
      )['category_id'] = travel.value,
      (t) => (t['event_fx'] as List).clear(),
      (t) {
        final row = (t['receipts'] as List).singleWhere(
          (r) => r['result_id'] == p.id.value,
        );
        final data = jsonDecode(row['input'] as String) as List;
        row['input'] = jsonEncode(data[1]);
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
  });
  test(
    'competing independent refunds share one atomic category limit',
    () async {
      await store.withSession((s) async {
        final a = refund(amount: '6', foodAmount: '6'),
            b = refund(amount: '6', foodAmount: '6');
        final outcomes = await Future.wait(
          [a, b].map((p) async {
            try {
              await post(s, p);
              return true;
            } on LedgerException {
              return false;
            }
          }),
        );
        expect(outcomes.where((ok) => ok), hasLength(1));
        expect(
          (await s.refundStatus(ws, original.id)).budget.remaining,
          m('4'),
        );
        expect(
          (await s.entries(ws)).where((e) => e.kind == PostingKind.refund),
          hasLength(1),
        );
      });
    },
  );
  test('unclassified maximum Money refund stays exact across partial and complete refunds', () async {
    await store.withSession((s) async {
      final source = Posting.expense(
        id: PublicId.generate(),
        operation: operation(),
        date: BusinessDate(2026, 9, 27),
        account: ref(a),
        amount: Money(currency, Money.maxMinorUnits),
      );
      await s.post(source);
      for (final amount in [BigInt.one, Money.maxMinorUnits - BigInt.one]) {
        await s.post(
          Posting.refund(
            id: PublicId.generate(),
            operation: operation(),
            date: BusinessDate(2026, 9, 28),
            account: ref(a),
            originalId: source.id,
            amount: Money(currency, amount),
          ),
        );
      }
      expect(
        (await s.refundStatus(ws, source.id)).budget.remaining.minorUnits,
        BigInt.zero,
      );
      expect(
        (await s.accounts(ws)).singleWhere((r) => r.account.id == a.id).balance,
        m('90'),
      );
      await s.snapshot();
    });
    final bytes = await store.snapshot();
    await store.generations.install(utf8.decode(bytes), op());
    expect(await store.snapshot(), bytes);
  });
}
