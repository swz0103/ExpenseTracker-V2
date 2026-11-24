# (id, area, file, old, new)  -- old must occur exactly once in file
APP = 'apps/expense_tracker/'
SVC = APP + 'lib/src/core/ledger/services/'
T = APP + 'test/'
def flt(*files): return ('apps/expense_tracker', 'flutter test ' + ' '.join(files))
# Every read method asked with an entry dated tomorrow (D25).
ASOF = 'test/core/ledger/services/as_of_today_test.dart'
AREAS = {
 'core':    ('packages/core', 'dart test'),
 'trade':   ('packages/ledger/trade_costs', 'dart test'),
 'loans':   ('packages/ledger/loans', 'dart test'),
 'entries': ('packages/ledger/entries', 'dart test'),
 'domain':  ('packages/domain', 'dart test'),
 'balance': flt('test/core/ledger/services/balance_service_test.dart', ASOF),
 'report':  flt('test/core/ledger/services/report_service_test.dart', ASOF),
 'budget':  flt('test/core/ledger/services/budget_service_test.dart', ASOF),
 'statement': flt('test/core/ledger/services/statement_service_test.dart', ASOF),
 'recurring': flt('test/core/ledger/services/recurring_service_test.dart'),
 'cardcycle': flt('test/core/ledger/services/statement_service_test.dart','test/core/ledger/services/balance_service_test.dart','test/baseline/installments_baseline_test.dart'),
 'cardsummary': flt('test/features/accounts/model/card_summary_test.dart', ASOF),
 'amount':  flt('test/design_system/display'),
}
# wide pass: for survivors, run a much broader app test set
_wide = 'flutter test test/core/ledger test/scenarios/ledger test/scenarios/entries test/scenarios/recurring test/scenarios/accounts test/features/accounts test/features/recurring test/features/budgets test/features/reports test/baseline test/design_system'
AREAS_WIDE = dict(AREAS)
for k in ('core','trade','loans','entries','domain','balance','report','budget','statement','recurring','cardcycle','cardsummary','amount'):
    AREAS_WIDE[k] = ('apps/expense_tracker', _wide)

MUTANTS = []
_n = {}
def M(area, f, old, new):
    _n[area] = _n.get(area, 0) + 1
    MUTANTS.append((f'{area}-{_n[area]:02d}', area, f, old, new))

# ---------------- core: money ----------------
C = 'packages/core/lib/money/money.dart'
M('core',C,'scaled.remainder(denominator) * BigInt.two >= denominator','scaled.remainder(denominator) * BigInt.two > denominator')  # half-up -> half-down
M('core',C,'units += BigInt.one;\n    }\n    return Money(currency, numerator.isNegative','units += BigInt.zero;\n    }\n    return Money(currency, numerator.isNegative')
M('core',C,'numerator.isNegative ? -units : units','units')  # sign dropped
M('core',C,'final scaled = numerator.abs() * BigInt.from(10).pow(currency.scale);','final scaled = numerator.abs() * BigInt.from(10).pow(currency.scale + 1);')
M('core',C,'if (denominator <= BigInt.zero) {','if (denominator < BigInt.zero) {')
M('core',C,'if (scale > currency.scale) {','if (scale >= currency.scale) {')
M('core',C,'pow(currency.scale - scale)','pow(currency.scale + scale)')
M('core',C,'if (minorUnits < minMinorUnits || minorUnits > maxMinorUnits) {','if (minorUnits <= minMinorUnits || minorUnits > maxMinorUnits) {')
M('core',C,'if (minorUnits < minMinorUnits || minorUnits > maxMinorUnits) {','if (minorUnits < minMinorUnits || minorUnits >= maxMinorUnits) {')
M('core',C,'static final maxMinorUnits = (BigInt.one << 63) - BigInt.one;','static final maxMinorUnits = (BigInt.one << 63);')
M('core',C,'weights.any((weight) => weight <= BigInt.zero)','weights.any((weight) => weight < BigInt.zero)')
M('core',C,'return byFraction != 0 ? byFraction : a.compareTo(b);','return byFraction != 0 ? byFraction : b.compareTo(a);')
M('core',C,'fractions[b].compareTo(fractions[a])','fractions[a].compareTo(fractions[b])')
M('core',C,'final sign = minorUnits.isNegative ? -BigInt.one : BigInt.one;','final sign = BigInt.one;')
M('core',C,'weights.length > 10000','weights.length >= 10000')
M('core',C,"padLeft(currency.scale + 1, '0')","padLeft(currency.scale, '0')")
M('core',C,"final sign = minorUnits.isNegative ? '-' : '';","final sign = '';")
M('core',C,'Money operator -(Money other) {\n    _requireCurrency(other);\n    return Money(currency, minorUnits - other.minorUnits);','Money operator -(Money other) {\n    _requireCurrency(other);\n    return Money(currency, minorUnits + other.minorUnits);')
M('core',C,'!_minorUnitsPattern.hasMatch(amount)','_minorUnitsPattern.hasMatch(amount)')  # 19: retargeted, the length check moved
M('core',C,'scale < 0 || scale > 18','scale < 0 || scale > 17')
M('core',C,'numerator.bitLength > 4096','numerator.bitLength >= 4096')
M('core',C,'text.length > 128','text.length >= 128')
M('core',C,"static const _whole = {'TWD', 'JPY', 'KRW'};","static const _whole = {'TWD', 'JPY'};")
M('core',C,'BigInt.from(10).pow(scale),','BigInt.from(10).pow(scale + 1),')
M('core',C,'amount.length > 20 ||','amount.length >= 20 ||')
M('core',C,'if (json[\'version\'] != 1 ||','if (json[\'version\'] != 2 ||')
M('core',C,'sign * unit','unit')
P = 'packages/core/lib/percent/percent.dart'
M('core',P,'if ((n % d) * 2 >= d) quotient += 1;','if ((n % d) * 2 > d) quotient += 1;')
M('core',P,'final negative = (numerator < 0) != (denominator < 0);','final negative = (numerator < 0) == (denominator < 0);')
M('core',P,'divideRounded(part * 100, whole)','divideRounded(part * 10, whole)')
M('core',P,'divideRounded(part * 1000, whole)','divideRounded(part * 100, whole)')
M('core',P,'roundHalfAwayFromZero(ratio * 100, 1)','roundHalfAwayFromZero(ratio * 100, 0)')
M('core',P,'bool isOver(int part, int whole) => part > whole;','bool isOver(int part, int whole) => part >= whole;')
M('core',P,'if (denominator == 0) {','if (denominator == 1) {')
M('core',P,'int percent(int part, int whole) =>\n    whole == 0 ? 0','int percent(int part, int whole) =>\n    whole < 0 ? 0')
F = 'packages/core/lib/money/amount_format.dart'
M('core',F,"return value < 0 ? '-$grouped' : grouped;","return value <= 0 ? '-$grouped' : grouped;")
M('core',F,'(digits.length - i) % 3 == 0','(digits.length - i) % 3 == 1')
M('core',F,'if (i > 0 && (digits.length - i)','if (i >= 0 && (digits.length - i)')
M('core',F,"fraction.codeUnitAt(decimals) >= '5'.codeUnitAt(0)","fraction.codeUnitAt(decimals) > '5'.codeUnitAt(0)")
M('core',F,'return value < 0 ? -scaled.toInt() : scaled.toInt();','return scaled.toInt();')
M('core',F,"padLeft(scale + 1, '0')","padLeft(scale, '0')")
M('core',F,"return text == '-0' ? '0' : text;","return text;")
M('core',F,"? text.substring(1)\n      : text;","? text\n      : text;") if False else None
M('core',F,"return RegExp(r'^-[0.,]+$').hasMatch(text) ? text.substring(1) : text;","return text;")
M('core',F,'for (var i = 0; i < exponent; i++) {','for (var i = 0; i <= exponent; i++) {')
M('core',F,'(sign: value.sign, size: value.abs())','(sign: -value.sign, size: value.abs())')
M('core',F,'final scaled = (value.abs() * _pow10(decimals)).round();','final scaled = (value.abs() * _pow10(decimals)).floor();')
M('core',F,'final sign = minor < 0 ? \'-\' : \'\';','final sign = minor <= 0 ? \'-\' : \'\';')
R = 'packages/core/lib/money/price.dart'
M('core',R,'const priceScale = 10000;','const priceScale = 1000;')
M('core',R,'(price * priceScale).round()','(price * priceScale).floor()')
S = 'packages/core/lib/money/amount_sum.dart'
M('core',S,'if (scaled.remainder(denominator) * BigInt.two >= denominator) {','if (scaled.remainder(denominator) * BigInt.two > denominator) {')
M('core',S,'return numerator.isNegative ? -units : units;','return units;')
M('core',S,'numerator * o.denominator - o.numerator * denominator,','numerator * o.denominator + o.numerator * denominator,')
M('core',S,'n = -n;','n = n;')
M('core',S,'return gcd <= BigInt.one','return gcd < BigInt.one')

# ---------------- trade costs ----------------
CH = 'packages/ledger/trade_costs/lib/calc/charges.dart'
M('trade',CH,'const fullFeePerMillion = 1425;','const fullFeePerMillion = 1424;')
M('trade',CH,'BigInt.from(_million * BrokerDiscountRange.highest)','BigInt.from(_million ~/ 10 * BrokerDiscountRange.highest)')
M('trade',CH,'oddLot ? oddLotMinimumFee : minimumFee','oddLot ? minimumFee : oddLotMinimumFee')
M('trade',CH,'quantity.coefficient < BigInt.from(1000)','quantity.coefficient <= BigInt.from(1000)')
M('trade',CH,'if (gross.minorUnits == BigInt.zero) return gross;','if (gross.minorUnits == BigInt.one) return gross;')
M('trade',CH,'int minimumFee = 20,','int minimumFee = 21,')
M('trade',CH,'int oddLotMinimumFee = 1,','int oddLotMinimumFee = 2,')
M('trade',CH,'minimumFee < 0 ||','minimumFee <= 0 ||')
M('trade',CH,'oddLotMinimumFee < 0) {','oddLotMinimumFee <= 0) {')
M('trade',CH,'dayTrade ? rates.dayTradeTax : rates.stockTax','dayTrade ? rates.stockTax : rates.dayTradeTax')
M('trade',CH,'InstrumentKind.etf => rates.etfTax,','InstrumentKind.etf => rates.stockTax,')
M('trade',CH,'InstrumentKind.bondEtf => rates.bondEtfTax,','InstrumentKind.bondEtf => rates.etfTax,')
M('trade',CH,'BigInt.from(perTenThousand) ~/ BigInt.from(10000)','BigInt.from(perTenThousand) ~/ BigInt.from(1000)')
M('trade',CH,'gross.minorUnits < BigInt.from(rates.premiumThreshold)','gross.minorUnits <= BigInt.from(rates.premiumThreshold)')
M('trade',CH,'final cap = BigInt.from(10000000);','final cap = BigInt.from(1000000);')
M('trade',CH,'base * BigInt.from(rates.premiumBasisPoints)','base * BigInt.from(rates.premiumBasisPoints + 1)')
M('trade',CH,'if (!quantity.isWhole) {','if (false) {')
M('trade',CH,'if (gross.currency != _twd) {\n      throw const InvestmentException(InvestmentError.currencyMismatch);\n    }\n    if (gross.minorUnits.isNegative) {\n      throw const InvestmentException(InvestmentError.invalidInput);\n    }\n    if (!quantity','if (gross.currency != _twd) {\n      throw const InvestmentException(InvestmentError.currencyMismatch);\n    }\n    if (false) {\n      throw const InvestmentException(InvestmentError.invalidInput);\n    }\n    if (!quantity')
M('trade',CH,'final base = gross.minorUnits > cap ? cap : gross.minorUnits;','final base = gross.minorUnits > cap ? gross.minorUnits : cap;')
M('trade',CH,'Money(_twd, BigInt.zero);\n  }\n  final cap','Money(_twd, BigInt.one);\n  }\n  final cap')
RT = 'packages/ledger/trade_costs/lib/rules/taiwan_rates.dart'
M('trade',RT,'if (rates.from.compareTo(date) <= 0) return rates;','if (rates.from.compareTo(date) < 0) return rates;')
M('trade',RT,'BusinessDate(2021, 1, 1)','BusinessDate(2021, 1, 2)')
M('trade',RT,'BusinessDate(2017, 4, 28)','BusinessDate(2017, 4, 29)')
M('trade',RT,'BusinessDate(2017, 1, 1)','BusinessDate(2017, 1, 2)')
M('trade',RT,'BusinessDate(2027, 1, 1)','BusinessDate(2027, 1, 2)')
M('trade',RT,'BusinessDate(2028, 1, 1)','BusinessDate(2028, 1, 2)')
M('trade',RT,'premiumBasisPoints: 211,\n      premiumThreshold: 20000,\n    ),\n    TaiwanRates._(\n      from: BusinessDate(2027','premiumBasisPoints: 191,\n      premiumThreshold: 20000,\n    ),\n    TaiwanRates._(\n      from: BusinessDate(2027')
M('trade',RT,'stockTax: 30,\n      dayTradeTax: 30,\n      etfTax: 10,\n      bondEtfTax: 10,\n      premiumBasisPoints: 211,','stockTax: 30,\n      dayTradeTax: 15,\n      etfTax: 10,\n      bondEtfTax: 10,\n      premiumBasisPoints: 211,')
ST = 'packages/ledger/trade_costs/lib/calc/settlement.dart'
M('trade',ST,'TradeKind.buy => -(gross + fee)','TradeKind.buy => -(gross - fee)')
M('trade',ST,'TradeKind.sell => gross - fee - tax','TradeKind.sell => gross - fee + tax')
M('trade',ST,'TradeKind.sell => gross - fee - tax','TradeKind.sell => gross - tax')
M('trade',ST,'TradeKind.dividend => gross - tax','TradeKind.dividend => gross + tax')
M('trade',ST,'TradeKind.capitalReturn => gross','TradeKind.capitalReturn => gross - fee')
MD = 'packages/ledger/trade_costs/lib/rules/taiwan_market_days.dart'
M('trade',MD,'const taiwanSettlementDays = 2;','const taiwanSettlementDays = 3;')
M('trade',MD,'const taiwanSettlementDays = 2;','const taiwanSettlementDays = 1;')
M('trade',MD,'workdays: const {},','workdays: closed.workdays,')
M('trade',MD,'2025-05-01,holiday,勞動節\n','')
BD = 'packages/ledger/trade_costs/lib/calc/broker_discount.dart'
M('trade',BD,'basisPoints >= lowest &&','basisPoints > lowest &&')
M('trade',BD,'basisPoints <= highest;','basisPoints < highest;')
M('trade',BD,'static const highest = 10000;','static const highest = 10001;')
M('trade',BD,'static const lowest = 1;','static const lowest = 0;')
M('trade',BD,'final places = inUnit ? 3 : 4;','final places = inUnit ? 4 : 3;')
M('trade',BD,'final places = inUnit ? 3 : 4;','final places = inUnit ? 4 : 3;')
M('trade',BD,'if (fraction.length > places)','if (fraction.length >= places)')
M('trade',BD,".length > 2) {\n    return const DiscountOutOfRange","  .length > 3) {\n    return const DiscountOutOfRange")
M('trade',BD,"number == '.')","number == '..')")
M('trade',BD,'basisPoints.clamp(lowest, highest)','basisPoints.clamp(lowest + 1, highest)')
M('trade',BD,"number.isEmpty ||","false ||")

# ---------------- loans ----------------
LP = 'packages/ledger/loans/lib/calc/loan_plan.dart'
M('loans',LP,'final _monthly = BigInt.from(120000);','final _monthly = BigInt.from(100000);')
M('loans',LP,'(numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two)','(numerator * BigInt.two + denominator - BigInt.one) ~/ (denominator * BigInt.two)')
M('loans',LP,'LoanRounding.down => numerator ~/ denominator,','LoanRounding.down => (numerator + denominator - BigInt.one) ~/ denominator,')
M('loans',LP,'const loanInterestRounding = LoanRounding.halfUp;','const loanInterestRounding = LoanRounding.down;')
M('loans',LP,'if (amount == null || amount <= 0) return null;','if (amount == null || amount < 0) return null;')
M('loans',LP,'if (months == null || months <= 0) return null;','if (months == null || months < 0) return null;')
M('loans',LP,'final last = k == months;','final last = k == months - 1;')
M('loans',LP,'for (var k = 1; k <= months; k++) {','for (var k = 1; k < months; k++) {')
M('loans',LP,'interestOn(amount, k) - interestOn(amount, k - 1)','interestOn(amount, k) - interestOn(amount, k - 2)')
M('loans',LP,'interestOn(amount, k) - interestOn(amount, k - 1)','interestOn(amount)')
M('loans',LP,'LoanRepay.even => level - interest,','LoanRepay.even => level,')
M('loans',LP,'final principal = last ? owed : wanted.clamp(0, owed);','final principal = wanted.clamp(0, owed);')
M('loans',LP,'final principal = last ? owed : wanted.clamp(0, owed);','final principal = last ? owed : wanted;')
M('loans',LP,'final principal = last ? owed : wanted.clamp(0, owed);','final principal = last ? owed : wanted.clamp(1, owed);')
M('loans',LP,'final share = amount ~/ months;','final share = amount ~/ months + 1;')
M('loans',LP,'payment: interest + principal,','payment: principal,')
M('loans',LP,'(_monthly + yearly).pow(months)','(_monthly + yearly).pow(months - 1)')
M('loans',LP,'_monthly * (grown - _monthly.pow(months))','_monthly * (grown - _monthly.pow(months - 1))')
M('loans',LP,'last: schedule.last.payment,','last: schedule.first.payment,')
M('loans',LP,'first: schedule.first.payment,','first: schedule.last.payment,')
M('loans',LP,'if (yearly == BigInt.zero) {','if (yearly <= BigInt.zero) {')
M('loans',LP,'LoanRepay.principal => share,','LoanRepay.principal => share + 1,')
M('loans',LP,'BigInt.from(owed) * yearly * BigInt.from(forMonths),','BigInt.from(owed) * yearly,')
M('loans',LP,'owed -= principal;','owed -= interest;') if False else None
RA = 'packages/ledger/loans/lib/model/rate.dart'
M('loans',RA,'(next >= 5 ? 1 : 0)','(next > 5 ? 1 : 0)')
M('loans',RA,'hundredths > 10000 ? null','hundredths >= 10000 ? null')
M('loans',RA,'whole * 100 + kept','whole * 10 + kept')
M('loans',RA,'cents % 10 == 0','cents % 5 == 0')
M('loans',RA,"|| !typed.contains(RegExp(r'\\d'))",'|| false')
M('loans',RA,'decimals.length > 2 ? int.parse(decimals[2]) : 0','decimals.length > 3 ? int.parse(decimals[2]) : 0')
M('loans',RA,"padLeft(2, '0')}'","padLeft(1, '0')}'")
M('loans',RA,'if (cents == 0) return','if (cents == 1) return')

# ---------------- entries ----------------
PL = 'packages/ledger/entries/lib/model/planned.dart'
M('entries',PL,'bool countsOn(DateTime day, DateTime today) => !day.isAfter(today);','bool countsOn(DateTime day, DateTime today) => day.isBefore(today);')
M('entries',PL,'bool countsOn(DateTime day, DateTime today) => !day.isAfter(today);','bool countsOn(DateTime day, DateTime today) => !day.isAfter(today.add(const Duration(days: 1)));')
M('entries',PL,'bool isPlanned(Entry e, DateTime today) => !countsOn(e.date, today);','bool isPlanned(Entry e, DateTime today) => countsOn(e.date, today);')
M('entries',PL,'const maxDaysAhead = 365;','const maxDaysAhead = 366;')
M('entries',PL,'today.day + maxDaysAhead','today.day - maxDaysAhead')
M('entries',PL,'entries.where((e) => countsOn(e.date, today))','entries.where((e) => !countsOn(e.date, today))')
ER = 'packages/ledger/entries/lib/rules/entry_rules.dart'
M('entries',ER,'e.date.isAfter(latestEntryDay(today))','!e.date.isBefore(latestEntryDay(today))')
M('entries',ER,'e.isInvestment && isPlanned(e, today)','e.isInvestment && !isPlanned(e, today)')
M('entries',ER,'today != null && e.isInvestment','e.isInvestment')
M('entries',ER,'if (e.amount <= 0 && !stock)','if (e.amount < 0 && !stock)')
M('entries',ER,'if (e.amount <= 0 && !stock)','if (e.amount <= 0)')
M('entries',ER,'if (e.amount > maxAmountOf(currency)) {','if (e.amount >= maxAmountOf(currency)) {')
M('entries',ER,'if (e.fee < 0 || e.tax < 0) found.add','if (e.fee < 0 && e.tax < 0) found.add')
M('entries',ER,'if (e.fee < 0 || e.tax < 0) found.add','if (e.fee < 0) found.add')
M('entries',ER,'if (e.fee < 0 || e.tax < 0) const NegativeCharge(),','if (e.fee < 0) const NegativeCharge(),')
M('entries',ER,'if (from == null) found.add(const UnknownAccount());','')
M('entries',ER,'if (transfer && e.account == e.to) {','if (transfer && e.account != e.to) {')
M('entries',ER,'} else if (transfer && to == null) {','} else if (transfer && to != null) {')
M('entries',ER,'currency != homeCode && e.home == null) {','currency != homeCode) {')
M('entries',ER,'if (transfer && from?.kind == AccountKind.card) {','if (transfer && from?.kind != AccountKind.card) {')
M('entries',ER,'if (transfer && e.fee > 0 && currency != homeCode) {','if (transfer && e.fee >= 0 && currency != homeCode) {')
M('entries',ER,'to.kind == AccountKind.card && e.fee > 0) {','to.kind == AccountKind.card && e.fee >= 0) {')
M('entries',ER,'to.currency != currency && e.received == null','to.currency != currency || e.received == null')
M('entries',ER,'currency != homeCode && to.kind == AccountKind.card) {','currency == homeCode && to.kind == AccountKind.card) {')
M('entries',ER,'if (e.isInvestment && currency != homeCode) {','if (e.isInvestment && currency == homeCode) {')
M('entries',ER,'if (e.isInvestment && (from?.kind.isDebt ?? false)) {','if (e.isInvestment && !(from?.kind.isDebt ?? false)) {')
M('entries',ER,'-e.shares > held','-e.shares >= held')
M('entries',ER,'e.isReduction && held != null','held != null')
M('entries',ER,'!e.isReduction && e.tax > e.amount','!e.isReduction && e.tax >= e.amount')
M('entries',ER,'e.isInvestment && e.holding == null','e.isInvestment && e.holding != null')
M('entries',ER,'if (trade && e.shares <= 0)','if (trade && e.shares < 0)')
M('entries',ER,'e.dayTrade && e.type != EntryType.sell','e.dayTrade && e.type == EntryType.sell')
M('entries',ER,'(e.type == EntryType.sell || e.isReduction) && facts.oversells','(e.type == EntryType.sell) && facts.oversells')
M('entries',ER,'e.account != refunded.account','e.account == refunded.account')
M('entries',ER,'refunded.kind == AccountKind.card &&','refunded.kind != AccountKind.card &&')
M('entries',ER,'e.amount > refunded.left + refunded.own','e.amount >= refunded.left + refunded.own')
M('entries',ER,'e.amount > refunded.left + refunded.own','e.amount > refunded.left')
M('entries',ER,'if (e.installments < 0 || e.installments > maxInstallments) {','if (e.installments < 0 || e.installments > maxInstallments + 1) {')
M('entries',ER,'if (e.installments < 0 || e.installments > maxInstallments)\n    const','if (e.installments < -1 || e.installments > maxInstallments)\n    const')
M('entries',ER,'if (e.installments < 0 || e.installments > maxInstallments)\n    const','if (e.installments < 0 || e.installments >= maxInstallments)\n    const')
M('entries',ER,'if (e.installments > 1 &&','if (e.installments >= 1 &&')
M('entries',ER,'(e.type != EntryType.expense || from?.kind != AccountKind.card)','(e.type != EntryType.expense && from?.kind != AccountKind.card)')
M('entries',ER,'after != null &&\n      after < 0 &&','after != null &&\n      after <= 0 &&')
M('entries',ER,'e.type == EntryType.buy &&\n      after != null','e.type == EntryType.sell &&\n      after != null')
M('entries',ER,'!(from?.kind.isDebt ?? false)) {\n    found.add(NegativeBalanceAfter','(from?.kind.isDebt ?? false)) {\n    found.add(NegativeBalanceAfter')
M('entries',ER,'if (total != e.amount) SplitTotalMismatch','if (total > e.amount) SplitTotalMismatch')
M('entries',ER,'if (amount <= 0) positive = false;','if (amount < 0) positive = false;')
M('entries',ER,'d.isUtc &&\n    d.hour','d.hour')
M('entries',ER,'d.millisecond == 0 &&','true &&')
M('entries',ER,'d.microsecond == 0;','true;')
M('entries',ER,'if (e.amount < 0) const MissingAmount(trade: false),','if (e.amount <= 0) const MissingAmount(trade: false),')
M('entries',ER,"if (e.type == EntryType.transfer && (e.to ?? '').isEmpty)","if (e.type == EntryType.transfer && (e.to ?? '').isNotEmpty)")
M('entries',ER,'const maxInstallments = 60;','const maxInstallments = 61;')
RR = 'packages/ledger/entries/lib/rules/record_rules.dart'
M('entries',RR,'if (amount <= 0) const MissingAmount(trade: false),','if (amount < 0) const MissingAmount(trade: false),')
M('entries',RR,'end.isBefore(start)','!end.isAfter(start)')
M('entries',RR,'if (every < 1) const IntervalTooSmall(),','if (every < 0) const IntervalTooSmall(),')
M('entries',RR,'if (day < 1 || day > 31) const DayOutOfRange(),','if (day < 0 || day > 31) const DayOutOfRange(),')
M('entries',RR,'if (day < 1 || day > 31) const DayOutOfRange(),','if (day < 1 || day > 32) const DayOutOfRange(),')
M('entries',RR,'if (amount < 0) const MissingAmount(trade: false),\n  if (amount > max','if (amount <= 0) const MissingAmount(trade: false),\n  if (amount > max')
M('entries',RR,'name.trim().isEmpty','name.isEmpty')
M('entries',RR,'(closingDay < 1 || closingDay > 31)','(closingDay < 1 || closingDay > 30)')
M('entries',RR,'(dueDay < 1 || dueDay > 31)','(dueDay < 2 || dueDay > 31)')
M('entries',RR,'limit != null && limit < 0','limit != null && limit <= 0')
M('entries',RR,'if (limit < 0) const NegativeBudgetLimit(),','if (limit <= 0) const NegativeBudgetLimit(),')
M('entries',RR,'warning < 1 || warning > 100','warning < 1 || warning > 99')
M('entries',RR,'warning < 1 || warning > 100','warning < 2 || warning > 100')
EN = 'packages/ledger/entries/lib/model/entry.dart'
M('entries',EN,'EntryType.income when isRefund => -worth,','EntryType.income when isRefund => worth,')
M('entries',EN,'EntryType.transfer => fee,','EntryType.transfer => 0,')
M('entries',EN,'EntryType.income when !isRefund => worth,','EntryType.income => worth,')
M('entries',EN,'int get arrived => received ?? amount;','int get arrived => amount;')
M('entries',EN,'bool get isReduction => type == EntryType.dividend && shares < 0;','bool get isReduction => type == EntryType.dividend && shares <= 0;')
M('entries',EN,'type == EntryType.dividend && !isReduction ? settlement : 0;','type == EntryType.dividend ? settlement : 0;')
M('entries',EN,'if (spending == 0) return const [];','if (spending <= 0) return const [];')
M('entries',EN,'bool get _splitCounts => parts.isNotEmpty && home == null;','bool get _splitCounts => parts.isNotEmpty;')
M('entries',EN,'EntryType.dividend when isReduction => TradeKind.capitalReturn,','')

# ---------------- domain ----------------
LM = 'packages/domain/lib/src/investments/lot_math.dart'
M('domain',LM,'cost * sold[i] ~/ lots[i].units;','(cost * sold[i] + lots[i].units - BigInt.one) ~/ lots[i].units;')
M('domain',LM,'final taken = sold[i] == lots[i].units\n          ? cost','final taken = sold[i] == BigInt.zero\n          ? cost')
M('domain',LM,'if (method == InvestmentCostMethod.fifo) {','if (method != InvestmentCostMethod.fifo) {')
M('domain',LM,': totalCost * quantity ~/ totalQuantity;',': (totalCost * quantity + totalQuantity - BigInt.one) ~/ totalQuantity;')
M('domain',LM,'_spread(totalCost - allocated, left, totalQuantity - quantity, keptCosts);','_spread(totalCost - allocated, left, totalQuantity, keptCosts);')
M('domain',LM,'final taken = toSell < lot.units ? toSell : lot.units;','final taken = toSell > lot.units ? toSell : lot.units;')
M('domain',LM,'quantity < BigInt.zero || quantity > totalQuantity','quantity < BigInt.zero || quantity >= totalQuantity')
M('domain',LM,'quantity < BigInt.zero || quantity > totalQuantity','quantity <= BigInt.zero || quantity > totalQuantity')
M('domain',LM,'units.lastIndexWhere((u) => u > BigInt.zero)','units.lastIndexWhere((u) => u >= BigInt.zero)')
M('domain',LM,'final share = i == last ? rest : amount * units[i] ~/ total;','final share = i == last ? rest : (amount * units[i] + total - BigInt.one) ~/ total;')
M('domain',LM,'if (expanded.remainder(divisor) != BigInt.zero) return null;','if (expanded.remainder(divisor) == BigInt.zero) return null;')
M('domain',LM,'final expanded = units * BigInt.from(newShares);','final expanded = units * BigInt.from(oldShares);')
M('domain',LM,'wholeSharesOnly ? total % unitsPerShare : BigInt.zero','wholeSharesOnly ? total ~/ unitsPerShare : BigInt.zero')
M('domain',LM,'BigInt.from(10).pow(12)','BigInt.from(10).pow(11)')
M('domain',LM,'i >= 0 && drop > BigInt.zero','i > 0 && drop > BigInt.zero')
M('domain',LM,'final taken = drop < units[i] ? drop : units[i];','final taken = drop > units[i] ? drop : units[i];')
M('domain',LM,'if (units[i] == BigInt.zero) continue;\n    final taken','final taken')
M('domain',LM,'if (numerator.remainder(denominator) * BigInt.two >= denominator) {','if (numerator.remainder(denominator) * BigInt.two > denominator) {')
M('domain',LM,'final lowered = returned < basis ? returned : basis;','final lowered = returned > basis ? returned : basis;')
M('domain',LM,'if (lowered > BigInt.zero) {','if (lowered >= BigInt.zero) {')
M('domain',LM,'if (costs[i] > BigInt.zero) i,','if (costs[i] >= BigInt.zero) i,')
M('domain',LM,'costs[i] -= parts[n].minorUnits;','costs[i] += parts[n].minorUnits;')
M('domain',LM,'costs[i] -= cost;\n    droppedCost += cost;','droppedCost += cost;')
M('domain',LM,'if (units[i] == BigInt.zero) continue;\n    final share','final share') if False else None
M('domain',LM,'if (units[i] == BigInt.zero) continue;\n    final share','final share') if False else None
IN = 'packages/domain/lib/src/credit_cards/installments.dart'
M('domain',IN,'total - each * (count - 1)','total - each * count')
M('domain',IN,'if (count < 1 || total < 0) {','if (count < 2 || total < 0) {')
M('domain',IN,'if (count < 1 || total < 0) {','if (count < 1 || total <= 0) {')
M('domain',IN,'for (var i = 1; i < count; i++) each','for (var i = 1; i <= count; i++) each')
M('domain',IN,'closingDay <= lastDay ? closingDay : lastDay','closingDay < lastDay ? closingDay : lastDay')
M('domain',IN,'shiftMonth(first.year, first.month, index)','shiftMonth(first.year, first.month, index + 1)')
M('domain',IN,'final lastDay = daysInMonth(year, month);','final lastDay = daysInMonth(year, month) - 1;')
M('domain',IN,'return (first, schedule.closingDayOn(first));','return (first, schedule.closingDay);')
CB = 'packages/domain/lib/src/credit_cards/card_billing.dart'
CR = 'packages/domain/lib/src/credit_cards/card_rules.dart'
M('domain',CR,'if (left > 0) return BillDue(dueOn, left);','if (left >= 0) return BillDue(dueOn, left);')
M('domain',CR,'if (left == 0) return BillDueToday(dueOn);','if (left == 1) return BillDueToday(dueOn);')
M('domain',CR,'if (owed <= 0) return const BillPaid();','if (owed < 0) return const BillPaid();')
M('domain',CR,'return BillOverdue(dueOn, -left);','return BillOverdue(dueOn, left);')
M('domain',CR,'final last = payBy ?? dueOn;','final last = dueOn;')
M('domain',CR,'if (dueOn == null) return const BillNotYetBilled();','')
M('domain',CR,'final left = today.daysUntil(last);','final left = today.daysUntil(last) - 1;')  # 38: retargeted
M('domain',CB,'if (shift > 7 ||','if (shift >= 7 ||')
M('domain',CB,'closesOn.compareTo(dueOn) >= 0) {','closesOn.compareTo(dueOn) > 0) {')
M('domain',CB,'if (date.compareTo(actual[i].$1) <= 0) {','if (date.compareTo(actual[i].$1) < 0) {')
M('domain',CB,'if (due.compareTo(close) <= 0) {','if (due.compareTo(close) < 0) {')
M('domain',CB,'if (date.compareTo(change.until) < 0) {','if (date.compareTo(change.until) <= 0) {')
M('domain',CB,'return date == cycle.closesOn ? cycle.closesOn : cycle.startsAfter;','return date == cycle.closesOn ? cycle.startsAfter : cycle.closesOn;')
M('domain',CB,'close.compareTo(scheduledStartsAfter) > 0 &&','close.compareTo(scheduledStartsAfter) >= 0 &&')
M('domain',CB,'close.compareTo(scheduledClose) <= 0;','close.compareTo(scheduledClose) < 0;')
M('domain',CB,'if (startsAfter.compareTo(closesOn) >= 0 ||','if (startsAfter.compareTo(closesOn) > 0 ||')
M('domain',CB,'(earlier != null && until.compareTo(earlier) <= 0)','(earlier != null && until.compareTo(earlier) < 0)')
M('domain',CB,'for (var offset = -3; offset <= 3; offset++) {','for (var offset = -3; offset <= 2; offset++) {')
M('domain',CB,'closingDay < 1 || closingDay > 31 || dueDay < 1 || dueDay > 31','closingDay < 1 || closingDay > 31 || dueDay < 2 || dueDay > 31')
M('domain',CB,'closingDay < 1 || closingDay > 31 || dueDay < 1 || dueDay > 31','closingDay < 1 || closingDay > 30 || dueDay < 1 || dueDay > 31')
M('domain',CB,'(result.year < 1 || result.year > 9999)','(result.year < 1 || result.year > 9998)') if False else None
HR = 'packages/domain/lib/src/investments/holding_rules.dart'
M('domain',HR,'shares > 0 ? HoldingStatus.held','shares >= 0 ? HoldingStatus.held')

# ---------------- app: balance ----------------
# Retargeted to the code of 2026-11 where the review-11 text is gone; the
# ids keep the review's numbering and intent.
BS = SVC + 'balance_service.dart'
M('balance',BS,'EntryType.transfer => -(e.amount + e.fee),','EntryType.transfer => -(e.amount),')
M('balance',BS,'change += e.arrived;','change += e.amount;')
M('balance',BS,'EntryType.expense => -from.billed(e, at),','EntryType.expense => from.billed(e, at),')
M('balance',BS,'EntryType.income => e.amount,','EntryType.income => -e.amount,')
M('balance',BS,'if (!from && !into) continue;','if (!from) continue;')  # 05 transfer in
M('balance',BS,'if (change > 0) {','if (change >= 0) {')
M('balance',BS,'outflow -= change;','outflow += change;')
M('balance',BS,'steps.add((day.microsecondsSinceEpoch, -share));','steps.add((day.microsecondsSinceEpoch, share));')
M('balance',BS,'(i < days.length && days[i] <= steps[k].$1)','(i < days.length && days[i] < steps[k].$1)')
M('balance',BS,'if (!a.inNetWorth) continue;\n      final worth = worthOf(a, until: day);','final worth = worthOf(a, until: day);')  # 10
M('balance',BS,'} else if (a.kind == AccountKind.receivable) {','} else if (a.kind == AccountKind.card) {')  # 11
M('balance',BS,'if (a.kind != kind || !a.inNetWorth) continue;','if (a.kind != kind) continue;')  # 12
M('balance',BS,'if (worth < 0) total -= worth;','total -= worth;')  # 13
M('balance',BS,'Duration(days: 7 * (weeks - 1))','Duration(days: 7 * weeks)')
M('balance',BS,'final end = last.isAfter(today) ? today : last;','final end = last;')  # 15 planned this week
M('balance',BS,'running.until(start.subtract(const Duration(days: 1)));','running.until(start);')  # 16
M('balance',BS,'final last = start.add(const Duration(days: 6));','final last = start.add(const Duration(days: 7));')  # 17
M('balance',BS,'final worth = worthOf(a, until: day);','final worth = worthOf(a);')  # 18
M('balance',BS,'_market.rateOf(a.currency) == null) a,','_market.rateOf(a.currency) != null) a,')
M('balance',BS,'when was == version && identical(from, own)','when was == version')
M('balance',BS,'return low == 0 ? 0 : totals[low - 1];','return low == 0 ? 0 : totals[low == days.length ? low - 1 : low];')
M('balance',BS,'return total + running.until(end);','return running.until(end);')
M('balance',BS,'if (!countsOn(day, today)) continue;','')  # 23 flowOf as of today
M('balance',BS,'if (!countsOn(at, day)) {','if (at.isAfter(day.add(const Duration(days: 1)))) {')  # 24 tomorrow counted
M('balance',BS,'invested += timesPrice(_holdings.sharesOn(h.code, day), h.price);','invested += timesPrice(_holdings.sharesOn(h.code, _today()), h.price);')  # 25
M('balance',BS,'final to = _firstAtOrAfter(last.microsecondsSinceEpoch + 1);','final to = _firstAtOrAfter(last.microsecondsSinceEpoch);')
M('balance',BS,"('flow', account, month.year, month.month, today),","('flow', account, month.year, month.month),")
M('balance',BS,"        weeks,\n        _today(),\n      ), () => _weeklyChanges","        weeks,\n      ), () => _weeklyChanges")
M('balance',BS,'owed -= worth;','owed += worth;')
M('balance',BS,'if (cancelled.isNotEmpty) {','if (cancelled.isNotEmpty && false) {')
M('balance',BS,'if (countsOn(day, at)) change -= billed;','change -= billed;')

# ---------------- report ----------------
RSV = SVC + 'report_service.dart'
M('report',RSV,'e.date.day <= untilDay','e.date.day < untilDay')
M('report',RSV,'e.account == account)','e.account != account)')
M('report',RSV,'for (final m in monthStarts(from, to)) {','for (final m in monthStarts(from, monthStart(to, -1))) {')  # 03
M('report',RSV,'if (!e.date.isBefore(from) && !e.date.isAfter(to)) yield e;','if (e.date.isAfter(from) && !e.date.isAfter(to)) yield e;')
M('report',RSV,'if (!e.date.isBefore(from) && !e.date.isAfter(to)) yield e;','if (!e.date.isBefore(from) && e.date.isBefore(to)) yield e;')
M('report',RSV,'for (final e in _between(from, to)) {\n      income += e.earning;\n      expense += e.spending;','for (final e in _between(from, to)) {\n      income += e.earning;\n      expense -= e.spending;')  # 06
M('report',RSV,'for (final e in _between(from, to)) {\n      income += e.earning;','for (final e in _between(from, to)) {\n      income += e.amount;')  # 07
M('report',RSV,'|| e.merchant.isEmpty) continue;',') continue;')
M('report',RSV,'rows.sort((a, b) => b.$3.compareTo(a.$3));','rows.sort((a, b) => a.$3.compareTo(b.$3));')
M('report',RSV,'rows.sort((a, b) => b.$2.compareTo(a.$2));','rows.sort((a, b) => a.$2.compareTo(b.$2));')
M('report',RSV,'if (e.spending == 0) continue;','if (e.spending != 0) continue;')
M('report',RSV,'var back = -_accounts.resolve(person).opening;','var back = _accounts.resolve(person).opening;')
M('report',RSV,'back -= change;','back += change;')  # 13
M('report',RSV,'if (countsOn(e.date, _today())) e,','e,')  # 14 owedBy as of today
M('report',RSV,'if (amount > taken) owed.add','if (amount >= taken) owed.add')  # 15
M('report',RSV,'return owed.reversed.toList();','return owed.toList();')
M('report',RSV,'.fold(0, (total, e) => total + e.earning);','.fold(0, (total, e) => total + e.spending);')
M('report',RSV,'for (final back in const [0, 1]) {','for (final back in const [0]) {')
M('report',RSV,'final month = monthStart(_today(), -back);','final month = monthStart(_today(), back);')  # 19
M('report',RSV,'(counts[b] ?? 0).compareTo(counts[a] ?? 0)','(counts[a] ?? 0).compareTo(counts[b] ?? 0)')
M('report',RSV,'(sum, e) => sum + e.dividendNet','(sum, e) => sum + e.settlement')
M('report',RSV,'if (e.type == type) {','if (e.type != type) {')  # 22
M('report',RSV,'for (final e in countedOn(_entries.all, _today())) {\n      for (final tag in e.tags) {','for (final e in _entries.all) {\n      for (final tag in e.tags) {')  # 23 tagStats as of today
M('report',RSV,'countedOn(_entries.inMonth(year, month), _today());','_entries.inMonth(year, month);')
M('report',RSV,'if (e.type != EntryType.expense','if (e.type == EntryType.expense')
M('report',RSV,'totals[name] = (totals[name] ?? 0) + value;','totals[name] = (totals[name] ?? 0) - value;')
M('report',RSV,'DateTime get firstDay => _entries.firstDate ?? _today();','DateTime get firstDay => _today();')
M('report',RSV,'for (final e in countedOn(entries, _today())) {','for (final e in entries) {')  # totalsOf
M('report',RSV,'int spentOn(DateTime day) => countedOn(\n    _entries.onDay(day),\n    _today(),\n  ).fold','int spentOn(DateTime day) => _entries.onDay(day).fold')
M('report',RSV,']..sort((a, b) => b.$2.compareTo(a.$2));',']..sort((a, b) => a.$2.compareTo(b.$2));')  # tagStats order
M('report',RSV,'..sort((a, b) => b.$2.compareTo(a.$2)),','..sort((a, b) => a.$2.compareTo(b.$2)),')  # merchantStats order
M('report',RSV,"_cache.remember(('owedBy', person, _today()), () {","_cache.remember(('owedBy', person), () {")
M('report',RSV,"_cache.remember(('tagStats', _today()), _tagStats);","_cache.remember(('tagStats'), _tagStats);")
M('report',RSV,'return [...used, ...known.difference(used.toSet())];','return [...used];')
M('report',RSV,'counts[e.merchant] = (counts[e.merchant] ?? 0) + 1;','counts[e.merchant] = (counts[e.merchant] ?? 0) + 2;')

# ---------------- budget ----------------
BU = SVC + 'budget_service.dart'
M('budget',BU,'(current ? _today().day : days, days)','(days, days)')
M('budget',BU,'final current = year == _today().year && month == _today().month;\n    return (current','final current = year == _today().year || month == _today().month;\n    return (current')  # 02
M('budget',BU,'if (passed >= days || passed == 0) return spent;','if (passed > days || passed == 0) return spent;')
M('budget',BU,'if (passed >= days || passed == 0) return spent;','if (passed >= days) return spent;')
M('budget',BU,'final heading = own * days ~/ passed + _roundsUp(own * days, passed);','final heading = own * days ~/ passed;')  # 05
M('budget',BU,'final heading = own * days ~/ passed + _roundsUp(own * days, passed);','final heading = own * passed ~/ days + _roundsUp(own * days, passed);')  # 06
M('budget',BU,'if (!budget.carry || budget.limit == 0) return budget.limit;','if (!budget.carry) return budget.limit;')
M('budget',BU,'if (!budget.carry || budget.limit == 0) return budget.limit;','if (budget.carry || budget.limit == 0) return budget.limit;')
M('budget',BU,'last.isBefore(since)','!last.isAfter(since)')
M('budget',BU,'last.isBefore(since)','last.isAfter(since)')
M('budget',BU,'(left > 0 ? left : 0)','left')
M('budget',BU,'final last = monthStart(DateTime.utc(year, month), -1);','final last = monthStart(DateTime.utc(year, month), -2);')  # 12
M('budget',BU,'budget.limit - spentAgainst(budget, last.year, last.month)','budget.limit + spentAgainst(budget, last.year, last.month)')
M('budget',BU,'total += spendingUnder(e, budget.category, _parentOf);','total -= spendingUnder(e, budget.category, _parentOf);')  # 14
M('budget',BU,'if (budget.category == allSpending) return','if (budget.category != allSpending) return')
M('budget',BU,'if (e.tags.contains(tag)) total += e.spending;','if (!e.tags.contains(tag)) total += e.spending;')
M('budget',BU,'for (final e in countedOn(_entries.inMonth(year, month), _today())) {\n      if (e.tags','for (final e in _entries.inMonth(year, month)) {\n      if (e.tags')
M('budget',BU,'for (final e in countedOn(_entries.inMonth(year, month), _today())) {\n      total += spendingUnder','for (final e in _entries.inMonth(year, month)) {\n      total += spendingUnder')  # 18
M('budget',BU,'if (budget.tag case final tag?) return spentOnTag','if (budget.tag case final tag? when false) return spentOnTag')
M('budget',BU,'if (rest * 2 < denominator) return 0;','if (rest * 2 <= denominator) return 0;')
M('budget',BU,'return numerator < 0 ? -1 : 1;','return 1;')
M('budget',BU,'return max(0, heading + earlier);','return heading + earlier;')
M('budget',BU,'if (original == null || original.date.isBefore(first)) {','if (original == null || !original.date.isAfter(first)) {')
M('budget',BU,'for (final e in countedOn(_entries.inMonth(year, month), _today())) {\n      final of','for (final e in _entries.inMonth(year, month)) {\n      final of')
M('budget',BU,'perDay: spent ~/ days,','perDay: spent ~/ (days - 1),')
M('budget',BU,'final remaining = days - passed + 1;','final remaining = days - passed;')
M('budget',BU,'perDay: left > 0 ? left ~/ remaining : 0,','perDay: left ~/ remaining,')
M('budget',BU,'forecast: passed >= forecastFrom ?','forecast: passed > forecastFrom ?')
M('budget',BU,'saved: total - spent','saved: spent - total')
M('budget',BU,'bool get overBudget => (forecast ?? 0) > total;','bool get overBudget => (forecast ?? 0) >= total;')

# ---------------- statement ----------------
SS = SVC + 'statement_service.dart'
M('statement',SS,'_today().subtract(const Duration(days: 1))','_today().subtract(const Duration(days: 0))')
M('statement',SS,'e.to == card.id &&\n          e.date.isAfter(end)','e.to == card.id &&\n          !e.date.isBefore(end)')
M('statement',SS,'e.to == card.id &&\n          e.date.isAfter(end)','e.to == card.id &&\n          e.date.isAfter(end.add(const Duration(days: 1)))')
M('statement',SS,'return max(0, -_balances.balance(card.id, until: end) - paid);','return max(0, -_balances.balance(card.id, until: end) + paid);')
M('statement',SS,'return max(0, -_balances.balance(card.id, until: end) - paid);','return min(0, -_balances.balance(card.id, until: end) - paid);')
M('statement',SS,'return max(0, -_balances.balance(card.id, until: end) - paid);','return max(0, -_balances.balance(card.id) - paid);')
M('statement',SS,'paid += e.arrived;','paid += e.amount;')
M('statement',SS,'for (final e in countedOn(_after(card, end), _today())) {','for (final e in _after(card, end)) {')  # 08 paid as of today
M('statement',SS,'EntryType.income => true,','EntryType.income => false,')
M('statement',SS,'EntryType.expense => e.installments < 2,','EntryType.expense => e.installments < 3,')
M('statement',SS,'EntryType.expense => e.installments < 2,','EntryType.expense => e.installments < 1,')
M('statement',SS,'for (final e in countedOn(_after(card, end), _today()))\n        if','for (final e in _after(card, end))\n        if')  # 12 unbilled as of today
M('statement',SS,'if (e.account == card.id && posted(e)) e,','if (posted(e)) e,')  # 13
M('statement',SS,'_balances.stillToBill(e) > 0)','_balances.stillToBill(e) >= 0)')  # 14
M('statement',SS,'e.installments > 1 &&\n            _balances','e.installments >= 1 &&\n            _balances')  # 15
M('statement',SS,'payBy: payByOf(due).value,','payBy: null,')
M('statement',SS,'today: BusinessDate.of(today),','today: BusinessDate.of(today.add(const Duration(days: 1))),')
M('statement',SS,'final end = card.closingOn(closedBy);','final end = card.closingOn(_today());')
M('statement',SS,'if (entries[middle].date.isAfter(end)) {','if (!entries[middle].date.isBefore(end)) {')
M('statement',SS,')..sort((a, b) => b.date.compareTo(a.date));',')..sort((a, b) => a.date.compareTo(b.date));')
M('statement',SS,"('due', card.id, closedBy, _today()),","('due', card.id, closedBy),")
M('statement',SS,'for (final e in countedOn(_entries.ofAccount(card.id), _today()))','for (final e in _entries.ofAccount(card.id))')

# ---------------- recurring ----------------
# Rewritten after review 11 (settled days, nearest day): a fresh set.
RE = SVC + 'recurring_service.dart'
M('recurring',RE,'var from = booked == null || booked.isEmpty ? _today() : booked.first.date;','var from = booked == null || booked.isEmpty ? _today() : booked.last.date;')
M('recurring',RE,'if (back != null && back.isBefore(from)) from = back;','if (back != null && back.isAfter(from)) from = back;')
M('recurring',RE,'final latest = booked.last.date.isAfter(_today())\n        ? booked.last.date\n        : _today();','final latest = _today();')
M('recurring',RE,'for (final m in monthStarts(first, monthStart(latest, 1)))','for (final m in monthStarts(first, latest))')
M('recurring',RE,'final last = e.date.isAfter(_today()) ? e.date : _today();','final last = e.date;')
M('recurring',RE,'if (!d.isAfter(last) ||','if (d.isBefore(last) ||')
M('recurring',RE,'(d.year == e.date.year && d.month == e.date.month))\n            d,','(d.year == e.date.year))\n            d,')
M('recurring',RE,'return d.year == date.year && d.month == date.month ? 1 : 2;','return d.year == date.year && d.month == date.month ? 2 : 1;')
M('recurring',RE,'if (rd < rb) best = d;','if (rd > rb) best = d;')
M('recurring',RE,'if (gap < 0 || (gap == 0 && d.isBefore(b))) best = d;','if (gap < 0 || (gap == 0 && d.isAfter(b))) best = d;')
M('recurring',RE,'? d.compareTo(b)','? b.compareTo(d)')
M('recurring',RE,'if (!item.active) return null;\n      final end','final end')
M('recurring',RE,'final end = monthEnd(_today().year, _today().month);','final end = _today();')
M('recurring',RE,'return days.isEmpty ? null : days.first;','return days.isEmpty ? null : days.last;')
M('recurring',RE,'if (!item.active) return const [];','')
M('recurring',RE,'monthStarts(from.isBefore(open) ? open : from, to)','monthStarts(from, to)')
M('recurring',RE,'if (!d.isBefore(from) && !d.isAfter(to) && !booked.contains(d)) {','if (d.isAfter(from) && !d.isAfter(to) && !booked.contains(d)) {')
M('recurring',RE,'if (!d.isBefore(from) && !d.isAfter(to) && !booked.contains(d)) {','if (!d.isBefore(from) && d.isBefore(to) && !booked.contains(d)) {')
M('recurring',RE,'if (!d.isBefore(from) && !d.isAfter(to) && !booked.contains(d)) {','if (!d.isBefore(from) && !d.isAfter(to)) {')
M('recurring',RE,'final next = monthStart(_today(), 1);','final next = monthStart(_today(), 2);')
M('recurring',RE,'if (!item.skipped.contains(d)) return d;','return d;')
M('recurring',RE,'if (!item.active) return null;\n    final next','final next')
M('recurring',RE,'when !d.isAfter(_today())) r,','when d.isBefore(_today())) r,')
M('recurring',RE,'when d.isAfter(_today())) (r, d),','when !d.isBefore(_today())) (r, d),')
M('recurring',RE,']..sort((a, b) => a.$2.compareTo(b.$2));',']..sort((a, b) => b.$2.compareTo(a.$2));')
M('recurring',RE,'final date = pending.isAfter(_today()) ? _today() : pending;','final date = pending;')
M('recurring',RE,'type: item.income ? EntryType.income : EntryType.expense,','type: item.income ? EntryType.expense : EntryType.income,')
M('recurring',RE,'home: currency == homeCode || date != _today()','home: currency == homeCode')
M('recurring',RE,'final pending = day ?? pendingDate(item) ?? _today();','final pending = pendingDate(item) ?? _today();')
M('recurring',RE,"('settled', item, _today()),","('settled', item),")

# ---------------- card cycle ----------------
CY = APP + 'lib/src/core/ledger/card_cycle.dart'
M('cardcycle',CY,'count < 2 ? [total] : installmentShares(total, count);','count < 1 ? [total] : installmentShares(total, count);')
M('cardcycle',CY,'if (count < 2) return e.amount;','if (count < 1) return e.amount;')
M('cardcycle',CY,'.take(periods)','.take(periods + 1)')
M('cardcycle',CY,'_utc(cycle.startsAfter).add(const Duration(days: 1))','_utc(cycle.startsAfter)')
M('cardcycle',CY,'if (day.compareTo(until) > 0) break;','if (day.compareTo(until) >= 0) break;')  # 05
M('cardcycle',CY,'if (e.installments < 1) return 0;','if (e.installments < 2) return 0;')
M('cardcycle',CY,'for (var keep = a.history.length; keep >= 0; keep--) {','for (var keep = a.history.length; keep > 0; keep--) {')
M('cardcycle',CY,'closingDay: a.closingDay ?? 1,','closingDay: a.closingDay ?? 2,')
M('cardcycle',CY,'dueDay: a.dueDay ?? 15,','dueDay: a.dueDay ?? 16,')
M('cardcycle',CY,'if (count < 2) return [(e.date, e.amount)];','if (count < 1) return [(e.date, e.amount)];')
M('cardcycle',CY,'(_utc(day), shares[k]),','(_utc(day), shares[0]),')  # 11
M('cardcycle',CY,'_day(e.date),\n        count,\n      ).indexed)','_day(e.date.add(const Duration(days: 1))),\n        count,\n      ).indexed)')  # 12
M('cardcycle',CY,'_utc(cycle.dueOn),','_utc(cycle.closesOn),')
M('cardcycle',CY,'final until = _day(at);','final until = _day(at.add(const Duration(days: 1)));')
M('cardcycle',CY,'if (kept != null && identical(kept.$1, this)) return kept.$2;','if (kept != null) return kept.$2;')
M('cardcycle',CY,'if (day.isAfter(at)) left += share;','if (!day.isBefore(at)) left += share;')
M('cardcycle',CY,'if (r.date.isAfter(at)) continue;','')
M('cardcycle',CY,'_day(end.add(const Duration(days: 1)))','_day(end)')

# ---------------- card summary ----------------
CSM = APP + 'lib/src/features/accounts/model/card_summary.dart'
M('cardsummary',CSM,'(sum, e) => sum - _balances.effect(e, card.id),','(sum, e) => sum + _balances.effect(e, card.id),')
M('cardsummary',CSM,'amounts[(periodsBilled(e) - 1).clamp(0, amounts.length - 1)]','amounts[(periodsBilled(e)).clamp(0, amounts.length - 1)]')
M('cardsummary',CSM,'int unbilledOf(Entry e) => _balances.stillToBill(e);','int unbilledOf(Entry e) => e.amount;')  # 03
M('cardsummary',CSM,'return l == null ? null : l - debt - pending;','return l == null ? null : l - debt + pending;')
M('cardsummary',CSM,'return l == null ? null : l - debt - pending;','return l == null ? null : l - debt;')
M('cardsummary',CSM,'((debt + pending) / l).clamp(0, 1)','((debt + pending) / l).clamp(0, 2)')
M('cardsummary',CSM,'((debt + pending) / l).clamp(0, 1)','((debt) / l).clamp(0, 1)')
M('cardsummary',CSM,'return percent(debt + pending, l);','return percent(debt, l);')
M('cardsummary',CSM,'(debt + pending) * 100 >= l * 80','(debt + pending) * 100 > l * 80')
M('cardsummary',CSM,'(debt + pending) * 100 >= l * 80','(debt + pending) * 100 >= l * 90')
M('cardsummary',CSM,'l != null && l > 0 && (debt','l != null && (debt')
M('cardsummary',CSM,'late final DateTime nextClose = card.closeAfter(end);','late final DateTime nextClose = card.closeAfter(end.add(const Duration(days: 1)));')  # 12
M('cardsummary',CSM,'int get cycleDays => nextClose.difference(end).inDays;','int get cycleDays => end.difference(nextClose).inDays;')  # 13
M('cardsummary',CSM,'int get daysGone => today.difference(end).inDays;','int get daysGone => end.difference(today).inDays;')
M('cardsummary',CSM,'    }\n    return nextClose;\n  }','    }\n    return end;\n  }')  # 15
M('cardsummary',CSM,'if (value == nextClose) return key;','if (value != nextClose) return key;')
M('cardsummary',CSM,'Entry? get payment => owed == 0\n      ? null','Entry? get payment => owed < 0\n      ? null')
M('cardsummary',CSM,'for (var month = 1; month <= today.month; month++) {','for (var month = 1; month < today.month; month++) {')
M('cardsummary',CSM,'if (e.mark == mark) return e.amount;','if (e.mark == mark) return -e.amount;')  # 19
M('cardsummary',CSM,'if (e.date.isAfter(end)) total += _markedPart(e, mark);','if (!e.date.isBefore(end)) total += _markedPart(e, mark);')  # 20
M('cardsummary',CSM,'late final int debt = -_balances.balance(card.id);','late final int debt = _balances.balance(card.id);')
M('cardsummary',CSM,'int get closingDay => card.closingDay ?? 1;','int get closingDay => card.closingDay ?? 2;')
M('cardsummary',CSM,'int get dueDay => card.dueDay ?? 15;','int get dueDay => card.dueDay ?? 16;')
M('cardsummary',CSM,"reward ? '其他收入' : feeCategory","reward ? feeCategory : '其他收入'")
M('cardsummary',CSM,'late final int pending = plans.fold(0, (sum, e) => sum + unbilledOf(e));','late final int pending = plans.fold(0, (sum, e) => sum - unbilledOf(e));')
M('cardsummary',CSM,'if (e.account != card.id) return 0;','')
M('cardsummary',CSM,'_entries.byId(of)?.mark == mark) return -e.amount;','_entries.byId(of)?.mark == mark) return e.amount;')
M('cardsummary',CSM,'for (final e in countedOn(_entries.inMonth(year, month), today)) {','for (final e in _entries.inMonth(year, month)) {')
M('cardsummary',CSM,'for (final e in countedOn(_entries.all, today)) {','for (final e in _entries.all) {')

# ---------------- amount.dart ----------------
AM = APP + 'lib/design_system/display/amount.dart'
M('amount',AM,'String signed(int value) => value > 0','String signed(int value) => value >= 0')
M('amount',AM,"'−${groupDigits(-value)}'","'−${groupDigits(value)}'")
M('amount',AM,"? '+${groupDigits(value)}'","? '${groupDigits(value)}'")
M('amount',AM,"String spent(int value) => '−${groupDigits(value)}';","String spent(int value) => '${groupDigits(value)}';")
M('amount',AM,'divideRounded(value, 1000)','value ~/ 1000')
M('amount',AM,'divideRounded(value, 1000)','divideRounded(value, 100)')
M('amount',AM,'if (value.abs() < 100000) return groupDigits(value);','if (value.abs() <= 100000) return groupDigits(value);')
M('amount',AM,'if (value.abs() < 100000) return','if (value < 100000) return')
M('amount',AM,"text.endsWith('.0') ? text.substring(0, text.length - 2) : text","text.endsWith('.0') ? text.substring(0, text.length - 1) : text")
M('amount',AM,'String amountIn(int minor, String currency) => currency == _home','String amountIn(int minor, String currency) => currency != _home')
M('amount',AM,"final zeros = '.${'0' * scale}';","final zeros = '.${'0' * (scale + 1)}';")
M('amount',AM,'return scale > 0 && text.endsWith(zeros)','return scale >= 0 && text.endsWith(zeros)')
M('amount',AM,'scale == 0 ? groupDigits(minor) : keyedAmount(minor, scale);','scale == 1 ? groupDigits(minor) : keyedAmount(minor, scale);')
M('amount',AM,'figures(minor, Currency.scaleOf(currency), grouped: false);','figures(minor, Currency.scaleOf(currency), grouped: true);')
M('amount',AM,'figures(minor, Currency.scaleOf(currency));','figures(minor, Currency.scaleOf(currency), grouped: false);')
M('amount',AM,"currency == _home ? r'NT$' : currency;","currency == _home ? currency : r'NT$';")
M('amount',AM,"'$currency ${figuresIn(minor, currency)}';","'${figuresIn(minor, currency)}';")
M('amount',AM,'_names[currency] ?? currency','_names[currency] ?? _home')
M('amount',AM,"final text = figures(minor, scale, grouped: false);\n  final zeros","final text = figures(minor, scale, grouped: true);\n  final zeros")
MUTANTS = [x for x in MUTANTS if x is not None]

# Mutants that cannot change what the code does, with why: left out of the
# score. Each was checked by hand; a code change can make one live again.
EQUIVALENT = {
    'core-42': "trimmedDecimals: figures() never writes '-0' (a negative "
               "minor keeps a non-zero digit after trimming)",
    'core-43': "fixedDecimals: figures() never writes '-0.00' for the same "
               "reason; the guard is defensive",
    'core-54': 'Fraction: the gcd of a non-zero denominator is at least 1, '
               'so dividing by a gcd of 1 changes nothing',
    'trade-45': 'readBrokerDiscount: three whole digits (100 and up) are '
                'past the range anyway and read DiscountOutOfRange; the '
                'guard only keeps int.parse off huge numbers',
    'domain-28': 'installmentCloses: closingDay == lastDay picks the same '
                 'day either way',
    'domain-49': 'CardSchedule._closesAround: every month has a close (a '
                 'day past the month end clamps to it), so the cycle of a '
                 'date is always found within a month either side; the '
                 'third month out is never reached',
    'balance-06': 'flowOf: a change of 0 adds 0 to the inflow or the '
                  'outflow alike',
    'balance-09': '_buildRunning: a change and an instalment step on the '
                  'same day are merged in either order; balances count a '
                  'whole day, and flows sum each side apart',
    'budget-04': 'forecast: no day of a month leaves 0 days gone (daysGone '
                 'is at least 1), so the guard is never reached',
}
