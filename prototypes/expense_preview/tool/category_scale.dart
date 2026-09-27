import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:categories/categories.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';

import '../test/support.dart';

void check(bool condition, String detail) {
  if (!condition) throw StateError(detail);
}

bool sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Synthetic App flow: original schema 3 -> 5, 5,000 events, categories,
/// archived attribution, independent balance oracle and two clean restores.
Future<void> main() async {
  final root = Directory('.dart_tool/app-category-scale')
    ..createSync(recursive: true);
  final work = root.createTempSync('case-');
  final source = Directory('${work.path}/source');
  final vault = MemoryVault();
  var engine = engineAt(source, vault, schemaVersion: 3);
  final watch = Stopwatch()..start();
  var succeeded = false;
  final report = <String, Object>{
    'startedUtc': DateTime.now().toUtc().toIso8601String(),
    'platform': Platform.operatingSystemVersion,
    'dart': Platform.version,
  };
  OperationKey operation() =>
      OperationKey(engine.workspace, OperationId(PublicId.generate()));
  try {
    final key = await setup(engine);
    final a = account(engine);
    await engine.createAccount(a, opening(a));
    var expected = BigInt.from(10000);
    final before = await EnvelopeCodec().openWithPassword(
      await engine.exportBackup(),
      password,
    );
    await engine.lock();
    engine = engineAt(source, vault);
    final upgradeStart = watch.elapsedMilliseconds;
    await engine.upgrade(password);
    report['upgradeMs'] = watch.elapsedMilliseconds - upgradeStart;
    final upgradeCopies =
        Directory('${source.path}/upgrade-backups')
            .listSync()
            .whereType<File>()
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    check(upgradeCopies.length == 2, 'Two known upgrade steps');
    check(
      sameBytes(
        await EnvelopeCodec().openWithRecovery(
          upgradeCopies.first.readAsStringSync(),
          key,
        ),
        before,
      ),
      'Original safety backup',
    );
    final ids = List.generate(256, (_) => PublicId.generate());
    for (var i = 0; i < ids.length; i++) {
      await engine.createCategory(
        operation(),
        ids[i],
        '分類 $i',
        i.isEven ? CategoryKind.income : CategoryKind.expense,
      );
    }
    var allocations = 0, retries = 0;
    Posting? last;
    final writesStart = watch.elapsedMilliseconds;
    for (var i = 1; i < 5000; i++) {
      final incoming = i.isEven;
      final amount = Money(a.currency, BigInt.from(incoming ? 400 : 200));
      final category = ids[i % ids.length];
      final create = incoming ? Posting.income : Posting.expense;
      final posting = create(
        id: PublicId.generate(),
        operation: operation(),
        date: BusinessDate(2026, 9, 27),
        account: ref(a),
        amount: amount,
        allocations: [Allocation(category, amount, expectedCategoryVersion: 1)],
      );
      await engine.post(posting);
      await engine.post(posting);
      allocations++;
      retries++;
      expected += incoming ? amount.minorUnits : -amount.minorUnits;
      last = posting;
      if (i % 1000 == 0) {
        stdout.writeln('Verified $i classified writes and replays.');
      }
    }
    report['writesMs'] = watch.elapsedMilliseconds - writesStart;
    var catalog = await engine.categories();
    for (final c in catalog.categories) {
      await engine.renameCategory(operation(), c, '${c.name} 更新');
    }
    catalog = await engine.categories();
    for (final c in catalog.categories) {
      await engine.archiveCategory(operation(), c, archived: true);
    }
    await engine.post(last!);
    retries++;
    check(
      (await engine.accounts()).single.balance.minorUnits == expected,
      'Independent balance oracle',
    );
    var count = 0;
    LedgerEntry? cursor;
    while (true) {
      final page = await engine.entries(before: cursor);
      if (page.isEmpty) break;
      count += page.length;
      cursor = page.last;
    }
    check(count == 5000, 'Full App paging');
    try {
      await engine.post(income(a));
      throw StateError('Event capacity not enforced');
    } on PreviewCapacity {
      /* expected */
    }
    try {
      await engine.createCategory(
        operation(),
        PublicId.generate(),
        'Too many',
        CategoryKind.income,
      );
      throw StateError('Category capacity not enforced');
    } on PreviewCapacity {
      /* expected */
    }
    final backup = await engine.exportBackup();
    final bytes = await EnvelopeCodec().openWithPassword(backup, password);
    check(
      sameBytes(bytes, await EnvelopeCodec().openWithRecovery(backup, key)),
      'Both export credentials',
    );
    await engine.lock();
    if (!source.resolveSymbolicLinksSync().startsWith(
      '${work.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    )) {
      throw StateError('unsafe cleanup');
    }
    source.deleteSync(recursive: true);
    vault.values.clear();
    final restores = <Object>[];
    for (final recovery in [false, true]) {
      engine = engineAt(
        Directory('${work.path}/${recovery ? 'recovery' : 'password'}'),
        MemoryVault(),
      );
      final localKey = await setup(engine);
      final restoreStart = watch.elapsedMilliseconds;
      await engine.importBackup(
        backup,
        recovery ? key : password,
        recovery: recovery,
      );
      await engine.post(last);
      retries++;
      check(
        (await engine.accounts()).single.balance.minorUnits == expected,
        'Restored balance',
      );
      check(
        (await engine.categories()).categories.every((c) => c.archived),
        'Archived catalog retained',
      );
      check(
        (await engine.allocations(last.id)).single.categoryVersion == 1,
        'Historical category version',
      );
      final restored = await EnvelopeCodec().openWithRecovery(
        await engine.exportBackup(),
        localKey,
      );
      check(sameBytes(restored, bytes), 'Full restored bytes and replay');
      await engine.lock();
      await engine.unlock(password);
      check(
        (await engine.accounts()).single.balance.minorUnits == expected,
        'Reopen balance',
      );
      restores.add({
        'credential': recovery ? 'recovery' : 'password',
        'elapsedMs': watch.elapsedMilliseconds - restoreStart,
        'passed': true,
      });
      await engine.lock();
    }
    report.addAll({
      'events': count,
      'allocations': allocations,
      'categories': 256,
      'categoryChanges': 768,
      'replays': retries,
      'snapshotBytes': bytes.length,
      'expectedMinorUnits': expected.toString(),
      'restores': restores,
      'totalMs': watch.elapsedMilliseconds,
      'passed': true,
    });
    File('.dart_tool/app-category-scale-report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    stdout.writeln(jsonEncode(report));
    succeeded = true;
  } finally {
    await engine.lock();
    if (succeeded) {
      if (!work.resolveSymbolicLinksSync().startsWith(
        '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
      )) {
        throw StateError('unsafe cleanup');
      }
      work.deleteSync(recursive: true);
    }
  }
}
