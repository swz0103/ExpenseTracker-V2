import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'commands.dart';

abstract base class _CardCommand<R> implements Command<R> {
  _CardCommand(this.operation);

  @override
  final OperationKey operation;

  Map<String, Object?> get fields;

  @override
  String get input => jsonEncode(fields);
}

abstract base class _IdResult extends _CardCommand<PublicId> {
  _IdResult(super.operation);

  @override
  String encodeResult(PublicId result) => result.value;

  @override
  PublicId decodeResult(String encoded) => PublicId.parse(encoded);
}

abstract base class _IntResult extends _CardCommand<int> {
  _IntResult(super.operation);

  @override
  String encodeResult(int result) => '$result';

  @override
  int decodeResult(String encoded) => int.parse(encoded);
}

/// Creates or revises a card's billing days. Returns the terms version.
final class SetCardTerms extends _IntResult {
  SetCardTerms({
    required OperationKey operation,
    required this.cardId,
    required this.expectedVersion,
    required this.closingDay,
    required this.dueDay,
    this.limit,
  }) : super(operation);

  final PublicId cardId;

  /// 0 when the card has no terms yet.
  final int expectedVersion;
  final int closingDay;
  final int dueDay;
  final Money? limit;

  @override
  Map<String, Object?> get fields => {
    'command': 'set-card-terms-v1',
    'cardId': cardId.value,
    'expectedVersion': expectedVersion,
    'closingDay': closingDay,
    'dueDay': dueDay,
    'limit': limit?.toJson(),
  };
}

/// Records a pending authorization. It has no ledger effect.
final class AuthorizeCardCharge extends _IdResult {
  AuthorizeCardCharge({
    required OperationKey operation,
    required this.chargeId,
    required this.cardId,
    required this.authorizedOn,
    required this.amount,
  }) : super(operation);

  final PublicId chargeId;
  final PublicId cardId;
  final BusinessDate authorizedOn;
  final Money amount;

  @override
  Map<String, Object?> get fields => {
    'command': 'authorize-card-charge-v1',
    'chargeId': chargeId.value,
    'cardId': cardId.value,
    'authorizedOn': authorizedOn.toString(),
    'amount': amount.toJson(),
  };
}

/// Posts a card purchase: one expense on the card for settled amount plus
/// fee. A pending authorization with [chargeId] is replaced, never added to.
/// Returns the posting id.
final class PostCardCharge extends _IdResult {
  PostCardCharge({
    required OperationKey operation,
    required this.chargeId,
    required this.postingId,
    required this.card,
    required this.postedOn,
    required this.settledAmount,
    required this.fee,
    this.allocations = const [],
    this.tags = const [],
    this.merchant,
  }) : super(operation);

  final PublicId chargeId;
  final PublicId postingId;
  final AccountRef card;
  final BusinessDate postedOn;
  final Money settledAmount;
  final Money fee;

  /// Empty, or shares adding up to settled amount plus fee.
  final List<CategoryShare> allocations;
  final List<TagSelection> tags;
  final MerchantSelection? merchant;

  @override
  Map<String, Object?> get fields => {
    'command': 'post-card-charge-v1',
    'chargeId': chargeId.value,
    'postingId': postingId.value,
    'card': card.toJson(),
    'postedOn': postedOn.toString(),
    'settledAmount': settledAmount.toJson(),
    'fee': fee.toJson(),
    'allocations': [for (final share in allocations) share.toJson()],
    'tags': [
      for (final tag in tags)
        {'id': tag.id.value, 'expectedVersion': tag.expectedVersion},
    ]..sort((a, b) => '${a['id']}'.compareTo('${b['id']}')),
    'merchant': merchant?.id.value,
    'merchantVersion': merchant?.expectedVersion,
  };
}

/// Pays a statement by transfer from [source] to the card. Never an expense.
/// Returns the posting id.
final class PayCard extends _IdResult {
  PayCard({
    required OperationKey operation,
    required this.paymentId,
    required this.postingId,
    required this.source,
    required this.card,
    required this.statementClose,
    required this.postedOn,
    required this.amount,
  }) : super(operation);

  final PublicId paymentId;
  final PublicId postingId;
  final AccountRef source;
  final AccountRef card;
  final BusinessDate statementClose;
  final BusinessDate postedOn;
  final Money amount;

  @override
  Map<String, Object?> get fields => {
    'command': 'pay-card-v1',
    'paymentId': paymentId.value,
    'postingId': postingId.value,
    'source': source.toJson(),
    'card': card.toJson(),
    'statementClose': statementClose.toString(),
    'postedOn': postedOn.toString(),
    'amount': amount.toJson(),
  };
}

/// Splits a posted purchase into a forecast installment schedule starting
/// with the statement the purchase falls in. Returns the installment count.
final class PlanInstallments extends _IntResult {
  PlanInstallments({
    required OperationKey operation,
    required this.chargeId,
    required this.count,
    required this.fixedFee,
  }) : super(operation);

  final PublicId chargeId;
  final int count;
  final Money fixedFee;

  @override
  Map<String, Object?> get fields => {
    'command': 'plan-installments-v1',
    'chargeId': chargeId.value,
    'count': count,
    'fixedFee': fixedFee.toJson(),
  };
}
