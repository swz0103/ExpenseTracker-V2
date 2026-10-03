import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';

enum CatalogType { category, tag, merchant }

/// One change to a category, tag or merchant. [subject] is the entry whose
/// new version the command returns.
sealed class CatalogChange {
  const CatalogChange();

  PublicId get subject;

  Map<String, Object?> toJson();
}

final class CreateEntry extends CatalogChange {
  const CreateEntry(this.id, this.name, {this.kind, this.parentId});

  final PublicId id;
  final String name;

  /// Required for categories, ignored by tags and merchants.
  final CategoryKind? kind;
  final PublicId? parentId;

  @override
  PublicId get subject => id;

  @override
  Map<String, Object?> toJson() => {
    'change': 'create',
    'id': id.value,
    'name': name,
    'kind': kind?.name,
    'parentId': parentId?.value,
  };
}

final class RenameEntry extends CatalogChange {
  const RenameEntry(this.id, this.expectedVersion, this.name);

  final PublicId id;
  final int expectedVersion;
  final String name;

  @override
  PublicId get subject => id;

  @override
  Map<String, Object?> toJson() => {
    'change': 'rename',
    'id': id.value,
    'expectedVersion': expectedVersion,
    'name': name,
  };
}

final class ArchiveEntry extends CatalogChange {
  const ArchiveEntry(this.id, this.expectedVersion, {required this.archived});

  final PublicId id;
  final int expectedVersion;
  final bool archived;

  @override
  PublicId get subject => id;

  @override
  Map<String, Object?> toJson() => {
    'change': 'archive',
    'id': id.value,
    'expectedVersion': expectedVersion,
    'archived': archived,
  };
}

/// Redirects [sourceId] to [targetId]; history keeps the original id.
final class MergeEntry extends CatalogChange {
  const MergeEntry(
    this.sourceId,
    this.expectedSourceVersion,
    this.targetId,
    this.expectedTargetVersion,
  );

  final PublicId sourceId;
  final int expectedSourceVersion;
  final PublicId targetId;
  final int expectedTargetVersion;

  @override
  PublicId get subject => sourceId;

  @override
  Map<String, Object?> toJson() => {
    'change': 'merge',
    'sourceId': sourceId.value,
    'expectedSourceVersion': expectedSourceVersion,
    'targetId': targetId.value,
    'expectedTargetVersion': expectedTargetVersion,
  };
}

/// Categories only. A null parent promotes the category to the top level.
final class MoveCategory extends CatalogChange {
  const MoveCategory(this.id, this.expectedVersion, this.parentId);

  final PublicId id;
  final int expectedVersion;
  final PublicId? parentId;

  @override
  PublicId get subject => id;

  @override
  Map<String, Object?> toJson() => {
    'change': 'move',
    'id': id.value,
    'expectedVersion': expectedVersion,
    'parentId': parentId?.value,
  };
}

/// Merchants only.
final class ChangeAlias extends CatalogChange {
  const ChangeAlias(
    this.id,
    this.expectedVersion,
    this.alias, {
    required this.add,
  });

  final PublicId id;
  final int expectedVersion;
  final String alias;
  final bool add;

  @override
  PublicId get subject => id;

  @override
  Map<String, Object?> toJson() => {
    'change': add ? 'add-alias' : 'remove-alias',
    'id': id.value,
    'expectedVersion': expectedVersion,
    'alias': alias,
  };
}

/// Returns the new version of the change's subject.
final class ChangeCatalog implements Command<int> {
  ChangeCatalog({
    required this.operation,
    required this.catalog,
    required this.change,
  });

  @override
  final OperationKey operation;
  final CatalogType catalog;
  final CatalogChange change;

  @override
  String get input => jsonEncode({
    'command': 'change-catalog-v1',
    'catalog': catalog.name,
    ...change.toJson(),
  });

  @override
  String encodeResult(int result) => '$result';

  @override
  int decodeResult(String encoded) => int.parse(encoded);
}
