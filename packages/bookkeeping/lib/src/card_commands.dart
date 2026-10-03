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

/// Drops a pending authorization that will never post, for example a
/// cancelled hold. Returns the charge id.
final class ReleaseAuthorization extends _IdResult {
  ReleaseAuthorization({
    required OperationKey operation,
    required this.chargeId,
    required this.cardId,
  }) : super(operation);

  final PublicId chargeId;
  final PublicId cardId;

  @override
  Map<String, Object?> get fields => {
    'command': 'release-authorization-v1',
    'chargeId': chargeId.value,
    'cardId': cardId.value,
  };
}

/// A merchant credit for a posted purchase, booked on the card: it lowers
/// the card balance, the statement and the original spending. Returns the
/// refund posting id.
final class RefundCardCharge extends _IdResult {
  RefundCardCharge({
    required OperationKey operation,
    required this.refundChargeId,
    required this.postingId,
    required this.originalChargeId,
    required this.card,
    required this.postedOn,
    required this.amount,
    this.allocations = const [],
  }) : super(operation);

  final PublicId refundChargeId;
  final PublicId postingId;
  final PublicId originalChargeId;
  final AccountRef card;
  final BusinessDate postedOn;
  final Money amount;

  /// Empty, or the categories the credit goes back to.
  final List<CategoryShare> allocations;

  @override
  Map<String, Object?> get fields => {
    'command': 'refund-card-charge-v1',
    'refundChargeId': refundChargeId.value,
    'postingId': postingId.value,
    'originalChargeId': originalChargeId.value,
    'card': card.toJson(),
    'postedOn': postedOn.toString(),
    'amount': amount.toJson(),
    'allocations': [for (final share in allocations) share.toJson()],
  };
}

/// Removes a posted charge or card refund entered by mistake: its posting
/// is reversed on its own date and it leaves the statement. A purchase
/// with active refunds or an installment plan cannot be voided. Returns
/// the reversal posting id.
final class VoidCardCharge extends _IdResult {
  VoidCardCharge({
    required OperationKey operation,
    required this.chargeId,
    required this.reversalId,
  }) : super(operation);

  final PublicId chargeId;
  final PublicId reversalId;

  @override
  Map<String, Object?> get fields => {
    'command': 'void-card-charge-v1',
    'chargeId': chargeId.value,
    'reversalId': reversalId.value,
  };
}

/// Removes a card payment entered by mistake: the transfer is reversed on
/// its own date and the payment leaves the statement. Returns the reversal
/// posting id.
final class VoidCardPayment extends _IdResult {
  VoidCardPayment({
    required OperationKey operation,
    required this.paymentId,
    required this.reversalId,
  }) : super(operation);

  final PublicId paymentId;
  final PublicId reversalId;

  @override
  Map<String, Object?> get fields => {
    'command': 'void-card-payment-v1',
    'paymentId': paymentId.value,
    'reversalId': reversalId.value,
  };
}
