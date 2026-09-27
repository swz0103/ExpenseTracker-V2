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

/// Synthetic mixed metadata or already-populated schema-5 upgrade validation.
Future<void> main(List<String> args) async {
  final legacy = args.contains('legacy');
  final root = Directory('.dart_tool/app-tag-scale')
    ..createSync(recursive: true);
  final work = root.createTempSync('case-');
  final source = Directory('${work.path}/source');
  final vault = MemoryVault();
  var engine = engineAt(source, vault, schemaVersion: legacy ? 5 : 6);
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
    final ids = List.generate(256, (_) => PublicId.generate());
    for (var i = 0; i < ids.length; i++) {
      await engine.createCategory(
        operation(),
        ids[i],
        '分類 $i',
        i.isEven ? CategoryKind.income : CategoryKind.expense,
      );
    }
    final tagIds = List.generate(256, (_) => PublicId.generate());
    OperationKey? firstTagOperation;
    Future<void> createTags() async {
      for (var i = 0; i < tagIds.length; i++) {
        final op = operation();
        if (i == 0) firstTagOperation = op;
        await engine.createTag(op, tagIds[i], '情境 $i');
      }
    }

    if (!legacy) await createTags();
    var allocations = 0, retries = 0;
    var lastTags = <TagSelection>[];
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
      lastTags = legacy
          ? []
          : [
              TagSelection(tagIds[i % 256], 1),
              TagSelection(tagIds[(i + 1) % 256], 1),
            ];
      await engine.post(posting, tags: lastTags);
      await engine.post(posting, tags: lastTags.reversed);
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
    if (legacy) {
      final before = await EnvelopeCodec().openWithPassword(
        await engine.exportBackup(),
        password,
      );
      await engine.lock();
      engine = engineAt(source, vault, schemaVersion: 6);
      final start = watch.elapsedMilliseconds;
      await engine.upgrade(password);
      report['upgradeMs'] = watch.elapsedMilliseconds - start;
      final copies = Directory('${source.path}/upgrade-backups')
          .listSync()
          .whereType<File>()
          .toList();
      check(copies.length == 1, 'One 5-to-6 upgrade');
      check(
        sameBytes(
          await EnvelopeCodec().openWithRecovery(
            copies.single.readAsStringSync(),
            key,
          ),
          before,
        ),
        'Original populated source backup',
      );
      final after = jsonDecode(
        utf8.decode(
          await EnvelopeCodec().openWithPassword(
            await engine.exportBackup(),
            password,
          ),
        ),
      ) as Map;
      final prior = jsonDecode(utf8.decode(before)) as Map;
      for (final entry in (prior['tables'] as Map).entries) {
        check(
          jsonEncode(after['tables'][entry.key]) == jsonEncode(entry.value),
          'Upgrade retains ${entry.key}',
        );
      }
      await createTags();
    }
    for (var round = 0; round < 2; round++) {
      final tags = await engine.tags();
      for (final tag in tags.tags) {
        await engine.renameTag(operation(), tag, '${tag.name} 更新');
      }
    }
    final tags = await engine.tags();
    for (final tag in tags.tags) {
      await engine.archiveTag(operation(), tag, archived: true);
    }
    await engine.createTag(firstTagOperation!, tagIds.first, '情境 0');
    retries++;
    try {
      await engine.renameTag(
        operation(),
        (await engine.tags()).get(tagIds.first),
        'exceeds history',
      );
      throw StateError('Tag history cap not enforced');
    } on PreviewCapacity {
      /* expected */
    }
    await engine.post(last!, tags: lastTags);
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
    try {
      await engine.createTag(
        operation(),
        PublicId.generate(),
        'exceeds capacity',
      );
      throw StateError('Tag capacity not enforced');
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
        schemaVersion: 6,
      );
      final localKey = await setup(engine);
      final restoreStart = watch.elapsedMilliseconds;
      await engine.importBackup(
        backup,
        recovery ? key : password,
        recovery: recovery,
      );
      await engine.post(last, tags: lastTags);
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
      check(
        (await engine.tagsFor(last.id)).length == (legacy ? 0 : 2),
        'Tag references restored',
      );
      check(
        (await engine.tags()).tags.every((t) => t.archived),
        'Tag archive retained',
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
      'scenario': legacy ? 'populated-schema-5-to-6' : 'mixed-schema-6',
      'events': count,
      'tagReferences': legacy ? 0 : 9998,
      'tags': 256,
      'tagChanges': 1024,
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
    File('.dart_tool/app-tag-${legacy ? 'upgrade-' : ''}scale-report.json')
        .writeAsStringSync(
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
