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
  final root = Directory('.dart_tool/reversal-session-tests')
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
  Posting reverse({Posting? source}) => Posting.reversal(
    id: PublicId.generate(),
    operation: operation(),
    date: BusinessDate(2026, 9, 28),
    original: source ?? original,
    reason: '輸入錯誤',
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
      reversalsAware: true,
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

  test('split reversal inherits archived attribution, retries once, restores and keeps activity family', () async {
    final p = reverse();
    await store.withSession((s) async {
      await s.archiveCategory(operation(), food, 1, archived: true);
      await s.archiveTag(operation(), tag, 1, archived: true);
      await s.archiveMerchant(operation(), merchant, 1, archived: true);
      final results = await Future.wait(List.generate(12, (_) => post(s, p)));
      expect(results.where((r) => !r.replayed), hasLength(1));
      expect(
        (await s.accounts(ws)).singleWhere((r) => r.account.id == a.id).balance,
        m('100'),
      );
      final e = (await s.entry(ws, p.id))!;
      expect(e.reversalOf, original.id);
      expect(e.reversalReason, '輸入錯誤');
      expect((await s.entry(ws, original.id))!.reversedBy, p.id);
      expect((await s.activity(ws, p.id)).map((r) => r.entry.id).toSet(), {
        p.id,
        original.id,
      });
      expect(await s.allocations(ws, p.id), hasLength(2));
      final before = await s.snapshot();
      await expectLater(post(s, reverse()), throwsA(isA<LedgerException>()));
      await expectLater(
        s.refundStatus(ws, original.id),
        throwsA(isA<LedgerException>()),
      );
      await expectLater(
        s.post(
          Posting.refund(
            id: PublicId.generate(),
            operation: operation(),
            date: original.date,
            account: ref(a),
            originalId: original.id,
            amount: m('1'),
            allocations: [alloc(food, '1')],
          ),
          tags: [TagSelection(tag, 1)],
          merchant: MerchantSelection(merchant, 1),
        ),
        throwsA(isA<LedgerException>()),
      );
      expect(await s.snapshot(), before);
      expect((await post(s, p)).replayed, true);
    });
    final bytes = await store.snapshot();
    expect(validateSessionCapacity(bytes, reversalsAware: true), bytes);
    final keys = FixtureKeySlots(Directory('${work.path}/target-keys'));
    final target = LedgerStore(
      Directory('${work.path}/target'),
      keys,
      catalogProtection: fixtureCatalogProtection(keys),
      reversalsAware: true,
    );
    await target.generations.install(utf8.decode(bytes), op());
    expect(await target.snapshot(), bytes);
  });
  test('income and same/FX transfers reverse every principal and fee, with unchanged original rate', () async {
    await store.withSession((s) async {
      final c = account();
      await s.createAccount(c, opening(c));
      final before = await s.accounts(ws);
      final sources = [
        Posting.income(
          id: PublicId.generate(),
          operation: operation(),
          date: original.date,
          account: ref(a),
          amount: m('12.34'),
        ),
        Posting.transfer(
          id: PublicId.generate(),
          operation: operation(),
          date: original.date,
          source: ref(a),
          destination: ref(c),
          principal: m('5'),
          fee: m('0.03'),
        ),
        Posting.transfer(
          id: PublicId.generate(),
          operation: operation(),
          date: original.date,
          source: ref(a),
          destination: ref(b),
          principal: m('7'),
          received: Money.parse(b.currency, '1051'),
          fee: m('0.02'),
        ),
      ];
      for (final source in sources) {
        await s.post(source);
        final ready = await s.reversalSource(ws, source.id);
        final inverse = reverse(source: ready.posting);
        await s.post(inverse);
        expect((await s.post(inverse)).replayed, true);
        expect((await s.activity(ws, inverse.id)), hasLength(2));
      }
      expect(
        {for (final x in await s.accounts(ws)) x.account.id: x.balance},
        {for (final x in before) x.account.id: x.balance},
      );
      final bytes = await s.snapshot();
      final tables = (jsonDecode(utf8.decode(bytes)) as Map)['tables'];
      final fx = tables['event_fx'] as List;
      expect(fx, hasLength(2));
      expect(fx[0]['context'], fx[1]['context']);
    });
  });
  test('dependent refund and forged original financial facts or selections cannot reverse', () async {
    await store.withSession((s) async {
      final before = await s.snapshot();
      final fake = Posting.expense(
        id: original.id,
        operation: original.operation,
        date: original.date,
        account: ref(a),
        amount: m('11'),
        allocations: [alloc(food, '7'), alloc(travel, '4')],
      );
      await expectLater(
        post(s, reverse(source: fake)),
        throwsA(isA<LedgerException>()),
      );
      await expectLater(s.post(reverse()), throwsA(isA<LedgerException>()));
      expect(await s.snapshot(), before);
      await post(
        s,
        Posting.refund(
          id: PublicId.generate(),
          operation: operation(),
          date: original.date,
          account: ref(a),
          originalId: original.id,
          amount: m('1'),
          allocations: [alloc(food, '1')],
        ),
      );
      final refunded = await s.snapshot();
      await expectLater(post(s, reverse()), throwsA(isA<LedgerException>()));
      expect(await s.snapshot(), refunded);
    });
  });
  test('competing independent reversal commands accept exactly one', () async {
    await store.withSession((s) async {
      final result = await Future.wait(
        [reverse(), reverse()].map((p) async {
          try {
            await post(s, p);
            return true;
          } on LedgerException {
            return false;
          }
        }),
      );
      expect(result.where((x) => x), hasLength(1));
      expect(
        (await s.accounts(ws)).singleWhere((r) => r.account.id == a.id).balance,
        m('100'),
      );
      await s.snapshot();
    });
  });
  test('altered link, reason, amount, attribution, date or receipt rejects restore without publication', () async {
    final p = reverse();
    await store.withSession((s) => post(s, p));
    final before = await store.snapshot();
    final mutations = <void Function(Map)>[
      (t) => (t['event_reversals'] as List).clear(),
      (t) => (t['event_reversals'] as List).single['original_id'] = p.id.value,
      (t) => (t['event_reversals'] as List).single['reason'] = '不同原因',
      (t) => (t['events'] as List).singleWhere(
        (r) => r['id'] == p.id.value,
      )['expense'] = '-999',
      (t) => (t['events'] as List).singleWhere(
        (r) => r['id'] == p.id.value,
      )['business_date'] = '2026-09-26',
      (t) => (t['legs'] as List).singleWhere(
        (r) => r['event_id'] == p.id.value,
      )['amount'] = '999',
      (t) => (t['allocations'] as List).firstWhere(
        (r) => r['event_id'] == p.id.value,
      )['amount'] = '500',
      (t) => (t['event_tags'] as List).removeWhere(
        (r) => r['event_id'] == p.id.value,
      ),
      (t) => (t['event_merchants'] as List).removeWhere(
        (r) => r['event_id'] == p.id.value,
      ),
      (t) {
        final r = (t['receipts'] as List).singleWhere(
          (r) => r['result_id'] == p.id.value,
        );
        final input = jsonDecode(r['input']);
        r['input'] = jsonEncode(input[1]);
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
  test('maximum split/tag inheritance and 256 four-byte characters fit write and restore budgets', () async {
    await store.withSession((s) async {
      final cats = [for (var i = 0; i < 16; i++) PublicId.generate()];
      final tags = [for (var i = 0; i < 16; i++) PublicId.generate()];
      for (var i = 0; i < 16; i++) {
        await s.createCategory(
          operation(),
          cats[i],
          'max category $i',
          CategoryKind.expense,
        );
        await s.createTag(operation(), tags[i], 'max tag $i');
      }
      final total = Money.maxMinorUnits - BigInt.from(15);
      final source = Posting.expense(
        id: PublicId.generate(),
        operation: operation(),
        date: original.date,
        account: ref(a),
        amount: Money(currency, total),
        allocations: [
          for (final cat in cats)
            Allocation(
              cat,
              Money(currency, total ~/ BigInt.from(16)),
              expectedCategoryVersion: 1,
            ),
        ],
      );
      final selected = [for (final tag in tags) TagSelection(tag, 1)];
      await s.post(
        source,
        tags: selected,
        merchant: MerchantSelection(merchant, 1),
      );
      final inverse = Posting.reversal(
        id: PublicId.generate(),
        operation: operation(),
        date: original.date,
        original: source,
        reason: '😀' * 256,
      );
      await s.post(
        inverse,
        tags: selected,
        merchant: MerchantSelection(merchant, 1),
      );
      expect(
        (await s.post(
          inverse,
          tags: selected,
          merchant: MerchantSelection(merchant, 1),
        )).replayed,
        true,
      );
      final bytes = await s.snapshot();
      final tables = (jsonDecode(utf8.decode(bytes)) as Map)['tables'];
      final receipt = (tables['receipts'] as List).singleWhere(
        (r) => r['result_id'] == inverse.id.value,
      );
      expect(utf8.encode(jsonEncode(receipt)).length, greaterThan(4096));
      expect(validateSessionCapacity(bytes, reversalsAware: true), bytes);
      expect(
        (await s.accounts(ws)).singleWhere((r) => r.account.id == a.id).balance,
        m('90'),
      );
    });
    final before = await store.snapshot();
    await store.generations.install(utf8.decode(before), op());
    expect(await store.snapshot(), before);
  });
}
