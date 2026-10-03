import 'package:tags/tags.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

Matcher fails(TagError code) =>
    throwsA(isA<TagException>().having((e) => e.code, 'code', code));

void main() {
  final ws = WorkspaceId(PublicId.generate());
  final id = PublicId.generate(), target = PublicId.generate();
  TagCatalog initial() =>
      TagCatalog.empty(ws)
          .create(workspace: ws, id: id, name: '  旅行  ')
          .create(workspace: ws, id: target, name: '出差');
  test('names are unique ignoring width and case', () {
    expect(
      () => initial().create(
        workspace: ws,
        id: PublicId.generate(),
        name: '旅行',
      ),
      fails(TagError.duplicate),
    );
    expect(
      () => initial().rename(
        workspace: ws,
        id: target,
        expectedVersion: 1,
        name: ' 旅行 ',
      ),
      fails(TagError.duplicate),
    );
    final merged = initial().merge(
      workspace: ws,
      sourceId: id,
      expectedSourceVersion: 1,
      targetId: target,
      expectedTargetVersion: 1,
    );
    // A merged-away tag no longer holds its name.
    merged.create(workspace: ws, id: PublicId.generate(), name: '旅行');
  });
  test(
    'flat identities stay independent through renames and views stay immutable',
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
      fails(TagError.unavailable),
    );
    final b = a.setArchived(
      workspace: ws,
      id: id,
      expectedVersion: 2,
      archived: false,
    );
    expect(
      () => b.requireSelection(workspace: ws, id: id, expectedVersion: 1),
      fails(TagError.versionConflict),
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
      fails(TagError.unavailable),
    );
    expect(
      () => initial().merge(
        workspace: ws,
        sourceId: id,
        expectedSourceVersion: 1,
        targetId: target,
        expectedTargetVersion: 2,
      ),
      fails(TagError.versionConflict),
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
      fails(TagError.workspaceMismatch),
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
      fails(TagError.missing),
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
      fails(TagError.replacementCycle),
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
        fails(TagError.invalidInput),
      );
    }
    expect(
      () => initial().rename(
        workspace: ws,
        id: id,
        expectedVersion: 1,
        name: 'a\nb',
      ),
      fails(TagError.invalidInput),
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
      fails(TagError.versionConflict),
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
