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
  final root = Directory('.dart_tool/tombstone-scale')
    ..createSync(recursive: true);
  final work = root.createTempSync('case-');
  final started = DateTime.now().toUtc().toIso8601String();
  final watch = Stopwatch()..start();
  const password = 'synthetic-tombstone-scale-password';
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
      tombstonesAware: true,
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
  PostingAccount ref(Account value) => PostingAccount(
    id: value.id,
    workspace: ws,
    currency: value.currency,
    expectedVersion: value.version,
  );
  var expectedUsd = BigInt.from(1000000);
  var expectedJpy = BigInt.from(100);
  var deletedCount = 0;
  PostingTombstone? firstDeleted;
  try {
    final source = store('source');
    await source.initialize(operation());
    await source.withSession((session) async {
      for (final (value, amount) in [(a, '10000'), (b, '100')]) {
        await session.createAccount(
          value,
          Posting.opening(
            id: PublicId.generate(),
            operation: key(),
            date: date,
            account: ref(value),
            amount: Money.parse(value.currency, amount),
          ),
        );
      }
      for (var i = 0; i < 4998; i++) {
        final transfer = i.isOdd;
        final p = transfer
            ? Posting.transfer(
                id: PublicId.generate(),
                operation: key(),
                date: date,
                source: ref(a),
                destination: ref(b),
                principal: Money.parse(usd, '1.23'),
                received: Money.parse(jpy, '7'),
                fee: Money.parse(usd, '0.01'),
              )
            : Posting.expense(
                id: PublicId.generate(),
                operation: key(),
                date: date,
                account: ref(a),
                amount: Money.parse(usd, '1.23'),
              );
        await session.post(p);
        final deleted = i % 4 == 1 || i % 4 == 2;
        if (deleted) {
          final command = PostingTombstone(
            original: p,
            operation: key(),
            reason: 'synthetic duplicate',
          );
          await session.tombstone(command);
          firstDeleted ??= command;
          deletedCount++;
        } else if (transfer) {
          expectedUsd -= BigInt.from(124);
          expectedJpy += BigInt.from(7);
        } else {
          expectedUsd -= BigInt.from(123);
        }
        if ((i + 1) % 500 == 0) {
          stdout.writeln('Events ${i + 1}; ${watch.elapsedMilliseconds} ms');
        }
      }
      // Two opening events plus 4,998 ordinary events meet the event cap.
      final balances = {
        for (final row in await session.accounts(ws))
          row.account.id: row.balance.minorUnits,
      };
      check(balances[a.id] == expectedUsd, 'source effective cash');
      check(balances[b.id] == expectedJpy, 'destination effective cash');
      var active = 0, deleted = 0;
      LedgerEntry? before;
      for (;;) {
        final page = await session.entries(ws, before: before);
        if (page.isEmpty) break;
        active += page.length;
        before = page.last;
      }
      before = null;
      for (;;) {
        final page = await session.deletedEntries(ws, before: before);
        if (page.isEmpty) break;
        deleted += page.length;
        before = page.last;
      }
      check(active + deleted == 5000, 'independent pagination total');
      check(deleted == deletedCount, 'deleted pagination count');
      final beforeCapacity = await session.snapshot();
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
      check(rejected, 'event cap still includes deleted history');
      check(
        await session.snapshot().then((v) => utf8.decode(v)) ==
            utf8.decode(beforeCapacity),
        'capacity rollback',
      );
      check((await session.tombstone(firstDeleted!)).replayed, 'replay');
    });
    final writtenMs = watch.elapsedMilliseconds;
    final bytes = await source.snapshot();
    final tables = (jsonDecode(utf8.decode(bytes)) as Map)['tables'] as Map;
    check((tables['events'] as List).length == 5000, 'event count');
    check(
      (tables['event_tombstones'] as List).length == deletedCount,
      'marker count',
    );
    final backup = await source.backup(password);
    removeSynthetic(Directory('${work.path}/source'), work);
    removeSynthetic(Directory('${work.path}/source-keys'), work);
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
            row.account.id: row.balance.minorUnits,
        };
        check(balances[a.id] == expectedUsd, '$method source cash');
        check(balances[b.id] == expectedJpy, '$method destination cash');
        check(
          (await session.tombstone(firstDeleted!)).replayed,
          '$method exact replay',
        );
      });
    }
    stdout.writeln(
      jsonEncode({
        'status': 'passed',
        'startedUtc': started,
        'events': 5000,
        'tombstones': deletedCount,
        'sourceCashMinor': expectedUsd.toString(),
        'destinationCashMinor': expectedJpy.toString(),
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
