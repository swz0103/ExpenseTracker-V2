import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:reports/reports.dart';

import 'budget.dart';

/// Strict, versioned representation for one authoritative budget plan.
/// Persistence and portable backup must use the same decoded contract.
final class BudgetPlanCodec {
  static const formatVersion = 1;
  static const maxBytes = 16384;

  /// Low enough that a plan using every selection on both lists still
  /// fits in [maxBytes], so this bound is reachable on its own.
  static const maxSelections = 150;

  static const _keys = {
    'format',
    'id',
    'workspace',
    'year',
    'month',
    'limit',
    'version',
    'categoryId',
    'accountIds',
    'tagIds',
    'warningPercent',
  };

  String encode(BudgetPlan plan) {
    if (plan.accountIds.length > maxSelections ||
        plan.tagIds.length > maxSelections) {
      throw const FormatException('Too many budget selections');
    }
    final accountIds = plan.accountIds.map((id) => id.value).toList()..sort();
    final tagIds = plan.tagIds.map((id) => id.value).toList()..sort();
    final value = jsonEncode({
      'format': formatVersion,
      'id': plan.id.value,
      'workspace': plan.workspace.id.value,
      'year': plan.month.year,
      'month': plan.month.month,
      'limit': plan.limit.toJson(),
      'version': plan.version,
      'categoryId': plan.categoryId?.value,
      'accountIds': accountIds,
      'tagIds': tagIds,
      'warningPercent': plan.warningPercent,
    });
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Budget plan exceeds size limit');
    }
    return value;
  }

  BudgetPlan decode(String value) {
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Budget plan exceeds size limit');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      throw const FormatException('Invalid budget plan JSON');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.keys.toSet().length != _keys.length ||
        !decoded.keys.toSet().containsAll(_keys) ||
        decoded['format'] != formatVersion ||
        decoded['id'] is! String ||
        decoded['workspace'] is! String ||
        decoded['year'] is! int ||
        decoded['month'] is! int ||
        decoded['version'] is! int ||
        decoded['warningPercent'] is! int ||
        decoded['categoryId'] != null && decoded['categoryId'] is! String) {
      throw const FormatException('Invalid budget plan fields');
    }
    final limit = decoded['limit'];
    if (limit is! Map<String, dynamic> ||
        limit.keys.toSet().length != 4 ||
        !limit.keys.toSet().containsAll({
          'version',
          'currency',
          'scale',
          'minorUnits',
        })) {
      throw const FormatException('Invalid budget limit');
    }
    final accounts = _decodeIds(decoded['accountIds']);
    final tags = _decodeIds(decoded['tagIds']);
    return BudgetPlan(
      id: PublicId.parse(decoded['id'] as String),
      workspace: WorkspaceId.parse(decoded['workspace'] as String),
      month: ReportMonth(decoded['year'] as int, decoded['month'] as int),
      limit: Money.fromJson(Map<String, Object?>.from(limit)),
      version: decoded['version'] as int,
      categoryId: decoded['categoryId'] == null
          ? null
          : PublicId.parse(decoded['categoryId'] as String),
      accountIds: accounts,
      tagIds: tags,
      warningPercent: decoded['warningPercent'] as int,
    );
  }

  Set<PublicId> _decodeIds(Object? value) {
    if (value is! List || value.length > maxSelections) {
      throw const FormatException('Invalid budget selections');
    }
    final ids = <PublicId>{};
    for (final item in value) {
      if (item is! String || !ids.add(PublicId.parse(item))) {
        throw const FormatException('Duplicate or invalid budget selection');
      }
    }
    return ids;
  }
}
