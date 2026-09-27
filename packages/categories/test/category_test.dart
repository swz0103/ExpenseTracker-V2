import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  final ws = WorkspaceId(PublicId.generate());
  final other = WorkspaceId(PublicId.generate());
  final root = PublicId.generate();
  final child = PublicId.generate();
  final target = PublicId.generate();
  Matcher error(CategoryError code) =>
      throwsA(isA<CategoryException>().having((e) => e.code, 'code', code));
  Category row(
    PublicId id, {
    WorkspaceId? workspace,
    CategoryKind kind = CategoryKind.expense,
    String name = '餐飲',
    int version = 1,
    PublicId? parent,
    bool archived = false,
    PublicId? replacement,
  }) => Category.restore(
    id: id,
    workspace: workspace ?? ws,
    name: name,
    kind: kind,
    version: version,
    parentId: parent,
    archived: archived,
    replacementId: replacement,
  );
  CategoryCatalog tree() => CategoryCatalog.restore(ws, [
    row(root),
    row(child, name: '午餐', parent: root),
    row(target, name: '其他'),
  ]);

  test('create and rename preserve IDs and previous immutable view', () {
    final empty = CategoryCatalog.empty(ws);
    final one = empty.create(
      workspace: ws,
      id: root,
      name: ' 餐飲 ',
      kind: CategoryKind.expense,
    );
    final renamed = one.rename(
      workspace: ws,
      id: root,
      expectedVersion: 1,
      name: '飲食',
    );
    expect(empty.categories, isEmpty);
    expect(one.get(root).name, '餐飲');
    expect(renamed.get(root).name, '飲食');
    expect(renamed.get(root).id, root);
    expect(renamed.get(root).version, 2);
    expect(() => renamed.categories.clear(), throwsUnsupportedError);
  });

  test(
    'new and restored names enforce the same validation without echoing input',
    () {
      for (final name in [
        '',
        '   ',
        'a' * 101,
        'private\ntext',
        'private\u0000text',
      ]) {
        expect(() => row(root, name: name), error(CategoryError.invalidInput));
        expect(
          () => CategoryCatalog.empty(ws).create(
            workspace: ws,
            id: root,
            name: name,
            kind: CategoryKind.expense,
          ),
          error(CategoryError.invalidInput),
        );
      }
      expect(
        const CategoryException(CategoryError.invalidInput).toString(),
        'CategoryException(invalidInput)',
      );
    },
  );

  test('workspace boundaries protect both rehydration and every command', () {
    expect(
      () => CategoryCatalog.restore(ws, [row(root, workspace: other)]),
      error(CategoryError.workspaceMismatch),
    );
    final catalog = tree();
    final commands = <void Function()>[
      () => catalog.create(
        workspace: other,
        id: PublicId.generate(),
        name: 'x',
        kind: CategoryKind.expense,
      ),
      () => catalog.rename(
        workspace: other,
        id: root,
        expectedVersion: 1,
        name: 'x',
      ),
      () => catalog.move(
        workspace: other,
        id: child,
        expectedVersion: 1,
        parentId: null,
      ),
      () => catalog.setArchived(
        workspace: other,
        id: child,
        expectedVersion: 1,
        archived: true,
      ),
      () => catalog.merge(
        workspace: other,
        sourceId: child,
        expectedSourceVersion: 1,
        targetId: target,
        expectedTargetVersion: 1,
      ),
      () => catalog.requireSelection(
        workspace: other,
        id: child,
        kind: CategoryKind.expense,
        expectedVersion: 1,
      ),
    ];
    for (final command in commands) {
      expect(command, error(CategoryError.workspaceMismatch));
    }
  });

  test(
    'duplicate identity is rejected while labels are not used as identity',
    () {
      expect(
        () => CategoryCatalog.restore(ws, [row(root), row(root)]),
        error(CategoryError.duplicate),
      );
      final catalog = CategoryCatalog.restore(ws, [row(root), row(child)]);
      expect(catalog.categories.length, 2);
      expect(
        () => catalog.create(
          workspace: ws,
          id: root,
          name: 'x',
          kind: CategoryKind.expense,
        ),
        error(CategoryError.duplicate),
      );
      expect(
        () => catalog.resolve(PublicId.generate()),
        error(CategoryError.missing),
      );
    },
  );

  test(
    'only two levels, existing parents and same-kind children are valid',
    () {
      expect(
        () => CategoryCatalog.restore(ws, [row(child, parent: root)]),
        error(CategoryError.invalidHierarchy),
      );
      expect(
        () => tree().create(
          workspace: ws,
          id: PublicId.generate(),
          name: '第三層',
          kind: CategoryKind.expense,
          parentId: child,
        ),
        error(CategoryError.invalidHierarchy),
      );
      expect(
        () => tree().create(
          workspace: ws,
          id: PublicId.generate(),
          name: '薪資',
          kind: CategoryKind.income,
          parentId: root,
        ),
        error(CategoryError.kindMismatch),
      );
      expect(
        () => CategoryCatalog.restore(ws, [
          row(root, parent: child),
          row(child, parent: root),
        ]),
        error(CategoryError.invalidHierarchy),
      );
      expect(() => row(root, parent: root), error(CategoryError.invalidInput));
    },
  );

  test('selection checks current kind, version, and archived status', () {
    final catalog = tree();
    catalog.requireSelection(
      workspace: ws,
      id: child,
      kind: CategoryKind.expense,
      expectedVersion: 1,
    );
    expect(
      () => catalog.requireSelection(
        workspace: ws,
        id: child,
        kind: CategoryKind.income,
        expectedVersion: 1,
      ),
      error(CategoryError.kindMismatch),
    );
    expect(
      () => catalog.requireSelection(
        workspace: ws,
        id: child,
        kind: CategoryKind.expense,
        expectedVersion: 2,
      ),
      error(CategoryError.versionConflict),
    );
    final archived = catalog.setArchived(
      workspace: ws,
      id: child,
      expectedVersion: 1,
      archived: true,
    );
    expect(archived.get(child).name, '午餐');
    expect(
      () => archived.requireSelection(
        workspace: ws,
        id: child,
        kind: CategoryKind.expense,
        expectedVersion: 2,
      ),
      error(CategoryError.unavailable),
    );
  });

  test(
    'archive parent requires children first; reactivate parent before child',
    () {
      final original = tree();
      expect(
        () => original.setArchived(
          workspace: ws,
          id: root,
          expectedVersion: 1,
          archived: true,
        ),
        error(CategoryError.hasChildren),
      );
      final archived = original
          .setArchived(
            workspace: ws,
            id: child,
            expectedVersion: 1,
            archived: true,
          )
          .setArchived(
            workspace: ws,
            id: root,
            expectedVersion: 1,
            archived: true,
          );
      expect(
        () => archived.setArchived(
          workspace: ws,
          id: child,
          expectedVersion: 2,
          archived: false,
        ),
        error(CategoryError.unavailable),
      );
      expect(
        () => archived.create(
          workspace: ws,
          id: PublicId.generate(),
          name: '新分類',
          kind: CategoryKind.expense,
          parentId: root,
        ),
        error(CategoryError.unavailable),
      );
      final active = archived
          .setArchived(
            workspace: ws,
            id: root,
            expectedVersion: 2,
            archived: false,
          )
          .setArchived(
            workspace: ws,
            id: child,
            expectedVersion: 2,
            archived: false,
          );
      active.requireSelection(
        workspace: ws,
        id: child,
        kind: CategoryKind.expense,
        expectedVersion: 3,
      );
      expect(archived.get(child).parentId, root);
    },
  );

  test('moving a child or promoting it keeps identity, moving a parent cannot create level three', () {
    final catalog = tree();
    final moved = catalog.move(
      workspace: ws,
      id: child,
      expectedVersion: 1,
      parentId: target,
    );
    expect(moved.get(child).parentId, target);
    final promoted = moved.move(
      workspace: ws,
      id: child,
      expectedVersion: 2,
      parentId: null,
    );
    expect(promoted.get(child).parentId, isNull);
    expect(promoted.get(child).id, child);
    expect(
      () => catalog.move(
        workspace: ws,
        id: root,
        expectedVersion: 1,
        parentId: target,
      ),
      error(CategoryError.invalidHierarchy),
    );
    expect(
      () => catalog.move(
        workspace: ws,
        id: child,
        expectedVersion: 1,
        parentId: child,
      ),
      error(CategoryError.invalidInput),
    );
    final historicalChild = catalog.setArchived(
      workspace: ws,
      id: child,
      expectedVersion: 1,
      archived: true,
    );
    expect(
      () => historicalChild.move(
        workspace: ws,
        id: root,
        expectedVersion: 1,
        parentId: target,
      ),
      error(CategoryError.invalidHierarchy),
    );
  });

  test('explicit merge preserves original reference and immutable label', () {
    final catalog = tree();
    final merged = catalog.merge(
      workspace: ws,
      sourceId: child,
      expectedSourceVersion: 1,
      targetId: target,
      expectedTargetVersion: 1,
    );
    expect(merged.get(child).name, '午餐');
    expect(merged.get(child).parentId, root);
    expect(merged.get(child).replacementId, target);
    expect(merged.resolve(child).id, target);
    expect(catalog.resolve(child).id, child);
    expect(
      () => merged.rename(
        workspace: ws,
        id: child,
        expectedVersion: 2,
        name: '改掉',
      ),
      error(CategoryError.unavailable),
    );
    expect(
      () => merged.setArchived(
        workspace: ws,
        id: child,
        expectedVersion: 2,
        archived: false,
      ),
      error(CategoryError.unavailable),
    );
    expect(
      () => merged.requireSelection(
        workspace: ws,
        id: child,
        kind: CategoryKind.expense,
        expectedVersion: 2,
      ),
      error(CategoryError.unavailable),
    );
  });

  test('merges reject stale targets, cross-kind, self and parents with historical children', () {
    final catalog = tree();
    expect(
      () => catalog.merge(
        workspace: ws,
        sourceId: child,
        expectedSourceVersion: 1,
        targetId: target,
        expectedTargetVersion: 0,
      ),
      error(CategoryError.versionConflict),
    );
    expect(
      () => catalog.merge(
        workspace: ws,
        sourceId: child,
        expectedSourceVersion: 0,
        targetId: target,
        expectedTargetVersion: 1,
      ),
      error(CategoryError.versionConflict),
    );
    expect(
      () => catalog.merge(
        workspace: ws,
        sourceId: target,
        expectedSourceVersion: 1,
        targetId: target,
        expectedTargetVersion: 1,
      ),
      error(CategoryError.invalidInput),
    );
    final income = CategoryCatalog.restore(ws, [
      row(child),
      row(target, kind: CategoryKind.income),
    ]);
    expect(
      () => income.merge(
        workspace: ws,
        sourceId: child,
        expectedSourceVersion: 1,
        targetId: target,
        expectedTargetVersion: 1,
      ),
      error(CategoryError.kindMismatch),
    );
    final archivedChild = catalog.setArchived(
      workspace: ws,
      id: child,
      expectedVersion: 1,
      archived: true,
    );
    expect(
      () => archivedChild.merge(
        workspace: ws,
        sourceId: root,
        expectedSourceVersion: 1,
        targetId: target,
        expectedTargetVersion: 1,
      ),
      error(CategoryError.hasChildren),
    );
  });

  test(
    'historical redirect chains survive target archive and restore exactly',
    () {
      final last = PublicId.generate();
      final original = tree().create(
        workspace: ws,
        id: last,
        name: '最終',
        kind: CategoryKind.expense,
      );
      final merged = original
          .merge(
            workspace: ws,
            sourceId: child,
            expectedSourceVersion: 1,
            targetId: target,
            expectedTargetVersion: 1,
          )
          .merge(
            workspace: ws,
            sourceId: target,
            expectedSourceVersion: 1,
            targetId: last,
            expectedTargetVersion: 1,
          )
          .setArchived(
            workspace: ws,
            id: last,
            expectedVersion: 1,
            archived: true,
          );
      final restored = CategoryCatalog.restore(ws, merged.categories);
      expect(restored.resolve(child).id, last);
      expect(restored.resolve(target).archived, isTrue);
      expect(restored.get(child).replacementId, target);
      expect(
        () => restored.requireSelection(
          workspace: ws,
          id: last,
          kind: CategoryKind.expense,
          expectedVersion: 2,
        ),
        error(CategoryError.unavailable),
      );
    },
  );

  test(
    'corrupt restore rejects missing targets, cycles and active redirects',
    () {
      expect(
        () => CategoryCatalog.restore(ws, [
          row(root, archived: true, replacement: target),
        ]),
        error(CategoryError.missing),
      );
      expect(
        () => CategoryCatalog.restore(ws, [
          row(root, archived: true, replacement: target),
          row(target, archived: true, replacement: root),
        ]),
        error(CategoryError.replacementCycle),
      );
      expect(
        () => row(root, replacement: target),
        error(CategoryError.invalidInput),
      );
      expect(
        () => row(root, archived: true, replacement: root),
        error(CategoryError.invalidInput),
      );
      expect(
        () => CategoryCatalog.restore(ws, [
          row(root, archived: true),
          row(child, parent: root),
        ]),
        error(CategoryError.unavailable),
      );
    },
  );

  test(
    'exhausted revision remains readable but cannot wrap through mutation',
    () {
      const max = 9223372036854775807;
      expect(() => row(root, version: 0), error(CategoryError.invalidInput));
      final catalog = CategoryCatalog.restore(ws, [row(root, version: max)]);
      catalog.requireSelection(
        workspace: ws,
        id: root,
        kind: CategoryKind.expense,
        expectedVersion: max,
      );
      expect(
        () => catalog.rename(
          workspace: ws,
          id: root,
          expectedVersion: max,
          name: 'x',
        ),
        error(CategoryError.versionConflict),
      );
      expect(catalog.get(root).version, max);
    },
  );

  test('a 10000-entity historical chain rehydrates without recursion or quadratic rescans', () {
    final ids = List.generate(10000, (_) => PublicId.generate());
    final catalog = CategoryCatalog.restore(ws, [
      for (var i = 0; i < ids.length; i++)
        row(
          ids[i],
          archived: i != ids.length - 1,
          replacement: i == ids.length - 1 ? null : ids[i + 1],
        ),
    ]);
    for (final id in ids) {
      expect(catalog.resolve(id).id, ids.last);
    }
    expect(catalog.get(ids.first).replacementId, ids[1]);
  });
}
