import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';

void check(bool ok, String label) {
  if (!ok) throw StateError(label);
}

void removeSynthetic(Directory directory, Directory root) {
  if (!directory.resolveSymbolicLinksSync().startsWith(
    '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
  )) {
    throw StateError('Unsafe synthetic cleanup');
  }
  directory.deleteSync(recursive: true);
}

Future<void> main() async {
  final root = Directory('.dart_tool/correction-scale')
    ..createSync(recursive: true);
  final work = root.createTempSync('case-');
  final started = DateTime.now().toUtc().toIso8601String();
  final watch = Stopwatch()..start();
  const password = 'synthetic-correction-scale-password';
  final ws = WorkspaceId(PublicId.generate());
  final usd = Currency('USD', 2), jpy = Currency('JPY', 0);
  final date = BusinessDate(2026, 9, 28);
  OperationId operation() => OperationId(PublicId.generate());
  OperationKey key() => OperationKey(ws, operation());
  LedgerStore store(String name) {
    final keys = FixtureKeySlots(Directory('${work.path}/$name-keys'));
    return LedgerStore(
      Directory('${work.path}/$name'),
      keys,
      catalogProtection: fixtureCatalogProtection(keys),
      correctionsAware: true,
    );
  }

  Account account(String name, Currency currency) => Account.open(
    id: PublicId.generate(),
    workspace: ws,
    name: name,
    kind: AccountKind.bank,
    currency: currency,
    openedOn: date,
  );
  final a = account('synthetic USD', usd), b = account('synthetic JPY', jpy);
  PostingAccount ref(Account account) => PostingAccount(
    id: account.id,
    workspace: ws,
    currency: account.currency,
    expectedVersion: account.version,
  );
  final pairs = <PostingCorrection>[];
  try {
    final source = store('source');
    await source.initialize(operation());
    await source.withSession((session) async {
      for (final (account, amount) in [(a, '10000'), (b, '100')]) {
        await session.createAccount(
          account,
          Posting.opening(
            id: PublicId.generate(),
            operation: key(),
            date: date,
            account: ref(account),
            amount: Money.parse(account.currency, amount),
          ),
        );
      }
      for (var i = 0; i < 1666; i++) {
        final foreign = i.isOdd;
        Posting make(String principal, String fee, String received) => foreign
            ? Posting.transfer(
                id: PublicId.generate(),
                operation: key(),
                date: date,
                source: ref(a),
                destination: ref(b),
                principal: Money.parse(usd, principal),
                received: Money.parse(jpy, received),
                fee: Money.parse(usd, fee),
              )
            : Posting.expense(
                id: PublicId.generate(),
                operation: key(),
                date: date,
                account: ref(a),
                amount: Money.parse(usd, principal),
              );
        final original = make('1.23', '0.01', '7');
        final replacement = make('1.11', '0.02', '6');
        final pair = PostingCorrection(
          original: original,
          replacement: replacement,
          reversalId: PublicId.generate(),
          reversalOperation: key(),
          reason: 'synthetic correction',
        );
        await session.post(original);
        await session.correct(pair);
        pairs.add(pair);
        if ((i + 1) % 250 == 0) {
          stdout.writeln(
            'Correction pairs ${i + 1}; ${watch.elapsedMilliseconds} ms',
          );
        }
      }
      final balances = {
        for (final row in await session.accounts(ws))
          row.account.id: row.balance,
      };
      check(balances[a.id] == Money.parse(usd, '8134.08'), 'source cash');
      check(balances[b.id] == Money.parse(jpy, '5098'), 'destination cash');
      final before = await session.snapshot();
      var rejected = false;
      try {
        await session.post(
          Posting.income(
            id: PublicId.generate(),
            operation: key(),
            date: date,
            account: ref(a),
            amount: Money.parse(usd, '1'),
          ),
        );
      } on PreviewCapacity {
        rejected = true;
      }
      check(rejected, 'full event capacity rejection');
      check(
        utf8.decode(await session.snapshot()) == utf8.decode(before),
        'capacity rollback',
      );
    });
    final writtenMs = watch.elapsedMilliseconds;
    await source.withSession((session) async {
      for (final pair in pairs) {
        check((await session.correct(pair)).replayed, 'pair replay');
      }
    });
    final bytes = await source.snapshot();
    final tables = (jsonDecode(utf8.decode(bytes)) as Map)['tables'] as Map;
    check((tables['events'] as List).length == 5000, 'event count');
    check((tables['event_corrections'] as List).length == 1666, 'pair count');
    check((tables['event_fx'] as List).length == 2499, 'FX event count');
    final backup = await source.backup(password);
    final sourceKeys = Directory('${work.path}/source-keys');
    final sourceData = Directory('${work.path}/source');
    removeSynthetic(sourceData, work);
    removeSynthetic(sourceKeys, work);
    for (final method in ['password', 'recovery']) {
      final restored = store(method);
      await restored.restore(
        backup.envelope,
        operation(),
        password: method == 'password' ? password : null,
        recoveryKey: method == 'recovery' ? backup.recoveryKey : null,
      );
      check(
        utf8.decode(await restored.snapshot()) == utf8.decode(bytes),
        '$method exact restore',
      );
      await restored.withSession((session) async {
        final balances = {
          for (final row in await session.accounts(ws))
            row.account.id: row.balance,
        };
        check(
          balances[a.id] == Money.parse(usd, '8134.08'),
          '$method source cash',
        );
        check(
          balances[b.id] == Money.parse(jpy, '5098'),
          '$method destination cash',
        );
        check((await session.correct(pairs.first)).replayed, '$method replay');
        check(
          (await session.activity(ws, pairs.first.original.id)).length == 3,
          '$method activity',
        );
      });
    }
    stdout.writeln(
      jsonEncode({
        'status': 'passed',
        'startedUtc': started,
        'events': 5000,
        'corrections': 1666,
        'crossCurrencyCorrections': 833,
        'replayed': 1668,
        'sourceCashMinor': '813408',
        'destinationCashMinor': '5098',
        'snapshotBytes': bytes.length,
        'rows': (tables.values.cast<List>()).fold<int>(
          0,
          (sum, rows) => sum + rows.length,
        ),
        'originalKeysDeleted': true,
        'passwordCleanRestore': true,
        'recoveryCleanRestore': true,
        'writesMs': writtenMs,
        'elapsedMs': watch.elapsedMilliseconds,
      }),
    );
  } finally {
    if (work.existsSync()) removeSynthetic(work, root);
  }
}
