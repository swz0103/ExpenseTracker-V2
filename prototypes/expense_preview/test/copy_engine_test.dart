import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:categories/categories.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/copy-tests')..createSync(recursive: true);
  late Directory work;
  late PreviewEngine engine;
  late PublicId category, tag, merchant, sourceId, openingId;
  OperationKey op() =>
      OperationKey(engine.workspace, OperationId(PublicId.generate()));
  Future<List<int>> snapshot() async =>
      EnvelopeCodec().openWithPassword(await engine.exportBackup(), password);
  setUp(() async {
    work = root.createTempSync('case-');
    engine = engineAt(work, MemoryVault(), schemaVersion: 7);
    await setup(engine);
    final a = account(engine);
    // The stored opening and source must use the same actual account identity.
    final initial = opening(a);
    openingId = initial.id;
    await engine.createAccount(a, initial);
    category = PublicId.generate();
    tag = PublicId.generate();
    merchant = PublicId.generate();
    await engine.createCategory(op(), category, '薪資', CategoryKind.income);
    await engine.createTag(op(), tag, '固定');
    await engine.createMerchant(op(), merchant, '公司');
    final source = Posting.income(
      id: PublicId.generate(),
      operation: op(),
      date: BusinessDate(2026, 1, 2),
      account: ref(a),
      amount: Money.parse(a.currency, '123.45'),
      allocations: [
        Allocation(
          category,
          Money.parse(a.currency, '123.45'),
          expectedCategoryVersion: 1,
        ),
      ],
    );
    sourceId = source.id;
    await engine.post(
      source,
      tags: [TagSelection(tag, 1)],
      merchant: MerchantSelection(merchant, 1),
    );
  });
  tearDown(() async {
    await engine.lock();
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    )) {
      throw StateError('Unsafe cleanup');
    }
    work.deleteSync(recursive: true);
  });
  test('copy reads persisted identities at current versions without any ledger mutation', () async {
    await engine.renameCategory(
      op(),
      (await engine.categories()).get(category),
      '薪水',
    );
    await engine.renameTag(op(), (await engine.tags()).get(tag), '定期');
    await engine.renameMerchant(
      op(),
      (await engine.merchants()).get(merchant),
      '新公司名',
    );
    final before = await snapshot();
    final copy = await engine.preparePostingCopy(sourceId);
    expect(copy.income, isTrue);
    expect(copy.account.id, (await engine.accounts()).single.account.id);
    expect(copy.account.currency.code, 'TWD');
    expect(copy.categoryId, category);
    expect(copy.tags.single.id, tag);
    expect(copy.tags.single.expectedVersion, 2);
    expect(copy.merchant!.id, merchant);
    expect(copy.merchant!.expectedVersion, 2);
    expect(copy.omittedMetadata, isFalse);
    expect(() => copy.tags.clear(), throwsUnsupportedError);
    expect(await snapshot(), before);
    expect((await engine.allocations(sourceId)).single.categoryVersion, 1);
    expect((await engine.merchantFor(sourceId))!.version, 1);
  });
  test(
    'archived and merged metadata is omitted instead of following redirects',
    () async {
      await engine.archiveCategory(
        op(),
        (await engine.categories()).get(category),
        archived: true,
      );
      final targetTag = PublicId.generate(),
          targetMerchant = PublicId.generate();
      await engine.createTag(op(), targetTag, '新標籤');
      await engine.createMerchant(op(), targetMerchant, '新商家');
      final tags = await engine.tags(), merchants = await engine.merchants();
      await engine.mergeTag(op(), tags.get(tag), tags.get(targetTag));
      await engine.mergeMerchant(
        op(),
        merchants.get(merchant),
        merchants.get(targetMerchant),
      );
      final before = await snapshot(),
          copy = await engine.preparePostingCopy(sourceId);
      expect(copy.categoryId, isNull);
      expect(copy.tags, isEmpty);
      expect(copy.merchant, isNull);
      expect(copy.omittedMetadata, isTrue);
      expect(await snapshot(), before);
    },
  );
  test(
    'missing and opening identities cannot be reused as daily postings',
    () async {
      final before = await snapshot();
      await expectLater(
        engine.preparePostingCopy(PublicId.generate()),
        throwsA(isA<PreviewInvalid>()),
      );
      await expectLater(
        engine.preparePostingCopy(openingId),
        throwsA(isA<PreviewInvalid>()),
      );
      expect(await snapshot(), before);
    },
  );
  test(
    'locked copy is rejected and repeated preparation does not create an event',
    () async {
      await engine.preparePostingCopy(sourceId);
      await engine.preparePostingCopy(sourceId);
      expect(await engine.entries(), hasLength(2));
      await engine.lock();
      await expectLater(
        engine.preparePostingCopy(sourceId),
        throwsA(isA<PreviewLocked>()),
      );
    },
  );
}
