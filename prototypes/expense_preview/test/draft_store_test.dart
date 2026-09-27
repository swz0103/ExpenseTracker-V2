import 'support.dart' show deleteSynthetic;

import 'dart:convert';
import 'dart:io';

import 'package:expense_preview/local_draft_store.dart';
import 'package:entry_drafts/entry_drafts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late Map<String, String> keys;
  late PublicId identity, generation;
  late WorkspaceId workspace;
  LocalDraftStore store({
    PublicId? id,
    PublicId? gen,
    WorkspaceId? ws,
    void Function(String)? checkpoint,
  }) => LocalDraftStore(
    dir,
    id ?? identity,
    gen ?? generation,
    ws ?? workspace,
    (s) async => keys[s],
    (s, v) async {
      keys[s] = v;
    },
    checkpoint: checkpoint,
  );
  EntryDraft draft(String text) => EntryDraft(
    id: PublicId.generate(),
    operation: OperationKey(workspace, OperationId(PublicId.generate())),
    fields: EntryFields(
      income: false,
      amount: text,
      date: '2026-',
      tags: [PublicId.generate()],
    ),
  );
  setUp(() {
    final root = Directory('.dart_tool/draft-store-tests')
      ..createSync(recursive: true);
    dir = root.createTempSync('slot-');
    keys = {};
    identity = PublicId.generate();
    generation = PublicId.generate();
    workspace = WorkspaceId(PublicId.generate());
  });
  tearDown(
    () => deleteSynthetic(dir, Directory('.dart_tool/draft-store-tests')),
  );
  test(
    'encrypted replacement keeps only current draft and returns exact text',
    () async {
      final s = store();
      final first = draft('private-input-123');
      await s.write(first);
      expect(await s.file.readAsString(), isNot(contains('private-input-123')));
      expect((await s.read())!.encode(), first.encode());
      final next = first.edit(
        EntryFields(income: true, amount: '12.', date: ''),
      );
      await s.write(next);
      expect((await s.read())!.encode(), next.encode());
      expect(await s.stage.exists(), false);
      await s.write(null);
      expect(await s.read(), null);
    },
  );
  test(
    'foreign profile generation workspace and ciphertext tampering fail closed',
    () async {
      final s = store();
      await s.write(draft('7'));
      for (final other in [
        store(id: PublicId.generate()),
        store(gen: PublicId.generate()),
        store(ws: WorkspaceId(PublicId.generate())),
      ]) {
        await expectLater(other.read(), throwsA(isA<DraftUnavailable>()));
      }
      final data = jsonDecode(await s.file.readAsString()) as List;
      final cipher = base64Decode(data[2] as String);
      cipher[0] ^= 1;
      data[2] = base64Encode(cipher);
      await s.file.writeAsString(jsonEncode(data));
      await expectLater(s.read(), throwsA(isA<DraftUnavailable>()));
    },
  );
  test(
    'lost or damaged key preserves file until explicit discard and regenerates',
    () async {
      final s = store();
      await s.write(draft('7'));
      final before = await s.file.readAsString();
      keys.clear();
      await expectLater(s.read(), throwsA(isA<DraftUnavailable>()));
      await expectLater(s.write(draft('8')), throwsA(isA<DraftUnavailable>()));
      expect(await s.file.readAsString(), before);
      keys[s.slot] = 'bad';
      await s.discard();
      await s.write(draft('9'));
      expect((await s.read())!.fields.amount, '9');
    },
  );
  test(
    'failed replacement before publication retains last acknowledged draft',
    () async {
      final s = store();
      await s.write(draft('old'));
      await expectLater(
        store(
          checkpoint: (point) {
            if (point == 'draft-staged') throw StateError('stop');
          },
        ).write(draft('new')),
        throwsStateError,
      );
      expect((await s.read())!.fields.amount, 'old');
      await s.write(draft('retry'));
      expect((await s.read())!.fields.amount, 'retry');
    },
  );
  test('interrupted first publication is retained and cannot be mistaken for empty', () async {
    final s = store(
      checkpoint: (point) {
        if (point == 'draft-staged') throw StateError('stop');
      },
    );
    await expectLater(s.write(draft('new')), throwsStateError);
    await expectLater(store().read(), throwsA(isA<DraftUnavailable>()));
    expect(await s.stage.exists(), true);
    await store().discard();
    expect(await store().read(), null);
  });
  test('completion without response survives reopening and queued writes stay ordered', () async {
    final s = store(
      checkpoint: (point) {
        if (point == 'draft-published') throw StateError('stop');
      },
    );
    await expectLater(s.write(draft('published')), throwsStateError);
    expect((await store().read())!.fields.amount, 'published');
    final stable = store();
    await Future.wait([
      for (var i = 0; i < 100; i++) stable.write(draft('$i')),
    ]);
    expect((await stable.read())!.fields.amount, '99');
  });
  test('oversized unknown and truncated storage fail closed', () async {
    final s = store();
    await s.file.writeAsString(' ' * 65537);
    await expectLater(s.read(), throwsA(isA<DraftUnavailable>()));
    await s.file.writeAsString('["new-version", "", "", ""]');
    await expectLater(s.read(), throwsA(isA<DraftUnavailable>()));
    await s.file.writeAsString('{"broken":');
    await expectLater(s.read(), throwsA(isA<DraftUnavailable>()));
  });
}
