import 'package:tags/tags.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  final ws = WorkspaceId(PublicId.generate());
  final id = PublicId.generate(), target = PublicId.generate();
  TagCatalog initial() =>
      TagCatalog.empty(ws)
          .create(workspace: ws, id: id, name: '  旅行  ')
          .create(workspace: ws, id: target, name: '旅行');
  test(
    'flat identities are independent even with equal names and immutable views',
    () {
      final first = initial(),
          renamed = first.rename(
            workspace: ws,
            id: id,
            expectedVersion: 1,
            name: '差旅',
          );
      expect(first.get(id).name, '旅行');
      expect(renamed.get(id).version, 2);
      expect(first.tags.length, 2);
      expect(() => first.tags.clear(), throwsUnsupportedError);
    },
  );
  test('archive/reactivate preserves identity and version and rejects stale selection', () {
    final a = initial().setArchived(
      workspace: ws,
      id: id,
      expectedVersion: 1,
      archived: true,
    );
    expect(
      () => a.requireSelection(workspace: ws, id: id, expectedVersion: 2),
      throwsA(isA<TagException>()),
    );
    final b = a.setArchived(
      workspace: ws,
      id: id,
      expectedVersion: 2,
      archived: false,
    );
    expect(
      () => b.requireSelection(workspace: ws, id: id, expectedVersion: 1),
      throwsA(isA<TagException>()),
    );
    b.requireSelection(workspace: ws, id: id, expectedVersion: 3);
  });
  test('explicit merge retains original identity and prevents edits through redirects', () {
    final a = initial().merge(
      workspace: ws,
      sourceId: id,
      expectedSourceVersion: 1,
      targetId: target,
      expectedTargetVersion: 1,
    );
    expect(a.get(id).name, '旅行');
    expect(a.resolve(id).id, target);
    expect(
      () => a.rename(workspace: ws, id: id, expectedVersion: 2, name: '新'),
      throwsA(isA<TagException>()),
    );
    expect(
      () => initial().merge(
        workspace: ws,
        sourceId: id,
        expectedSourceVersion: 1,
        targetId: target,
        expectedTargetVersion: 2,
      ),
      throwsA(isA<TagException>()),
    );
  });
  test('workspace, missing target and cycles cannot be restored', () {
    final foreign = WorkspaceId(PublicId.generate());
    expect(
      () => initial().rename(
        workspace: foreign,
        id: id,
        expectedVersion: 1,
        name: 'X',
      ),
      throwsA(isA<TagException>()),
    );
    expect(
      () => TagCatalog.restore(ws, [
        Tag.restore(
          id: id,
          workspace: ws,
          name: 'a',
          version: 1,
          archived: true,
          replacementId: target,
        ),
      ]),
      throwsA(isA<TagException>()),
    );
    expect(
      () => TagCatalog.restore(ws, [
        Tag.restore(
          id: id,
          workspace: ws,
          name: 'a',
          version: 1,
          archived: true,
          replacementId: target,
        ),
        Tag.restore(
          id: target,
          workspace: ws,
          name: 'b',
          version: 1,
          archived: true,
          replacementId: id,
        ),
      ]),
      throwsA(isA<TagException>()),
    );
  });
  test('invalid names and exhausted revisions fail without changing state', () {
    for (final name in ['', ' ' * 5, 'x' * 101]) {
      expect(
        () => initial().rename(
          workspace: ws,
          id: id,
          expectedVersion: 1,
          name: name,
        ),
        throwsA(isA<TagException>()),
      );
    }
    expect(
      () => initial().rename(
        workspace: ws,
        id: id,
        expectedVersion: 1,
        name: 'a\nb',
      ),
      throwsA(isA<TagException>()),
    );
    final c = TagCatalog.restore(ws, [
      Tag.restore(
        id: id,
        workspace: ws,
        name: 'a',
        version: 9223372036854775807,
      ),
    ]);
    expect(
      () => c.rename(
        workspace: ws,
        id: id,
        expectedVersion: 9223372036854775807,
        name: 'b',
      ),
      throwsA(isA<TagException>()),
    );
  });
  test('long historical merge chains resolve iteratively without changing original IDs', () {
    final ids = List.generate(10000, (_) => PublicId.generate());
    final c = TagCatalog.restore(ws, [
      for (var i = 0; i < ids.length; i++)
        Tag.restore(
          id: ids[i],
          workspace: ws,
          name: 'tag-$i',
          version: 1,
          archived: i < ids.length - 1,
          replacementId: i < ids.length - 1 ? ids[i + 1] : null,
        ),
    ]);
    expect(c.resolve(ids.first).id, ids.last);
    expect(c.get(ids.first).id, ids.first);
  });
}
