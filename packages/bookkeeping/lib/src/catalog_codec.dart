import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:merchants/merchants.dart';
import 'package:tags/tags.dart';

import 'codec.dart';

/// Versioned JSON for catalog rows. Decoding uses the domain `restore`
/// constructors; whole-catalog rules run when the catalog is restored.
abstract final class CatalogCodec {
  static const version = 1;

  static Map<String, Object?> category(Category row) => {
    ..._common(row.id, row.workspace, row.name, row.version),
    ..._lifecycle(row.archived, row.replacementId),
    'kind': row.kind.name,
    'parentId': row.parentId?.value,
  };

  static Map<String, Object?> tag(Tag row) => {
    ..._common(row.id, row.workspace, row.name, row.version),
    ..._lifecycle(row.archived, row.replacementId),
  };

  static Map<String, Object?> merchant(Merchant row) => {
    ..._common(row.id, row.workspace, row.name, row.version),
    ..._lifecycle(row.archived, row.replacementId),
    'aliases': row.aliases,
  };

  static Category readCategory(Map<String, Object?> json) => decoding(() {
    checkKeys(json, {..._keys, 'kind', 'parentId'});
    final parent = json['parentId'] as String?;
    return Category.restore(
      id: PublicId.parse(json['id'] as String),
      workspace: WorkspaceId.parse(json['workspace'] as String),
      name: json['name'] as String,
      kind: CategoryKind.values.byName(json['kind'] as String),
      version: json['entryVersion'] as int,
      parentId: parent == null ? null : PublicId.parse(parent),
      archived: json['archived'] as bool,
      replacementId: _replacement(json),
    );
  });

  static Tag readTag(Map<String, Object?> json) => decoding(() {
    checkKeys(json, _keys);
    return Tag.restore(
      id: PublicId.parse(json['id'] as String),
      workspace: WorkspaceId.parse(json['workspace'] as String),
      name: json['name'] as String,
      version: json['entryVersion'] as int,
      archived: json['archived'] as bool,
      replacementId: _replacement(json),
    );
  });

  static Merchant readMerchant(Map<String, Object?> json) => decoding(() {
    checkKeys(json, {..._keys, 'aliases'});
    return Merchant.restore(
      id: PublicId.parse(json['id'] as String),
      workspace: WorkspaceId.parse(json['workspace'] as String),
      name: json['name'] as String,
      version: json['entryVersion'] as int,
      archived: json['archived'] as bool,
      replacementId: _replacement(json),
      aliases: (json['aliases'] as List).cast<String>(),
    );
  });

  static const _keys = {
    'version',
    'id',
    'workspace',
    'name',
    'entryVersion',
    'archived',
    'replacementId',
  };

  static Map<String, Object?> _common(
    PublicId id,
    WorkspaceId workspace,
    String name,
    int entryVersion,
  ) => {
    'version': version,
    'id': id.value,
    'workspace': workspace.toString(),
    'name': name,
    'entryVersion': entryVersion,
  };

  static Map<String, Object?> _lifecycle(bool archived, PublicId? target) => {
    'archived': archived,
    'replacementId': target?.value,
  };

  static PublicId? _replacement(Map<String, Object?> json) {
    if (json['version'] != version) throw const CodecException('version');
    final value = json['replacementId'] as String?;
    return value == null ? null : PublicId.parse(value);
  }
}
