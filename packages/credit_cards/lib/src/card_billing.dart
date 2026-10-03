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

/// Billing days that applied until a change took effect.
final class CardScheduleChange {
  CardScheduleChange({
    required this.until,
    required this.closingDay,
    required this.dueDay,
  }) {
    _checkDays(closingDay, dueDay);
  }

  /// The first close on the newer days; these days applied before it.
  final BusinessDate until;
  final int closingDay;
  final int dueDay;
}

/// The issuer's actual dates for one statement, when they differ from the
/// schedule (feature audit G-08).
final class CardCycleOverride {
  CardCycleOverride({
    required this.scheduledClose,
    required this.closesOn,
    required this.dueOn,
  }) {
    final shift = _utc(closesOn).difference(_utc(scheduledClose)).inDays.abs();
    if (shift > 7 || closesOn.compareTo(dueOn) >= 0) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
  }

  final BusinessDate scheduledClose;
  final BusinessDate closesOn;
  final BusinessDate dueOn;
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
    List<CardScheduleChange> history = const [],
    List<CardCycleOverride> overrides = const [],
  }) : history = List.unmodifiable(history),
       overrides = List.unmodifiable(overrides) {
    if (version < 1) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
    _checkDays(closingDay, dueDay);
    if (limit != null &&
        (limit!.currency != currency || limit!.minorUnits <= BigInt.zero)) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
    for (final (i, change) in this.history.indexed) {
      final until = change.until;
      // A change takes effect on a close of the newer closing day.
      final newer = i + 1 < this.history.length
          ? this.history[i + 1].closingDay
          : closingDay;
      final earlier = i == 0 ? null : this.history[i - 1].until;
      if (until != _day(until.year, until.month, newer) ||
          (earlier != null && until.compareTo(earlier) <= 0)) {
        throw const CreditCardException(CreditCardError.invalidInput);
      }
    }
    final scheduled = <BusinessDate>{};
    for (final override in this.overrides) {
      if (!scheduled.add(override.scheduledClose) ||
          _nominalClose(override.scheduledClose) != override.scheduledClose) {
        throw const CreditCardException(CreditCardError.invalidInput);
      }
    }
  }

  final WorkspaceId workspace;
  final PublicId cardId;
  final Currency currency;

  /// The billing days in effect now, since the last [history] change.
  final int closingDay;
  final int dueDay;
  final Money? limit;
  final int version;

  /// Earlier billing days, oldest first, so past statements keep their
  /// dates after a change (feature audit G-08).
  final List<CardScheduleChange> history;
  final List<CardCycleOverride> overrides;

  /// New billing days from the close on [from] onward, or for the whole
  /// card when [from] is null. Earlier statements keep their dates.
  CreditCardTerms reschedule({
    required int closingDay,
    required int dueDay,
    BusinessDate? from,
    Money? limit,
  }) {
    final keep =
        from == null ||
        (this.closingDay == closingDay && this.dueDay == dueDay);
    return CreditCardTerms(
      workspace: workspace,
      cardId: cardId,
      currency: currency,
      closingDay: closingDay,
      dueDay: dueDay,
      limit: limit,
      version: version + 1,
      history: keep
          ? history
          : [
              ...history,
              CardScheduleChange(
                until: from,
                closingDay: this.closingDay,
                dueDay: this.dueDay,
              ),
            ],
      overrides: overrides,
    );
  }

  /// Records the issuer's actual dates for the statement scheduled to close
  /// on [scheduledClose]; null dates go back to the schedule.
  CreditCardTerms overrideCycle({
    required BusinessDate scheduledClose,
    BusinessDate? closesOn,
    BusinessDate? dueOn,
  }) {
    if ((closesOn == null) != (dueOn == null)) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
    return CreditCardTerms(
      workspace: workspace,
      cardId: cardId,
      currency: currency,
      closingDay: closingDay,
      dueDay: dueDay,
      limit: limit,
      version: version + 1,
      history: history,
      overrides: [
        for (final override in overrides)
          if (override.scheduledClose != scheduledClose) override,
        if (closesOn != null)
          CardCycleOverride(
            scheduledClose: scheduledClose,
            closesOn: closesOn,
            dueOn: dueOn!,
          ),
      ],
    );
  }

  /// The statement cycle containing [date], with the billing days in
  /// effect then and any actual dates the issuer used.
  CardCycle cycleFor(BusinessDate date) {
    final closes = _closesAround(date);
    final actual = [for (final close in closes) _actual(close)];
    for (var i = 1; i < closes.length; i++) {
      if (date.compareTo(actual[i].$1) <= 0) {
        return CardCycle(
          startsAfter: actual[i - 1].$1,
          closesOn: actual[i].$1,
          dueOn: actual[i].$2,
          scheduledStartsAfter: closes[i - 1],
          scheduledClose: closes[i],
        );
      }
    }
    throw const CreditCardException(CreditCardError.invalidInput);
  }

  (BusinessDate, BusinessDate) _actual(BusinessDate close) {
    for (final override in overrides) {
      if (override.scheduledClose == close) {
        return (override.closesOn, override.dueOn);
      }
    }
    // Due on the first due day after the close: the same month when the
    // due day comes later in it, otherwise the next (health check G2-08).
    final (_, dueDay) = _daysOn(close);
    var due = _day(close.year, close.month, dueDay);
    if (due.compareTo(close) <= 0) {
      final following = _month(close.year, close.month, 1);
      due = _day(following.$1, following.$2, dueDay);
    }
    return (close, due);
  }

  /// Scheduled closes from three months before [date] to three after.
  List<BusinessDate> _closesAround(BusinessDate date) {
    final closes = <BusinessDate>[];
    for (var offset = -3; offset <= 3; offset++) {
      final (year, month) = _month(date.year, date.month, offset);
      final days = {...history.map((h) => h.closingDay), closingDay};
      final found = <BusinessDate>{
        for (final day in days)
          if (_daysOn(_day(year, month, day)).$1 == day) _day(year, month, day),
      };
      closes.addAll(found.toList()..sort());
    }
    return closes;
  }

  /// The closing day in effect on [date].
  int closingDayOn(BusinessDate date) => _daysOn(date).$1;

  BusinessDate _nominalClose(BusinessDate date) {
    final (closing, _) = _daysOn(date);
    return _day(date.year, date.month, closing);
  }

  (int, int) _daysOn(BusinessDate date) {
    for (final change in history) {
      if (date.compareTo(change.until) < 0) {
        return (change.closingDay, change.dueDay);
      }
    }
    return (closingDay, dueDay);
  }
}

void _checkDays(int closingDay, int dueDay) {
  if (closingDay < 1 || closingDay > 31 || dueDay < 1 || dueDay > 31) {
    throw const CreditCardException(CreditCardError.invalidInput);
  }
}

DateTime _utc(BusinessDate date) =>
    DateTime.utc(date.year, date.month, date.day);

/// Portable, strict representation of one saved card-settings revision.
/// The database owns the operation ID and UTC audit timestamp separately.
final class CreditCardTermsCodec {
  const CreditCardTermsCodec();

  static const _keys = {
    'format',
    'workspace',
    'cardId',
    'version',
    'currency',
    'scale',
    'closingDay',
    'dueDay',
    'limitMinor',
    'history',
    'overrides',
  };

  String encode(CreditCardTerms terms) => jsonEncode({
    'format': 2,
    'workspace': terms.workspace.id.value,
    'cardId': terms.cardId.value,
    'version': terms.version,
    'currency': terms.currency.code,
    'scale': terms.currency.scale,
    'closingDay': terms.closingDay,
    'dueDay': terms.dueDay,
    'limitMinor': terms.limit?.minorUnits.toString(),
    'history': [
      for (final change in terms.history)
        {
          'until': '${change.until}',
          'closingDay': change.closingDay,
          'dueDay': change.dueDay,
        },
    ],
    'overrides': [
      for (final override in terms.overrides)
        {
          'scheduledClose': '${override.scheduledClose}',
          'closesOn': '${override.closesOn}',
          'dueOn': '${override.dueOn}',
        },
    ],
  });

  CreditCardTerms decode(String encoded) {
    try {
      return _decode(encoded);
    } on CreditCardException {
      // One error type for every stored-settings problem.
      throw const FormatException('Invalid card settings');
    } on TypeError {
      throw const FormatException('Invalid card settings');
    }
  }

  CreditCardTerms _decode(String encoded) {
    final Object? value = jsonDecode(encoded);
    if (value is! Map<String, dynamic> ||
        value.length != _keys.length ||
        !_keys.every(value.containsKey) ||
        value['format'] != 2 ||
        value['workspace'] is! String ||
        value['cardId'] is! String ||
        value['version'] is! int ||
        value['currency'] is! String ||
        value['scale'] is! int ||
        value['closingDay'] is! int ||
        value['dueDay'] is! int ||
        (value['limitMinor'] != null && value['limitMinor'] is! String) ||
        value['history'] is! List ||
        value['overrides'] is! List) {
      throw const FormatException('Invalid card settings');
    }
    final currency = Currency(
      value['currency'] as String,
      value['scale'] as int,
    );
    final limit = value['limitMinor'] == null
        ? null
        : Money(currency, parseMinorUnits(value['limitMinor'] as String));
    final terms = CreditCardTerms(
      workspace: WorkspaceId.parse(value['workspace'] as String),
      cardId: PublicId.parse(value['cardId'] as String),
      currency: currency,
      closingDay: value['closingDay'] as int,
      dueDay: value['dueDay'] as int,
      limit: limit,
      version: value['version'] as int,
      history: [
        for (final item in value['history'] as List)
          CardScheduleChange(
            until: BusinessDate.parse((item as Map)['until'] as String),
            closingDay: item['closingDay'] as int,
            dueDay: item['dueDay'] as int,
          ),
      ],
      overrides: [
        for (final item in value['overrides'] as List)
          CardCycleOverride(
            scheduledClose: BusinessDate.parse(
              (item as Map)['scheduledClose'] as String,
            ),
            closesOn: BusinessDate.parse(item['closesOn'] as String),
            dueOn: BusinessDate.parse(item['dueOn'] as String),
          ),
      ],
    );
    if (encode(terms) != encoded) {
      throw const FormatException('Non-canonical card settings');
    }
    return terms;
  }
}

/// One statement period. The scheduled dates are the nominal ones the
/// card's billing days give; installments are billed by them.
final class CardCycle {
  CardCycle({
    required this.startsAfter,
    required this.closesOn,
    required this.dueOn,
    BusinessDate? scheduledStartsAfter,
    BusinessDate? scheduledClose,
  }) : scheduledStartsAfter = scheduledStartsAfter ?? startsAfter,
       scheduledClose = scheduledClose ?? closesOn {
    if (startsAfter.compareTo(closesOn) >= 0 ||
        closesOn.compareTo(dueOn) >= 0 ||
        this.scheduledStartsAfter.compareTo(this.scheduledClose) >= 0) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
  }

  final BusinessDate startsAfter;
  final BusinessDate closesOn;
  final BusinessDate dueOn;
  final BusinessDate scheduledStartsAfter;
  final BusinessDate scheduledClose;

  bool includes(BusinessDate postedOn) =>
      postedOn.compareTo(startsAfter) > 0 && postedOn.compareTo(closesOn) <= 0;

  /// Whether an installment scheduled to close on [close] is billed here.
  bool bills(BusinessDate close) =>
      close.compareTo(scheduledStartsAfter) > 0 &&
      close.compareTo(scheduledClose) <= 0;
}

enum CardChargeKind {
  purchase,
  refund,

  /// Charged by the issuer itself: an annual fee, late fee or interest.
  fee,

  /// Credited by the issuer itself: cashback or a waived fee (G6-12).
  credit,
}

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
    this.foreignAmount,
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

  /// What the merchant charged in its own currency, for a foreign charge
  /// (feature audit G-09).
  final Money? foreignAmount;
  bool get isPosted => ledgerEventId != null;

  /// True when it adds to what is owed: a purchase or an issuer fee.
  bool get raisesBalance =>
      kind == CardChargeKind.purchase || kind == CardChargeKind.fee;

  /// A posting is a separate confirmed fact: its date and currency may differ
  /// from the authorization. It replaces the pending estimate, never adds a
  /// second purchase. The application must commit the Ledger event atomically
  /// and retain its identity for retries.
  ///
  /// [foreignAmount] defaults to a foreign-currency authorization.
  CardCharge post({
    required BusinessDate postedOn,
    required Money settledAmount,
    required Money fee,
    required PublicId ledgerEventId,
    Money? foreignAmount,
  }) {
    final local = settledAmount.currency.code;
    final sameCurrency = authorizedAmount.currency.code == local;
    final foreign = foreignAmount ?? (sameCurrency ? null : authorizedAmount);
    if (settledAmount.minorUnits <= BigInt.zero ||
        fee.minorUnits < BigInt.zero ||
        settledAmount.currency != fee.currency) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
    if (foreign != null &&
        (foreign.minorUnits.sign < 1 || foreign.currency.code == local)) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
    if (isPosted) {
      if (this.postedOn == postedOn &&
          this.settledAmount == settledAmount &&
          this.fee == fee &&
          this.ledgerEventId == ledgerEventId &&
          this.foreignAmount == foreign) {
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
      foreignAmount: foreign,
    );
  }
}

/// The issuer's foreign transaction fee on [settled], 1.5% by default,
/// rounded half up to the card currency (feature audit G-09). A
/// suggestion: the statement's own figure wins.
Money foreignTransactionFee(Money settled, {int basisPoints = 150}) {
  if (basisPoints < 0 || basisPoints > 10000 || settled.minorUnits.isNegative) {
    throw const CreditCardException(CreditCardError.invalidInput);
  }
  return Money.quantizeRatio(
    settled.currency,
    settled.minorUnits * BigInt.from(basisPoints),
    BigInt.from(10000) * BigInt.from(10).pow(settled.currency.scale),
  );
}

/// How much more of [purchase] the card can credit back, given the
/// refunds already posted against it. A foreign purchase is limited in
/// its own currency and may come back with its fee, since the exchange
/// rate moves; a local one only up to the amount charged (G-09).
({Money local, Money? foreign}) refundableOf(
  CardCharge purchase,
  Iterable<CardCharge> refunds,
) {
  if (purchase.kind != CardChargeKind.purchase || !purchase.isPosted) {
    throw const CreditCardException(CreditCardError.invalidInput);
  }
  final foreign = purchase.foreignAmount;
  var local = foreign == null
      ? purchase.settledAmount!
      : purchase.settledAmount! + purchase.fee!;
  var abroad = foreign;
  for (final refund in refunds) {
    if (refund.originalChargeId != purchase.id || !refund.isPosted) continue;
    local -= refund.settledAmount!;
    if (abroad != null) {
      final back = refund.foreignAmount;
      if (back == null || back.currency != abroad.currency) {
        throw const CreditCardException(CreditCardError.currencyMismatch);
      }
      abroad -= back;
    }
  }
  return (local: local, foreign: abroad);
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
    required this.credits,
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
    var credits = Money(terms.currency, BigInt.zero);
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
    final refunded = <CardCharge>{};
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
        refunded.add(original);
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
          final close = part.scheduledClose;
          if (cycle.bills(close)) {
            installmentsDue += charged;
          } else if (close.compareTo(cycle.scheduledStartsAfter) <= 0) {
            carried += charged;
          }
        }
      }
      if (charge.postedOn!.compareTo(cycle.startsAfter) <= 0) {
        if (plan == null) {
          carried += charge.raisesBalance
              ? charge.settledAmount!
              : -charge.settledAmount!;
        }
        carried += charge.fee!;
        continue;
      }
      if (!cycle.includes(charge.postedOn!)) continue;
      switch (charge.kind) {
        case CardChargeKind.purchase:
          // A planned purchase is billed through installmentsDue above.
          if (plan == null) purchases += charge.settledAmount!;
        case CardChargeKind.refund:
          refunds += charge.settledAmount!;
        case CardChargeKind.fee:
          fees += charge.settledAmount!;
        case CardChargeKind.credit:
          credits += charge.settledAmount!;
      }
      fees += charge.fee!;
    }
    for (final purchase in refunded) {
      final left = refundableOf(purchase, allCharges);
      if (left.local.minorUnits.isNegative ||
          (left.foreign?.minorUnits.isNegative ?? false)) {
        throw const CreditCardException(CreditCardError.invalidInput);
      }
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
    final net =
        carried + purchases + installmentsDue - refunds - credits + fees - paid;
    return CardStatement._(
      cycle: cycle,
      carriedOver: carried,
      installmentsDue: installmentsDue,
      purchases: purchases,
      refunds: refunds,
      credits: credits,
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

  /// Cashback and waived fees credited by the issuer.
  final Money credits;
  final Money fees;
  final Money payments;
  final Money remainingDue;
  final Money credit;
  final int pendingCount;

  /// What must still be paid by the due date to avoid a late fee: the
  /// installments and fees billed now plus [percent] of everything else
  /// owed, rounded up, at least [floor], less what was already paid
  /// (feature audit G-10). Issuers differ, so the rule's numbers are
  /// passed in.
  Money minimumDue({int percent = 10, Money? floor}) {
    final currency = remainingDue.currency;
    if (percent < 0 || percent > 100) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
    if (floor != null && floor.currency != currency) {
      throw const CreditCardException(CreditCardError.currencyMismatch);
    }
    final owed =
        carriedOver.minorUnits +
        purchases.minorUnits +
        installmentsDue.minorUnits -
        refunds.minorUnits -
        credits.minorUnits +
        fees.minorUnits;
    if (owed <= BigInt.zero) return Money(currency, BigInt.zero);
    final fixed = installmentsDue.minorUnits + fees.minorUnits;
    final rest = owed > fixed ? owed - fixed : BigInt.zero;
    final hundred = BigInt.from(100);
    var minimum =
        fixed + (rest * BigInt.from(percent) + hundred - BigInt.one) ~/ hundred;
    if (floor != null && minimum < floor.minorUnits) minimum = floor.minorUnits;
    if (minimum > owed) minimum = owed;
    final left = minimum - payments.minorUnits;
    return Money(currency, left.isNegative ? BigInt.zero : left);
  }
}

/// The day a payment is really due: [dueOn], or the next banking day when
/// it falls on a weekend or holiday (feature audit G-10).
BusinessDate paymentDueOn(BusinessDate dueOn, BankingCalendar calendar) =>
    calendar.onOrAfter(dueOn);

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

/// The posted lines behind one statement, for the statement detail view.
/// A purchase paid in installments is listed through its installments.
final class CardStatementItems {
  const CardStatementItems({
    required this.charges,
    required this.installments,
    required this.payments,
  });

  factory CardStatementItems.select({
    required CardCycle cycle,
    required Iterable<CardCharge> charges,
    required Iterable<CardPayment> payments,
    Iterable<CardInstallmentSchedule> plans = const [],
  }) {
    final planned = {for (final plan in plans) plan.purchaseEventId};
    final posted = [
      for (final charge in charges)
        if (charge.isPosted &&
            cycle.includes(charge.postedOn!) &&
            !(charge.kind == CardChargeKind.purchase &&
                planned.contains(charge.ledgerEventId)))
          charge,
    ]..sort((a, b) => a.postedOn!.compareTo(b.postedOn!));
    return CardStatementItems(
      charges: posted,
      installments: [
        for (final plan in plans)
          for (final part in plan.installments)
            if (cycle.bills(part.scheduledClose)) part,
      ],
      payments: [
        for (final payment in payments)
          if (payment.statementClose == cycle.closesOn) payment,
      ]..sort((a, b) => a.postedOn.compareTo(b.postedOn)),
    );
  }

  final List<CardCharge> charges;
  final List<CardInstallment> installments;
  final List<CardPayment> payments;
}

/// What can still be charged to the card: the limit less posted charges
/// and fees, less pending purchase authorizations, plus refunds and
/// payments. Null when the card has no limit. An authorization in another
/// currency is not counted until it posts; an overpayment can leave more
/// than the limit.
Money? remainingCredit({
  required CreditCardTerms terms,
  required Iterable<CardCharge> charges,
  required Iterable<CardPayment> payments,
}) {
  final limit = terms.limit;
  if (limit == null) return null;
  var used = BigInt.zero;
  for (final charge in charges) {
    _checkOwner(terms, charge.workspace, charge.cardId);
    if (charge.isPosted) {
      if (charge.settledAmount!.currency != terms.currency) {
        throw const CreditCardException(CreditCardError.currencyMismatch);
      }
      used += charge.raisesBalance
          ? charge.settledAmount!.minorUnits
          : -charge.settledAmount!.minorUnits;
      used += charge.fee!.minorUnits;
    } else if (charge.kind == CardChargeKind.purchase &&
        charge.authorizedAmount.currency == terms.currency) {
      used += charge.authorizedAmount.minorUnits;
    }
  }
  for (final payment in payments) {
    _checkOwner(terms, payment.workspace, payment.cardId);
    used -= payment.amount.minorUnits;
  }
  return limit - Money(terms.currency, used);
}
