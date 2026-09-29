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
    required this.firstClose,
    required this.count,
  }) {
    if (count < 2 ||
        count > 120 ||
        principal.minorUnits < BigInt.from(count) ||
        fixedFee.minorUnits < BigInt.zero ||
        principal.currency != fixedFee.currency ||
        principal.minorUnits + fixedFee.minorUnits > Money.maxMinorUnits) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
    // Reject dates that cannot accommodate the whole schedule.
    if (firstClose.year * 12 + firstClose.month - 1 + count - 1 >
        9999 * 12 + 11) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
  }

  final PublicId purchaseEventId;
  final WorkspaceId workspace;
  final PublicId cardId;
  final Money principal;
  final Money fixedFee;
  final BusinessDate firstClose;
  final int count;

  /// The final installment receives any integer-minor-unit remainder.
  List<CardInstallment> get installments {
    final weights = List<BigInt>.filled(count, BigInt.one);
    final principals = principal.allocate(weights);
    final fees = fixedFee.allocate(weights);
    return List.unmodifiable(
      List.generate(count, (index) {
        final month = DateTime.utc(
          firstClose.year,
          firstClose.month + index,
          1,
        );
        final lastDay = DateTime.utc(month.year, month.month + 1, 0).day;
        return CardInstallment(
          number: index + 1,
          closesOn: BusinessDate(
            month.year,
            month.month,
            firstClose.day <= lastDay ? firstClose.day : lastDay,
          ),
          principal: principals[index],
          fee: fees[index],
        );
      }),
    );
  }
}

final class CardInstallment {
  const CardInstallment({
    required this.number,
    required this.closesOn,
    required this.principal,
    required this.fee,
  });

  final int number;
  final BusinessDate closesOn;
  final Money principal;
  final Money fee;
  Money get due => principal + fee;
}
