import 'package:foundation_values/foundation_values.dart';
import 'package:merchants/merchants.dart';
import 'package:test/test.dart';

void main() {
  final ws = WorkspaceId(PublicId.generate());
  final a = PublicId.generate(), b = PublicId.generate();
  MerchantCatalog initial() =>
      MerchantCatalog.empty(ws)
          .create(workspace: ws, id: a, name: '便利商店甲')
          .create(workspace: ws, id: b, name: '便利商店乙');
  MerchantCatalog add(MerchantCatalog catalog, PublicId id, String alias) =>
      catalog.addAlias(
        workspace: ws,
        id: id,
        expectedVersion: catalog.get(id).version,
        alias: alias,
      );
  final error = throwsA(isA<MerchantException>());

  test('alias input and all exported views are immutable', () {
    final names = ['  SEVEN  ', '7-11'];
    final row = Merchant.restore(
      id: a,
      workspace: ws,
      name: '超商',
      version: 1,
      aliases: names,
    );
    names.clear();
    expect(row.aliases, ['7-11', 'SEVEN']);
    expect(() => row.aliases.clear(), throwsUnsupportedError);
    final catalog = MerchantCatalog.restore(ws, [row]);
    expect(() => catalog.candidates('seven').clear(), throwsUnsupportedError);
  });

  test('exact candidates preserve punctuation and internal whitespace', () {
    final catalog = add(add(initial(), a, '  SEVEN  '), a, 'Seven Shop');
    expect(catalog.candidates('seven').single.id, a);
    expect(catalog.candidates(' SEvEN ').single.id, a);
    expect(catalog.candidates('Seven Shop').single.id, a);
    expect(catalog.candidates('Seven  Shop'), isEmpty);
    expect(catalog.candidates('7-11'), isEmpty);
    expect(catalog.candidates('Seven!'), isEmpty);
    expect(catalog.candidates('  '), isEmpty);
    expect(catalog.candidates('便利商店甲').single.id, a);
  });

  test(
    'equal aliases across identities remain ambiguous until explicit merge',
    () {
      final catalog = add(add(initial(), a, 'SEVEN'), b, 'seven');
      expect(catalog.candidates('seven').map((m) => m.id).toSet(), {a, b});
      expect(catalog.merchants.every((m) => m.replacementId == null), isTrue);
      final merged = catalog.merge(
        workspace: ws,
        sourceId: a,
        expectedSourceVersion: 2,
        targetId: b,
        expectedTargetVersion: 2,
      );
      expect(merged.candidates('seven').single.id, b);
      expect(merged.candidates('便利商店甲').single.id, b);
      expect(merged.get(a).aliases, ['SEVEN']);
      expect(catalog.resolve(a).id, a);
      expect(
        () => merged.requireSelection(workspace: ws, id: a, expectedVersion: 3),
        error,
      );
      merged.requireSelection(workspace: ws, id: b, expectedVersion: 2);
    },
  );

  test('archived canonical identity hides all redirected suggestions until enabled', () {
    final first = add(initial(), a, 'SHOP');
    final merged = first.merge(
      workspace: ws,
      sourceId: a,
      expectedSourceVersion: 2,
      targetId: b,
      expectedTargetVersion: 1,
    );
    final archived = merged.setArchived(
      workspace: ws,
      id: b,
      expectedVersion: 1,
      archived: true,
    );
    expect(archived.candidates('shop'), isEmpty);
    expect(archived.candidates('便利商店乙'), isEmpty);
    expect(archived.resolve(a).id, b);
    final active = archived.setArchived(
      workspace: ws,
      id: b,
      expectedVersion: 2,
      archived: false,
    );
    expect(active.candidates('shop').single.id, b);
  });

  test(
    'removing an alias advances version and does not change old catalog',
    () {
      final first = add(initial(), a, 'SHOP');
      final next = first.removeAlias(
        workspace: ws,
        id: a,
        expectedVersion: 2,
        alias: ' shop ',
      );
      expect(next.get(a).version, 3);
      expect(next.candidates('shop'), isEmpty);
      expect(first.candidates('shop').single.id, a);
      expect(
        () => next.removeAlias(
          workspace: ws,
          id: a,
          expectedVersion: 3,
          alias: 'shop',
        ),
        error,
      );
      expect(
        () => next.addAlias(
          workspace: ws,
          id: a,
          expectedVersion: 2,
          alias: 'NEW',
        ),
        error,
      );
      expect(
        () => first.removeAlias(
          workspace: WorkspaceId(PublicId.generate()),
          id: a,
          expectedVersion: 2,
          alias: 'SHOP',
        ),
        error,
      );
    },
  );

  test('duplicate and malformed aliases fail without changing a catalog', () {
    final catalog = add(initial(), a, 'SHOP');
    for (final alias in ['', ' ', 'x' * 101, 'x\ny', 'shop', '便利商店甲']) {
      expect(() => add(catalog, a, alias), error, reason: alias);
    }
    expect(catalog.get(a).version, 2);
    expect(catalog.get(a).aliases, ['SHOP']);
    expect(
      () => Merchant.restore(
        id: a,
        workspace: ws,
        name: 'x',
        version: 1,
        aliases: ['SHOP', ' shop '],
      ),
      error,
    );
    expect(
      () => Merchant.restore(
        id: a,
        workspace: ws,
        name: 'x',
        version: 1,
        aliases: ['\u0000'],
      ),
      error,
    );
  });

  test(
    'alias capacity is explicit and may be freed without replacing identity',
    () {
      var full = initial();
      for (var i = 0; i < 16; i++) {
        full = add(full, a, 'Alias $i');
      }
      expect(full.get(a).aliases.length, 16);
      expect(() => add(full, a, 'Alias 17'), error);
      final removed = full.removeAlias(
        workspace: ws,
        id: a,
        expectedVersion: 17,
        alias: 'Alias 0',
      );
      final replacement = add(removed, a, 'Alias 17');
      expect(replacement.get(a).id, a);
      expect(replacement.get(a).aliases.length, 16);
      expect(replacement.get(a).version, 19);
      expect(full.candidates('Alias 0').single.id, a);
    },
  );

  test('rename retains aliases and identity without adding guessed names', () {
    final prior = add(initial(), a, 'SHOP');
    final renamed = prior.rename(
      workspace: ws,
      id: a,
      expectedVersion: 2,
      name: '新名稱',
    );
    expect(renamed.candidates('SHOP').single.id, a);
    expect(renamed.candidates('新名稱').single.id, a);
    expect(renamed.candidates('便利商店甲'), isEmpty);
    expect(prior.get(a).name, '便利商店甲');
  });

  test('aliases never resolve a different workspace and merged sources are immutable', () {
    final catalog = add(initial(), a, 'SHOP');
    final foreign = WorkspaceId(PublicId.generate());
    final other = MerchantCatalog.empty(foreign)
        .create(workspace: foreign, id: a, name: 'SHOP');
    expect(other.candidates('SHOP').single.workspace, foreign);
    expect(catalog.candidates('SHOP').single.workspace, ws);
    expect(
      () => catalog.addAlias(
        workspace: foreign,
        id: a,
        expectedVersion: 2,
        alias: 'NEW',
      ),
      error,
    );
    final merged = catalog.merge(
      workspace: ws,
      sourceId: a,
      expectedSourceVersion: 2,
      targetId: b,
      expectedTargetVersion: 1,
    );
    expect(
      () => merged.addAlias(
        workspace: ws,
        id: a,
        expectedVersion: 3,
        alias: 'NEW',
      ),
      error,
    );
    expect(
      () => merged.removeAlias(
        workspace: ws,
        id: a,
        expectedVersion: 3,
        alias: 'SHOP',
      ),
      error,
    );
  });
}
