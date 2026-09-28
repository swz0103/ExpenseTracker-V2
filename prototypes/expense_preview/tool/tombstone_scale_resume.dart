import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
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
  final root = Directory('.dart_tool/tombstone-scale');
  final work = root.listSync().whereType<Directory>().single;
  final watch = Stopwatch()..start();
  const password = 'synthetic-tombstone-scale-password';
  OperationId operation() => OperationId(PublicId.generate());
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

  const eventCount = 5000, ordinaryCount = 4998;
  var expectedUsd = BigInt.from(1000000), expectedJpy = BigInt.from(100);
  var deletedCount = 0;
  for (var i = 0; i < ordinaryCount; i++) {
    final deleted = i % 4 == 1 || i % 4 == 2;
    if (deleted) {
      deletedCount++;
    } else if (i.isOdd) {
      expectedUsd -= BigInt.from(124);
      expectedJpy += BigInt.from(7);
    } else {
      expectedUsd -= BigInt.from(123);
    }
  }

  final source = store('source');
  late WorkspaceId ws;
  late Account a, b;
  final bytes = await source.withSession((session) async {
    ws = (await session.workspaces()).single;
    final accounts = await session.accounts(ws);
    a = accounts.singleWhere((r) => r.account.currency.code == 'USD').account;
    b = accounts.singleWhere((r) => r.account.currency.code == 'JPY').account;
    final balances = {
      for (final row in accounts) row.account.id: row.balance.minorUnits,
    };
    check(balances[a.id] == expectedUsd, 'USD effective balance');
    check(balances[b.id] == expectedJpy, 'JPY effective balance');
    stdout.writeln('balances ${watch.elapsedMilliseconds}');
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
    check(active + deleted == eventCount, 'both paginated sets');
    check(deleted == deletedCount, 'deleted count');
    stdout.writeln('pages ${watch.elapsedMilliseconds}');
    final beforeCapacity = await session.snapshot();
    check(
      ((jsonDecode(utf8.decode(beforeCapacity)) as Map)['tables']
                  as Map)['events']
              .length ==
          eventCount,
      'snapshot event count',
    );
    stdout.writeln('snapshot ${watch.elapsedMilliseconds}');
    var rejected = false;
    try {
      await session.post(
        Posting.income(
          id: PublicId.generate(),
          operation: OperationKey(ws, operation()),
          date: BusinessDate(2026, 9, 28),
          account: PostingAccount(
            id: a.id,
            workspace: ws,
            currency: a.currency,
            expectedVersion: a.version,
          ),
          amount: Money.parse(a.currency, '1'),
        ),
      );
    } on PreviewCapacity {
      rejected = true;
    }
    check(rejected, 'cap includes deleted history');
    check(
      utf8.decode(await session.snapshot()) == utf8.decode(beforeCapacity),
      'capacity rejection preserves snapshot',
    );
    stdout.writeln('capacity ${watch.elapsedMilliseconds}');
    return beforeCapacity;
  });
  final backup = await source.backup(password);
  stdout.writeln('backup ${watch.elapsedMilliseconds}');
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
      '$method exact clean restore',
    );
    stdout.writeln('$method ${watch.elapsedMilliseconds}');
  }
  final tables = (jsonDecode(utf8.decode(bytes)) as Map)['tables'] as Map;
  check(
    (tables['event_tombstones'] as List).length == deletedCount,
    'tombstone markers',
  );
  stdout.writeln(
    jsonEncode({
      'status': 'passed',
      'mode': 'resumed-after-instrumented-interruption',
      'events': eventCount,
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
      'elapsedMs': watch.elapsedMilliseconds,
    }),
  );
  removeSynthetic(work, root);
}
