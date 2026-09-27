import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';

void check(bool ok, String what) {
  if (!ok) throw StateError(what);
}

void remove(Directory dir, Directory root) {
  if (!dir.resolveSymbolicLinksSync().startsWith(
    '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
  )) {
    throw StateError('Unsafe synthetic cleanup');
  }
  dir.deleteSync(recursive: true);
}

Future<void> main() async {
  final root = Directory('.dart_tool/note-scale')..createSync(recursive: true);
  var work = root.createTempSync('source-');
  final started = DateTime.now().toUtc().toIso8601String(),
      watch = Stopwatch()..start();
  LedgerStore store(String name) {
    final keys = FixtureKeySlots(Directory('${work.path}/$name-keys'));
    return LedgerStore(
      Directory('${work.path}/$name'),
      keys,
      catalogProtection: fixtureCatalogProtection(keys),
      notesAware: true,
    );
  }

  final ws = WorkspaceId(PublicId.generate()), cur = Currency('TWD', 2);
  OperationId operation() => OperationId(PublicId.generate());
  OperationKey key() => OperationKey(ws, operation());
  final a = Account.open(
    id: PublicId.generate(),
    workspace: ws,
    name: 'synthetic',
    kind: AccountKind.cash,
    currency: cur,
    openedOn: BusinessDate(2026, 1, 1),
  );
  final ref = PostingAccount(
    id: a.id,
    workspace: ws,
    currency: cur,
    expectedVersion: 1,
  );
  final events = <Posting>[], commands = <(OperationKey, NoteChange)>[];
  const password = 'synthetic-note-scale-password';
  try {
    final source = store('source');
    await source.initialize(operation());
    await source.withSession((s) async {
      await s.createAccount(
        a,
        Posting.opening(
          id: PublicId.generate(),
          operation: key(),
          date: a.openedOn,
          account: ref,
          amount: Money.parse(cur, '100'),
        ),
      );
      for (var i = 0; i < 4999; i++) {
        final p = Posting.income(
          id: PublicId.generate(),
          operation: key(),
          date: a.openedOn,
          account: ref,
          amount: Money.parse(cur, '1'),
        );
        await s.post(p);
        events.add(p);
      }
      for (var i = 0; i < 5000; i++) {
        final change = NoteChange(
          events[i % 100].id,
          i ~/ 100,
          '備註 $i 🙂\n${i == 0 ? '🙂' * 1000 : 'retained'}',
        );
        final op = key();
        await s.reviseNote(op, change);
        commands.add((op, change));
        if ((i + 1) % 1000 == 0) {
          stdout.writeln('Notes ${i + 1}; ${watch.elapsedMilliseconds} ms');
        }
      }
    });
    final writtenMs = watch.elapsedMilliseconds;
    final bytes = await source.snapshot();
    check(
      validateSessionCapacity(bytes, notesAware: true).length == bytes.length,
      'capacity admits exact bounded data',
    );
    await source.withSession((s) async {
      for (final p in events) {
        check((await s.post(p)).replayed, 'financial replay');
      }
      for (final c in commands) {
        check((await s.reviseNote(c.$1, c.$2)).replayed, 'note replay');
      }
      var blocked = false;
      try {
        await s.reviseNote(key(), NoteChange(events.first.id, 50, 'over cap'));
      } on PreviewCapacity {
        blocked = true;
      }
      check(blocked, 'note cap');
      check(
        utf8.decode(await s.snapshot()) == utf8.decode(bytes),
        'failed cap leaves exact bytes',
      );
    });
    final backup = await source.backup(password);
    remove(work, root);
    work = root.createTempSync('restored-');
    for (final recovery in [false, true]) {
      final target = store('$recovery');
      await target.restore(
        backup.envelope,
        operation(),
        password: recovery ? null : password,
        recoveryKey: recovery ? backup.recoveryKey : null,
      );
      check(
        utf8.decode(await target.snapshot()) == utf8.decode(bytes),
        'canonical clean restore',
      );
      await target.withSession((s) async {
        check(
          (await s.accounts(ws)).single.balance == Money.parse(cur, '5099'),
          'independent balance',
        );
        final ids = <PublicId>{};
        LedgerEntry? entry;
        while (true) {
          final page = await s.entries(ws, before: entry);
          if (page.isEmpty) break;
          for (final e in page) {
            check(ids.add(e.id), 'unique entry');
          }
          entry = page.last;
        }
        check(ids.length == 5000, 'complete entry pagination');
        final activity = <String>{};
        LedgerActivityCursor? cursor;
        var revisions = 0;
        while (true) {
          final page = await s.activity(
            ws,
            events.first.id,
            before: cursor,
            limit: 7,
          );
          if (page.isEmpty) break;
          for (final row in page) {
            check(activity.add(row.key), 'unique activity');
            if (row.noteRevision != null) revisions++;
          }
          cursor = page.last.cursor;
        }
        check(
          activity.length == 51 && revisions == 50,
          'complete note history',
        );
        check(
          (await s.entryNote(ws, events.first.id)).text ==
              '備註 4900 🙂\nretained',
          'latest text',
        );
      });
    }
    final tables = (jsonDecode(utf8.decode(bytes)) as Map)['tables'] as Map;
    final report = {
      'status': 'passed',
      'startedUtc': started,
      'events': 5000,
      'noteRevisions': 5000,
      'replayed': 9999,
      'snapshotBytes': bytes.length,
      'rows': tables.values.fold<int>(0, (n, r) => n + (r as List).length),
      'balanceMinor': '509900',
      'originalKeysDeleted': true,
      'passwordCleanRestore': true,
      'recoveryCleanRestore': true,
      'writesMs': writtenMs,
      'elapsedMs': watch.elapsedMilliseconds,
    };
    await File(
      '.dart_tool/note-scale-report.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    stdout.writeln(jsonEncode(report));
  } finally {
    remove(work, root);
  }
}
