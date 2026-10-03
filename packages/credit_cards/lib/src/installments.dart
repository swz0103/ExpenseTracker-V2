import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';

import 'card_billing.dart';

/// A schedule derived from one already-posted card purchase. It does not post
/// another expense, claim an issuer statement, or allocate a payment.
final class CardInstallmentSchedule {
  CardInstallmentSchedule({
    required this.purchaseEventId,
    required this.workspace,
    required this.cardId,
    required this.principal,
    required this.fixedFee,
    required this.firstScheduledClose,
    required this.closingDay,
    required this.count,
  }) {
    if (count < 2 ||
        count > 120 ||
        closingDay < 1 ||
        closingDay > 31 ||
        principal.minorUnits < BigInt.from(count) ||
        fixedFee.minorUnits < BigInt.zero ||
        principal.currency != fixedFee.currency ||
        principal.minorUnits + fixedFee.minorUnits > Money.maxMinorUnits) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
    final firstMonthEnd = DateTime.utc(
      firstScheduledClose.year,
      firstScheduledClose.month + 1,
      0,
    ).day;
    if (firstScheduledClose.day !=
        (closingDay < firstMonthEnd ? closingDay : firstMonthEnd)) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
    // Reject dates that cannot accommodate the whole schedule.
    if (firstScheduledClose.year * 12 +
            firstScheduledClose.month -
            1 +
            count -
            1 >
        9999 * 12 + 11) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
  }

  final PublicId purchaseEventId;
  final WorkspaceId workspace;
  final PublicId cardId;
  final Money principal;
  final Money fixedFee;
  final BusinessDate firstScheduledClose;
  final int closingDay;
  final int count;

  /// Equal installments rounded down; the whole remainder goes into the
  /// first one, as Taiwan card issuers bill it (feature audit G-23).
  List<CardInstallment> get installments {
    final principals = _splitFirst(principal, count);
    final fees = _splitFirst(fixedFee, count);
    return List.unmodifiable(
      List.generate(count, (index) {
        final month = DateTime.utc(
          firstScheduledClose.year,
          firstScheduledClose.month + index,
          1,
        );
        final lastDay = DateTime.utc(month.year, month.month + 1, 0).day;
        return CardInstallment(
          number: index + 1,
          scheduledClose: BusinessDate(
            month.year,
            month.month,
            closingDay <= lastDay ? closingDay : lastDay,
          ),
          principal: principals[index],
          fee: fees[index],
        );
      }),
    );
  }
}

List<Money> _splitFirst(Money total, int count) {
  final each = total.minorUnits ~/ BigInt.from(count);
  final first = total.minorUnits - each * BigInt.from(count - 1);
  return [
    Money(total.currency, first),
    for (var i = 1; i < count; i++) Money(total.currency, each),
  ];
}

final class CardInstallment {
  const CardInstallment({
    required this.number,
    required this.scheduledClose,
    required this.principal,
    required this.fee,
  });

  final int number;
  final BusinessDate scheduledClose;
  final Money principal;
  final Money fee;

  /// Forecast only. An issuer-confirmed statement remains a separate fact.
  Money get projectedCharge => principal + fee;
}

/// Strict, versioned representation for a future authoritative plan record.
/// The owning store must still verify that [purchaseEventId] is a posted card
/// purchase belonging to this workspace and card before committing it.
final class CardInstallmentScheduleCodec {
  const CardInstallmentScheduleCodec();

  String encode(CardInstallmentSchedule plan) => jsonEncode({
    'format': 1,
    'purchaseEventId': plan.purchaseEventId.value,
    'workspace': plan.workspace.id.value,
    'cardId': plan.cardId.value,
    'currency': plan.principal.currency.code,
    'scale': plan.principal.currency.scale,
    'principalMinor': plan.principal.minorUnits.toString(),
    'fixedFeeMinor': plan.fixedFee.minorUnits.toString(),
    'firstScheduledClose': plan.firstScheduledClose.toString(),
    'closingDay': plan.closingDay,
    'count': plan.count,
  });

  CardInstallmentSchedule decode(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value.length != 11 ||
          value['format'] != 1 ||
          value['purchaseEventId'] is! String ||
          value['workspace'] is! String ||
          value['cardId'] is! String ||
          value['currency'] is! String ||
          value['scale'] is! int ||
          value['principalMinor'] is! String ||
          value['fixedFeeMinor'] is! String ||
          value['firstScheduledClose'] is! String ||
          value['closingDay'] is! int ||
          value['count'] is! int ||
          (value['principalMinor'] as String).length > 20 ||
          (value['fixedFeeMinor'] as String).length > 20) {
        throw const FormatException('Invalid installment plan');
      }
      final currency = Currency(
        value['currency'] as String,
        value['scale'] as int,
      );
      final plan = CardInstallmentSchedule(
        purchaseEventId: PublicId.parse(value['purchaseEventId'] as String),
        workspace: WorkspaceId.parse(value['workspace'] as String),
        cardId: PublicId.parse(value['cardId'] as String),
        principal: Money(
          currency,
          parseMinorUnits(value['principalMinor'] as String),
        ),
        fixedFee: Money(
          currency,
          parseMinorUnits(value['fixedFeeMinor'] as String),
        ),
        firstScheduledClose: BusinessDate.parse(
          value['firstScheduledClose'] as String,
        ),
        closingDay: value['closingDay'] as int,
        count: value['count'] as int,
      );
      if (encode(plan) != raw) {
        throw const FormatException('Noncanonical installment plan');
      }
      return plan;
    } catch (_) {
      throw const FormatException('Invalid installment plan');
    }
  }
}
