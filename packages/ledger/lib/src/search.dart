import 'package:foundation_values/foundation_values.dart';

import 'posting.dart';

/// Versioned AND predicate for authoritative Ledger reads. Search never
/// changes a posting, and amount bounds compare absolute first-leg principal
/// in one explicitly selected currency. Opening and transfer events remain
/// searchable, but report totals must apply their own financial semantics.
final class LedgerSearchQuery {
  LedgerSearchQuery({
    this.from,
    this.through,
    this.accountId,
    this.categoryId,
    this.tagId,
    this.merchantId,
    this.currency,
    this.kind,
    this.minAbsAmount,
    this.maxAbsAmount,
    this.noteContains,
  }) {
    if (from != null && through != null && from!.compareTo(through!) > 0) {
      throw const FormatException('Search date range is reversed.');
    }
    if (minAbsAmount != null || maxAbsAmount != null) {
      if (currency == null ||
          (minAbsAmount != null && minAbsAmount!.currency != currency) ||
          (maxAbsAmount != null && maxAbsAmount!.currency != currency) ||
          (minAbsAmount?.minorUnits.isNegative ?? false) ||
          (maxAbsAmount?.minorUnits.isNegative ?? false) ||
          (minAbsAmount != null &&
              maxAbsAmount != null &&
              minAbsAmount!.minorUnits > maxAbsAmount!.minorUnits)) {
        throw const FormatException('Invalid search amount range.');
      }
    }
    if (noteContains != null &&
        (noteContains!.trim().isEmpty || noteContains!.runes.length > 100)) {
      throw const FormatException('Invalid search note text.');
    }
  }

  static const version = 1;
  static const _keys = {
    'version',
    'from',
    'through',
    'accountId',
    'categoryId',
    'tagId',
    'merchantId',
    'currency',
    'kind',
    'minAbsMinor',
    'maxAbsMinor',
    'noteContains',
  };

  final BusinessDate? from, through;
  final PublicId? accountId, categoryId, tagId, merchantId;
  final Currency? currency;
  final PostingKind? kind;
  final Money? minAbsAmount, maxAbsAmount;
  final String? noteContains;

  factory LedgerSearchQuery.fromJson(Map<String, Object?> json) {
    if (json['version'] != version ||
        json.keys.any((key) => !_keys.contains(key))) {
      throw const FormatException('Unsupported search query.');
    }
    String? field(String name) {
      if (!json.containsKey(name)) return null;
      final value = json[name];
      if (value is! String) throw FormatException('Invalid search $name.');
      return value;
    }

    final currencyValue = json['currency'];
    Currency? currency;
    if (json.containsKey('currency')) {
      if (currencyValue is! Map ||
          currencyValue.length != 2 ||
          currencyValue['code'] is! String ||
          currencyValue['scale'] is! int) {
        throw const FormatException('Invalid search currency.');
      }
      currency = Currency(
        currencyValue['code'] as String,
        currencyValue['scale'] as int,
      );
    }
    Money? amount(String name) {
      final raw = field(name);
      if (raw == null) return null;
      if (currency == null ||
          raw.length > 19 ||
          !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(raw)) {
        throw FormatException('Invalid search $name.');
      }
      return Money(currency, parseMinorUnits(raw));
    }

    final kindName = field('kind');
    final kind = kindName == null
        ? null
        : PostingKind.values
              .where((value) => value.name == kindName)
              .firstOrNull;
    if (kindName != null && kind == null) {
      throw const FormatException('Unknown posting kind.');
    }
    return LedgerSearchQuery(
      from: field('from') == null ? null : BusinessDate.parse(field('from')!),
      through: field('through') == null
          ? null
          : BusinessDate.parse(field('through')!),
      accountId: field('accountId') == null
          ? null
          : PublicId.parse(field('accountId')!),
      categoryId: field('categoryId') == null
          ? null
          : PublicId.parse(field('categoryId')!),
      tagId: field('tagId') == null ? null : PublicId.parse(field('tagId')!),
      merchantId: field('merchantId') == null
          ? null
          : PublicId.parse(field('merchantId')!),
      currency: currency,
      kind: kind,
      minAbsAmount: amount('minAbsMinor'),
      maxAbsAmount: amount('maxAbsMinor'),
      noteContains: field('noteContains'),
    );
  }

  Map<String, Object> toJson() => {
    'version': version,
    if (from != null) 'from': from.toString(),
    if (through != null) 'through': through.toString(),
    if (accountId != null) 'accountId': accountId!.value,
    if (categoryId != null) 'categoryId': categoryId!.value,
    if (tagId != null) 'tagId': tagId!.value,
    if (merchantId != null) 'merchantId': merchantId!.value,
    if (currency != null)
      'currency': {'code': currency!.code, 'scale': currency!.scale},
    if (kind != null) 'kind': kind!.name,
    if (minAbsAmount != null)
      'minAbsMinor': minAbsAmount!.minorUnits.toString(),
    if (maxAbsAmount != null)
      'maxAbsMinor': maxAbsAmount!.minorUnits.toString(),
    if (noteContains != null) 'noteContains': noteContains!,
  };
}
