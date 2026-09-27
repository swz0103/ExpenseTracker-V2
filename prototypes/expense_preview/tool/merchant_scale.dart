import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:amount_input/amount_input.dart';
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

/// Synthetic mixed metadata or already-populated schema-6 upgrade validation.
Future<void> main(List<String> args) async {
  final legacy = args.contains('legacy');
  final calculator = args.contains('calculator');
  var calculations = 0, roundedCalculations = 0;
  final root = Directory('.dart_tool/app-merchant-scale')
    ..createSync(recursive: true);
  final work = root.createTempSync('case-');
  final source = Directory('${work.path}/source');
  final vault = MemoryVault();
  var engine = engineAt(source, vault, schemaVersion: legacy ? 6 : 7);
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

    await createTags();
    final merchantIds = List.generate(256, (_) => PublicId.generate());
    OperationKey? firstMerchantOperation;
    Future<void> createMerchants() async {
      for (var i = 0; i < merchantIds.length; i++) {
        final op = operation();
        if (i == 0) firstMerchantOperation = op;
        await engine.createMerchant(op, merchantIds[i], '商家 $i');
      }
      final catalog = await engine.merchants();
      for (var i = 0; i < merchantIds.length; i++) {
        await engine.changeMerchantAlias(
          operation(),
          catalog.get(merchantIds[i]),
          'SHOP $i',
          remove: false,
        );
      }
    }

    if (!legacy) await createMerchants();
    MerchantSelection? lastMerchant;
    var allocations = 0, retries = 0;
    var lastTags = <TagSelection>[];
    Posting? last;
    final writesStart = watch.elapsedMilliseconds;
    for (var i = 1; i < 5000; i++) {
      final incoming = i.isEven;
      final major = incoming ? 4 : 2;
      final expression = switch (i % 3) {
        0 => '$i/3*3-$i+$major',
        1 => '$major-0.005',
        _ => '$major*(1-10%)+$major*10%',
      };
      final calculation = calculator
          ? calculateAmount(a.currency, expression)
          : null;
      final amount =
          calculation?.money ??
          Money(a.currency, BigInt.from(incoming ? 400 : 200));
      check(
        amount.minorUnits == BigInt.from(incoming ? 400 : 200),
        'Independent computed amount',
      );
      if (calculation != null) {
        calculations++;
        if (calculation.rounded) roundedCalculations++;
        check(calculation.rounded == (i % 3 == 1), 'Rounding disclosure');
      }
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
      lastTags = [TagSelection(tagIds[i % 256], 1)];
      lastMerchant = legacy ? null : MerchantSelection(merchantIds[i % 256], 2);
      await engine.post(posting, tags: lastTags, merchant: lastMerchant);
      await engine.post(
        posting,
        tags: lastTags.reversed,
        merchant: lastMerchant,
      );
      allocations++;
      retries++;
      expected += BigInt.from(incoming ? 400 : -200);
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
      engine = engineAt(source, vault, schemaVersion: 7);
      final start = watch.elapsedMilliseconds;
      await engine.upgrade(password);
      report['upgradeMs'] = watch.elapsedMilliseconds - start;
      final copies = Directory('${source.path}/upgrade-backups')
          .listSync()
          .whereType<File>()
          .toList();
      check(copies.length == 1, 'One 6-to-7 upgrade');
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
      await createMerchants();
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
    var merchantCatalog = await engine.merchants();
    for (final merchant in merchantCatalog.merchants) {
      await engine.renameMerchant(operation(), merchant, '${merchant.name} 更新');
    }
    merchantCatalog = await engine.merchants();
    for (final merchant in merchantCatalog.merchants) {
      await engine.archiveMerchant(operation(), merchant, archived: true);
    }
    await engine.createMerchant(
      firstMerchantOperation!,
      merchantIds.first,
      '商家 0',
    );
    retries++;
    try {
      await engine.renameMerchant(
        operation(),
        (await engine.merchants()).get(merchantIds.first),
        'exceeds history',
      );
      throw StateError('Merchant history cap not enforced');
    } on PreviewCapacity {
      /* expected */
    }
    try {
      await engine.createMerchant(
        operation(),
        PublicId.generate(),
        'exceeds capacity',
      );
      throw StateError('Merchant capacity not enforced');
    } on PreviewCapacity {
      /* expected */
    }
    await engine.post(last!, tags: lastTags, merchant: lastMerchant);
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
        schemaVersion: 7,
      );
      final localKey = await setup(engine);
      final restoreStart = watch.elapsedMilliseconds;
      await engine.importBackup(
        backup,
        recovery ? key : password,
        recovery: recovery,
      );
      await engine.post(last, tags: lastTags, merchant: lastMerchant);
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
        (await engine.tagsFor(last.id)).length == 1,
        'Tag references restored',
      );
      check(
        (await engine.tags()).tags.every((t) => t.archived),
        'Tag archive retained',
      );
      final merchantRef = await engine.merchantFor(last.id);
      check(
        legacy ? merchantRef == null : merchantRef?.version == 2,
        'Merchant reference retains posting version',
      );
      final restoredMerchants = await engine.merchants();
      check(
        restoredMerchants.merchants.every(
          (m) => m.archived && m.aliases.length == 1,
        ),
        'Merchant archive and aliases retained',
      );
      check(
        restoredMerchants.candidates('SHOP 1').isEmpty,
        'Archived merchant suppressed',
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
      'scenario': legacy ? 'populated-schema-6-to-7' : 'mixed-schema-7',
      'calculatorEnabled': calculator,
      'calculations': calculations,
      'roundedCalculations': roundedCalculations,
      'events': count,
      'tagReferences': 4999,
      'merchantReferences': legacy ? 0 : 4999,
      'merchants': 256,
      'merchantChanges': 1024,
      'merchantAliases': 256,
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
    File(
      '.dart_tool/app-merchant-${calculator ? 'calculator-' : ''}${legacy ? 'upgrade-' : ''}scale-report.json',
    ).writeAsStringSync(
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
