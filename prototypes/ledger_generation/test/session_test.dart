import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:test/test.dart';

OperationId op() => OperationId(PublicId.generate());
final ws = WorkspaceId.parse('019f0000-0000-7000-8000-000000000000');
final other = WorkspaceId.parse('019f0000-0000-7000-8000-000000000099');
final currency = Currency('TWD', 2);
Account account() => Account.open(
  id: PublicId.generate(),
  workspace: ws,
  name: '日常帳戶',
  kind: AccountKind.cash,
  currency: currency,
  openedOn: BusinessDate(2006, 1, 1),
);
PostingAccount ref(Account a) => PostingAccount(
  id: a.id,
  workspace: a.workspace,
  currency: a.currency,
  expectedVersion: a.version,
);
Posting opening(Account a) => Posting.opening(
  id: PublicId.generate(),
  operation: OperationKey(ws, op()),
  date: a.openedOn,
  account: ref(a),
  amount: Money.parse(currency, '100'),
);
Posting income(
  Account a, {
  String amount = '1',
  BusinessDate? date,
  OperationId? operation,
}) => Posting.income(
  id: PublicId.generate(),
  operation: OperationKey(ws, operation ?? op()),
  date: date ?? BusinessDate(2026, 9, 27),
  account: ref(a),
  amount: Money.parse(currency, amount),
);

void main() {
  final root = Directory('.dart_tool/session-tests')
    ..createSync(recursive: true);
  late Directory directory;
  late LedgerStore store;
  setUp(() {
    directory = root.createTempSync('case-');
    store = LedgerStore(
      Directory('${directory.path}/store'),
      FixtureKeySlots(Directory('${directory.path}/keys')),
    );
  });
  tearDown(() {
    if (!directory.absolute.path.startsWith(
      '${root.absolute.path}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    directory.deleteSync(recursive: true);
  });
  test(
    'single entry lookup is scoped to workspace and agrees with paged history',
    () async {
      await store.initialize(op());
      final a = account();
      final initial = opening(a), posted = income(a, amount: '12.34');
      late LedgerSession closed;
      await store.withSession((session) async {
        closed = session;
        await session.createAccount(a, initial);
        await session.post(posted);
        final row = (await session.entry(ws, posted.id))!;
        final listed = (await session.entries(ws)).first;
        expect(row.id, listed.id);
        expect(row.accountId, a.id);
        expect(row.kind, PostingKind.income);
        expect(row.date.toString(), posted.date.toString());
        expect(row.amount, Money.parse(currency, '12.34'));
        expect(await session.entry(other, posted.id), isNull);
        expect(await session.entry(ws, PublicId.generate()), isNull);
        expect(
          (await session.entry(ws, initial.id))!.kind,
          PostingKind.opening,
        );
      });
      await expectLater(
        closed.entry(ws, posted.id),
        throwsA(isA<SessionClosed>()),
      );
    },
  );
  test(
    'empty initialization is replayable but cannot reset existing entries',
    () async {
      final operation = op();
      final receipt = await store.initialize(operation);
      expect(
        (await store.initialize(operation)).generation,
        receipt.generation,
      );
      final a = account();
      await store.withSession(
        (session) => session.createAccount(a, opening(a)),
      );
      final before = await store.snapshot();
      await expectLater(
        store.initialize(op()),
        throwsA(
          isA<GenerationUnavailable>().having(
            (e) => e.problem,
            'problem',
            GenerationProblem.alreadyInitialized,
          ),
        ),
      );
      expect(await store.snapshot(), before);
      await store.initialize(operation);
      expect(await store.snapshot(), before);
    },
  );
  test(
    'scoped facade is revoked; queued writes drain even on callback failure',
    () async {
      await store.initialize(op());
      final a = account();
      late LedgerSession escaped;
      late Future<Object> pending;
      await expectLater(
        store.withSession<void>((session) async {
          escaped = session;
          await session.createAccount(a, opening(a));
          pending = session.post(income(a));
          throw const FormatException('caller');
        }),
        throwsFormatException,
      );
      await pending;
      await expectLater(escaped.post(income(a)), throwsA(isA<SessionClosed>()));
      await store.withSession((s) async {
        expect(
          (await s.accounts(ws)).single.balance.minorUnits,
          BigInt.from(10100),
        );
      });
    },
  );
  test('concurrent duplicate submission applies once and failures do not poison queue', () async {
    await store.initialize(op());
    final a = account();
    await store.withSession((s) async {
      await s.createAccount(a, opening(a));
      final p = income(a);
      final results = await Future.wait(List.generate(20, (_) => s.post(p)));
      expect(results.where((r) => !r.replayed), hasLength(1));
      await expectLater(
        s.post(income(a, date: BusinessDate(2005, 12, 31))),
        throwsA(isA<AccountException>()),
      );
      await s.post(income(a, amount: '2'));
      expect(
        (await s.accounts(ws)).single.balance.minorUnits,
        BigInt.from(10300),
      );
      expect(await s.accounts(other), isEmpty);
      expect(await s.entries(other), isEmpty);
    });
  });
  test(
    'pagination orders dates and ties without skipping or repeating',
    () async {
      await store.initialize(op());
      final a = account();
      await store.withSession((s) async {
        await s.createAccount(a, opening(a));
        for (var i = 0; i < 61; i++) {
          await s.post(income(a, date: BusinessDate(2026, 9, 1 + i % 4)));
        }
        final all = await s.entries(ws, limit: 100);
        final seen = <LedgerEntry>[];
        while (true) {
          final page = await s.entries(
            ws,
            before: seen.isEmpty ? null : seen.last,
            limit: 7,
          );
          if (page.isEmpty) break;
          seen.addAll(page);
        }
        expect(seen.map((e) => e.id), all.map((e) => e.id));
        expect(seen.map((e) => e.id).toSet(), hasLength(62));
        await expectLater(s.entries(ws, limit: 0), throwsArgumentError);
        await expectLater(s.entries(ws, limit: 101), throwsArgumentError);
        final snapshot = jsonDecode(utf8.decode(await s.snapshot())) as Map;
        expect(
          (snapshot['tables']['events'] as List).every(
            (r) => r['source_context'] == 'preview-manual-v1',
          ),
          isTrue,
        );
      });
    },
  );
  test(
    'lifecycle lease prevents restore publication while session is open',
    () async {
      await store.initialize(op());
      final entered = Completer<void>();
      final release = Completer<void>();
      final active = store.withSession((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      await expectLater(
        store.snapshot(),
        throwsA(
          isA<GenerationUnavailable>().having(
            (e) => e.problem,
            'problem',
            GenerationProblem.busy,
          ),
        ),
      );
      release.complete();
      await active;
      expect(await store.snapshot(), isNotEmpty);
    },
  );
  test('overflow rolls back event receipt and audit together', () async {
    await store.initialize(op());
    final a = account();
    await store.withSession((s) async {
      await s.createAccount(a, opening(a));
      final before = await s.snapshot();
      await expectLater(
        s.post(income(a, amount: '92233720368547758.07')),
        throwsA(isA<MoneyException>()),
      );
      expect(await s.snapshot(), before);
      await s.post(income(a));
    });
  });
}
