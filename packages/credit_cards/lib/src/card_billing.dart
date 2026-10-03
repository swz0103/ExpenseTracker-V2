import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';

import 'installments.dart';

enum CreditCardError {
  invalidInput,
  workspaceMismatch,
  cardMismatch,
  currencyMismatch,
  duplicateIdentity,
  alreadyPosted,
}

final class CreditCardException implements Exception {
  const CreditCardException(this.code);
  final CreditCardError code;
  @override
  String toString() => 'CreditCardException(${code.name})';
}

/// Card settings are not a Ledger balance or an issuer-specific limit engine.
final class CreditCardTerms {
  CreditCardTerms({
    required this.workspace,
    required this.cardId,
    required this.currency,
    required this.closingDay,
    required this.dueDay,
    this.limit,
    this.version = 1,
  }) {
    if (version < 1 ||
        closingDay < 1 ||
        closingDay > 31 ||
        dueDay < 1 ||
        dueDay > 31) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
    if (limit != null &&
        (limit!.currency != currency || limit!.minorUnits <= BigInt.zero)) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
  }

  final WorkspaceId workspace;
  final PublicId cardId;
  final Currency currency;
  final int closingDay;
  final int dueDay;
  final Money? limit;
  final int version;

  /// Nominal dates only. A real issuer statement may supply actual dates.
  CardCycle scheduledCycleFor(BusinessDate postedOn) {
    var close = _day(postedOn.year, postedOn.month, closingDay);
    if (postedOn.compareTo(close) > 0) {
      final next = _month(postedOn.year, postedOn.month, 1);
      close = _day(next.$1, next.$2, closingDay);
    }
    final previous = _month(close.year, close.month, -1);
    // Due on the first [dueDay] after the close: the same month when the
    // due day comes later in it, otherwise the next (health check G2-08).
    var due = _day(close.year, close.month, dueDay);
    if (due.compareTo(close) <= 0) {
      final following = _month(close.year, close.month, 1);
      due = _day(following.$1, following.$2, dueDay);
    }
    return CardCycle(
      startsAfter: _day(previous.$1, previous.$2, closingDay),
      closesOn: close,
      dueOn: due,
    );
  }
}

/// Portable, strict representation of one saved card-settings revision.
/// The database owns the operation ID and UTC audit timestamp separately.
final class CreditCardTermsCodec {
  const CreditCardTermsCodec();

  String encode(CreditCardTerms terms) => jsonEncode({
    'format': 1,
    'workspace': terms.workspace.id.value,
    'cardId': terms.cardId.value,
    'version': terms.version,
    'currency': terms.currency.code,
    'scale': terms.currency.scale,
    'closingDay': terms.closingDay,
    'dueDay': terms.dueDay,
    'limitMinor': terms.limit?.minorUnits.toString(),
  });

  CreditCardTerms decode(String encoded) {
    final Object? value = jsonDecode(encoded);
    if (value is! Map<String, dynamic> ||
        value.length != 9 ||
        !const {
          'format',
          'workspace',
          'cardId',
          'version',
          'currency',
          'scale',
          'closingDay',
          'dueDay',
          'limitMinor',
        }.every(value.containsKey) ||
        value['format'] != 1 ||
        value['workspace'] is! String ||
        value['cardId'] is! String ||
        value['version'] is! int ||
        value['currency'] is! String ||
        value['scale'] is! int ||
        value['closingDay'] is! int ||
        value['dueDay'] is! int ||
        (value['limitMinor'] != null && value['limitMinor'] is! String)) {
      throw const FormatException('Invalid card settings');
    }
    final currency = Currency(
      value['currency'] as String,
      value['scale'] as int,
    );
    final limit = value['limitMinor'] == null
        ? null
        : Money(currency, parseMinorUnits(value['limitMinor'] as String));
    final CreditCardTerms terms;
    try {
      terms = CreditCardTerms(
        workspace: WorkspaceId.parse(value['workspace'] as String),
        cardId: PublicId.parse(value['cardId'] as String),
        currency: currency,
        closingDay: value['closingDay'] as int,
        dueDay: value['dueDay'] as int,
        limit: limit,
        version: value['version'] as int,
      );
    } on CreditCardException {
      // One error type for every stored-settings problem.
      throw const FormatException('Invalid card settings');
    }
    if (encode(terms) != encoded) {
      throw const FormatException('Non-canonical card settings');
    }
    return terms;
  }
}

/// Explicit actual dates can replace nominal issuer dates for one statement.
final class CardCycle {
  CardCycle({
    required this.startsAfter,
    required this.closesOn,
    required this.dueOn,
  }) {
    if (startsAfter.compareTo(closesOn) >= 0 ||
        closesOn.compareTo(dueOn) >= 0) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
  }

  final BusinessDate startsAfter;
  final BusinessDate closesOn;
  final BusinessDate dueOn;

  bool includes(BusinessDate postedOn) =>
      postedOn.compareTo(startsAfter) > 0 && postedOn.compareTo(closesOn) <= 0;
}

enum CardChargeKind { purchase, refund }

/// Pending is only an authorization; only a posted charge has a Ledger event.
final class CardCharge {
  CardCharge._({
    required this.id,
    required this.workspace,
    required this.cardId,
    required this.kind,
    required this.authorizedOn,
    required this.authorizedAmount,
    this.originalChargeId,
    this.postedOn,
    this.settledAmount,
    this.fee,
    this.ledgerEventId,
  });

  factory CardCharge.pending({
    required PublicId id,
    required WorkspaceId workspace,
    required PublicId cardId,
    required CardChargeKind kind,
    required BusinessDate authorizedOn,
    required Money authorizedAmount,
    PublicId? originalChargeId,
  }) {
    if (authorizedAmount.minorUnits <= BigInt.zero ||
        (kind == CardChargeKind.refund) != (originalChargeId != null) ||
        originalChargeId == id) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
    return CardCharge._(
      id: id,
      workspace: workspace,
      cardId: cardId,
      kind: kind,
      authorizedOn: authorizedOn,
      authorizedAmount: authorizedAmount,
      originalChargeId: originalChargeId,
    );
  }

  final PublicId id;
  final WorkspaceId workspace;
  final PublicId cardId;
  final CardChargeKind kind;
  final BusinessDate authorizedOn;
  final Money authorizedAmount;
  final PublicId? originalChargeId;
  final BusinessDate? postedOn;
  final Money? settledAmount;
  final Money? fee;
  final PublicId? ledgerEventId;
  bool get isPosted => ledgerEventId != null;

  /// A posting is a separate confirmed fact: its date and currency may differ
  /// from the authorization. It replaces the pending estimate, never adds a
  /// second purchase. The application must commit the Ledger event atomically
  /// and retain its identity for retries.
  CardCharge post({
    required BusinessDate postedOn,
    required Money settledAmount,
    required Money fee,
    required PublicId ledgerEventId,
  }) {
    if (settledAmount.minorUnits <= BigInt.zero ||
        fee.minorUnits < BigInt.zero ||
        settledAmount.currency != fee.currency) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
    if (isPosted) {
      if (this.postedOn == postedOn &&
          this.settledAmount == settledAmount &&
          this.fee == fee &&
          this.ledgerEventId == ledgerEventId) {
        return this;
      }
      throw const CreditCardException(CreditCardError.alreadyPosted);
    }
    return CardCharge._(
      id: id,
      workspace: workspace,
      cardId: cardId,
      kind: kind,
      authorizedOn: authorizedOn,
      authorizedAmount: authorizedAmount,
      originalChargeId: originalChargeId,
      postedOn: postedOn,
      settledAmount: settledAmount,
      fee: fee,
      ledgerEventId: ledgerEventId,
    );
  }
}

/// The application links this to a committed Ledger transfer, never expense.
final class CardPayment {
  CardPayment({
    required this.id,
    required this.workspace,
    required this.cardId,
    required this.statementClose,
    required this.postedOn,
    required this.amount,
    required this.ledgerEventId,
  }) {
    if (amount.minorUnits <= BigInt.zero) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
  }
  final PublicId id;
  final WorkspaceId workspace;
  final PublicId cardId;
  final BusinessDate statementClose;
  final BusinessDate postedOn;
  final Money amount;
  final PublicId ledgerEventId;
}

/// Read model only. Spending belongs to the original posted Ledger purchase;
/// statement due and payment must never be reported as new spending.
final class CardStatement {
  CardStatement._({
    required this.cycle,
    required this.carriedOver,
    required this.purchases,
    required this.installmentsDue,
    required this.refunds,
    required this.fees,
    required this.payments,
    required this.remainingDue,
    required this.credit,
    required this.pendingCount,
  });

  factory CardStatement.calculate({
    required CreditCardTerms terms,
    required CardCycle cycle,
    required Iterable<CardCharge> charges,
    required Iterable<CardPayment> payments,
    Iterable<CardInstallmentSchedule> plans = const [],
  }) {
    // A purchase paid in installments is billed one installment per
    // statement, not in full (feature audit G-01).
    final planned = {for (final plan in plans) plan.purchaseEventId: plan};
    var installmentsDue = Money(terms.currency, BigInt.zero);
    var purchases = Money(terms.currency, BigInt.zero);
    var refunds = Money(terms.currency, BigInt.zero);
    var fees = Money(terms.currency, BigInt.zero);
    var paid = Money(terms.currency, BigInt.zero);
    // What earlier statements left unpaid, or overpaid when negative
    // (health check G2-12).
    var carried = Money(terms.currency, BigInt.zero);
    var pendingCount = 0;
    final ids = <PublicId>{};
    final events = <PublicId>{};
    final allCharges = charges.toList();
    final chargesById = <PublicId, CardCharge>{};
    final refundedByPurchase = <PublicId, BigInt>{};
    for (final charge in allCharges) {
      _checkOwner(terms, charge.workspace, charge.cardId);
      if (!ids.add(charge.id)) {
        throw const CreditCardException(CreditCardError.duplicateIdentity);
      }
      chargesById[charge.id] = charge;
    }
    for (final charge in allCharges) {
      if (charge.kind == CardChargeKind.refund &&
          (chargesById[charge.originalChargeId]?.kind !=
                  CardChargeKind.purchase ||
              chargesById[charge.originalChargeId]?.isPosted != true)) {
        throw const CreditCardException(CreditCardError.invalidInput);
      }
      if (charge.kind == CardChargeKind.refund && charge.isPosted) {
        final original = chargesById[charge.originalChargeId]!;
        if (charge.postedOn!.compareTo(original.postedOn!) < 0) {
          throw const CreditCardException(CreditCardError.invalidInput);
        }
        final refunded =
            (refundedByPurchase[original.id] ?? BigInt.zero) +
            charge.settledAmount!.minorUnits;
        if (refunded > original.settledAmount!.minorUnits) {
          throw const CreditCardException(CreditCardError.invalidInput);
        }
        refundedByPurchase[original.id] = refunded;
      }
      if (!charge.isPosted) {
        if (cycle.includes(charge.authorizedOn)) pendingCount++;
        continue;
      }
      if (charge.settledAmount!.currency != terms.currency ||
          charge.fee!.currency != terms.currency) {
        throw const CreditCardException(CreditCardError.currencyMismatch);
      }
      if (!events.add(charge.ledgerEventId!)) {
        throw const CreditCardException(CreditCardError.duplicateIdentity);
      }
      final plan = charge.kind == CardChargeKind.purchase
          ? planned[charge.ledgerEventId]
          : null;
      if (plan != null) {
        if (plan.cardId != terms.cardId ||
            plan.principal != charge.settledAmount) {
          throw const CreditCardException(CreditCardError.invalidInput);
        }
        for (final part in plan.installments) {
          final charged = part.principal + part.fee;
          if (part.scheduledClose == cycle.closesOn) {
            installmentsDue += charged;
          } else if (part.scheduledClose.compareTo(cycle.startsAfter) <= 0) {
            carried += charged;
          }
        }
      }
      if (charge.postedOn!.compareTo(cycle.startsAfter) <= 0) {
        if (plan == null) {
          carried += charge.kind == CardChargeKind.purchase
              ? charge.settledAmount!
              : -charge.settledAmount!;
        }
        carried += charge.fee!;
        continue;
      }
      if (!cycle.includes(charge.postedOn!)) continue;
      if (charge.kind == CardChargeKind.purchase) {
        // A planned purchase is billed through installmentsDue above.
        if (plan == null) purchases += charge.settledAmount!;
      } else {
        refunds += charge.settledAmount!;
      }
      fees += charge.fee!;
    }
    for (final payment in payments) {
      _checkOwner(terms, payment.workspace, payment.cardId);
      if (!ids.add(payment.id) || !events.add(payment.ledgerEventId)) {
        throw const CreditCardException(CreditCardError.duplicateIdentity);
      }
      if (payment.amount.currency != terms.currency) {
        throw const CreditCardException(CreditCardError.currencyMismatch);
      }
      if (payment.statementClose == cycle.closesOn) {
        paid += payment.amount;
      } else if (payment.statementClose.compareTo(cycle.startsAfter) <= 0) {
        carried -= payment.amount;
      }
    }
    final net = carried + purchases + installmentsDue - refunds + fees - paid;
    return CardStatement._(
      cycle: cycle,
      carriedOver: carried,
      installmentsDue: installmentsDue,
      purchases: purchases,
      refunds: refunds,
      fees: fees,
      payments: paid,
      remainingDue: net.minorUnits.isNegative
          ? Money(terms.currency, BigInt.zero)
          : net,
      credit: net.minorUnits.isNegative
          ? -net
          : Money(terms.currency, BigInt.zero),
      pendingCount: pendingCount,
    );
  }

  final CardCycle cycle;

  /// Unpaid balance from earlier statements; negative for a credit.
  final Money carriedOver;
  final Money purchases;

  /// The installments of planned purchases that fall in this statement,
  /// fees included.
  final Money installmentsDue;
  final Money refunds;
  final Money fees;
  final Money payments;
  final Money remainingDue;
  final Money credit;
  final int pendingCount;
}

void _checkOwner(
  CreditCardTerms terms,
  WorkspaceId workspace,
  PublicId cardId,
) {
  if (workspace != terms.workspace) {
    throw const CreditCardException(CreditCardError.workspaceMismatch);
  }
  if (cardId != terms.cardId) {
    throw const CreditCardException(CreditCardError.cardMismatch);
  }
}

(int, int) _month(int year, int month, int offset) {
  final result = DateTime.utc(year, month + offset, 1);
  if (result.year < 1 || result.year > 9999) {
    throw const CreditCardException(CreditCardError.invalidInput);
  }
  return (result.year, result.month);
}

BusinessDate _day(int year, int month, int requested) {
  final last = DateTime.utc(year, month + 1, 0).day;
  return BusinessDate(year, month, requested > last ? last : requested);
}
