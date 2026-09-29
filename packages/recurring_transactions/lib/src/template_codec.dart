import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';

import 'recurrence.dart';

/// Canonical, bounded payload for a future authoritative template revision.
/// Persisted rows and portable snapshots must both validate this contract.
final class RecurringTemplateCodec {
  static const formatVersion = 1;
  static const maxBytes = 4096;
  static const _keys = {
    'format',
    'id',
    'workspace',
    'accountId',
    'label',
    'amount',
    'firstDate',
    'unit',
    'every',
    'version',
  };

  String encode(RecurringTemplate template) {
    final value = jsonEncode({
      'format': formatVersion,
      'id': template.id.value,
      'workspace': template.workspace.id.value,
      'accountId': template.accountId.value,
      'label': template.label,
      'amount': template.amount.toJson(),
      'firstDate': template.firstDate.toString(),
      'unit': template.unit.name,
      'every': template.every,
      'version': template.version,
    });
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Recurring template exceeds size limit');
    }
    return value;
  }

  RecurringTemplate decode(String value) {
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Recurring template exceeds size limit');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      throw const FormatException('Invalid recurring template JSON');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.keys.toSet().length != _keys.length ||
        !decoded.keys.toSet().containsAll(_keys) ||
        decoded['format'] != formatVersion ||
        decoded['id'] is! String ||
        decoded['workspace'] is! String ||
        decoded['accountId'] is! String ||
        decoded['label'] is! String ||
        decoded['firstDate'] is! String ||
        decoded['unit'] is! String ||
        decoded['every'] is! int ||
        decoded['version'] is! int) {
      throw const FormatException('Invalid recurring template fields');
    }
    final amount = decoded['amount'];
    if (amount is! Map<String, dynamic> ||
        amount.keys.toSet().length != 4 ||
        !amount.keys.toSet().containsAll({
          'version',
          'currency',
          'scale',
          'minorUnits',
        })) {
      throw const FormatException('Invalid recurring amount');
    }
    final unit = switch (decoded['unit']) {
      'day' => RecurrenceUnit.day,
      'week' => RecurrenceUnit.week,
      'month' => RecurrenceUnit.month,
      'year' => RecurrenceUnit.year,
      _ => throw const FormatException('Invalid recurrence unit'),
    };
    final template = RecurringTemplate(
      id: PublicId.parse(decoded['id'] as String),
      workspace: WorkspaceId.parse(decoded['workspace'] as String),
      accountId: PublicId.parse(decoded['accountId'] as String),
      label: decoded['label'] as String,
      amount: Money.fromJson(Map<String, Object?>.from(amount)),
      firstDate: BusinessDate.parse(decoded['firstDate'] as String),
      unit: unit,
      every: decoded['every'] as int,
      version: decoded['version'] as int,
    );
    if (encode(template) != value) {
      throw const FormatException('Noncanonical recurring template');
    }
    return template;
  }
}
