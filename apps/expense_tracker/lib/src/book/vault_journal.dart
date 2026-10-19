import 'dart:convert';
import 'dart:math';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:domain/accounts.dart';
import 'package:domain/bookkeeping.dart';
import 'package:domain/budgets.dart';
import 'package:domain/categories.dart';
import 'package:domain/investments.dart';
import 'package:domain/ledger.dart';
import 'package:domain/recurring_transactions.dart';
import 'package:domain/reports.dart';
import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/painting.dart' show Color;
import 'package:market/market_data.dart';
import 'package:storage/ledger_sqlcipher.dart';
import 'package:vault/ledger_vault.dart';

import '../model/journal.dart';
import '../model/ledger.dart' as ui;
import '../perf.dart';
import 'looks.dart';

part 'vault_app_events.dart';
part 'vault_catalogs.dart';
part 'vault_investments.dart';
part 'vault_loading.dart';
part 'vault_market.dart';
part 'vault_values.dart';

/// The categories a new ledger starts with, with their marks and colours.
const _starters = [
  ('居家生活', 'home', 0xFF5C9A83, false),
  ('飲食日常', 'food', 0xFFD08B5B, false),
  ('交通通勤', 'travel', 0xFF5B8DB0, false),
  ('購物休閒', 'bag', 0xFF8E7CC0, false),
  ('訂閱服務', 'subscription', 0xFFC9A34A, false),
  ('其他支出', 'other', 0xFFB07A8C, false),
  ('薪資收入', 'salary', 0xFF2F7A65, true),
  ('股息收入', 'dividend', 0xFF5A6FA8, true),
  ('其他收入', 'income', 0xFF4E8A9A, true),
];

/// Colours for categories without a saved one, picked by name.
const _palette = [
  0xFF5C9A83,
  0xFFD08B5B,
  0xFF5B8DB0,
  0xFF8E7CC0,
  0xFFC9A34A,
  0xFFB07A8C,
  0xFF4E8A9A,
  0xFF7F9A5B,
];

typedef _Label = ({PublicId id, String name, int version});

/// The book kept in the encrypted ledger. Loading builds the screens'
/// ledger from the stored accounts, postings and catalogs; each change
/// the screens make becomes the matching ledger command.
///
/// Trades go to one investment account per funding account, at a broker
/// named 券商, in instruments listed on TWSE.
final class VaultJournal implements Journal {
  VaultJournal(
    this._vault, {
    Clock clock = const SystemClock(),
    MarketDataGateway? market,
  }) : _clock = clock,
       _market = market,
       _books = Bookkeeping(_vault.ledger);

  final OpenVault _vault;
  final Clock _clock;

  /// Where closing prices come from; none in tests.
  final MarketDataGateway? _market;
  final _quotes = <String, double>{};

  /// NT$ for one unit of each currency on 臺灣銀行's latest board.
  final _rates = <String, double>{};
  final Bookkeeping<SqlBookkeeping> _books;
  late final _cards = CardBook(_books);
  late final _planning = PlanningBook(_books);
  late final _invest = InvestmentBook(_books);
  late final _looks = Looks(_vault.store, _workspace, _books.exclusive);

  LedgerStore get _store => _vault.ledger;

  /// Runs [job] with the ledger to itself, in turn with every change.
  Future<R> exclusive<R>(Future<R> Function() job) => _books.exclusive(job);
  WorkspaceId get _workspace => _vault.workspace;

  OperationKey _op() =>
      OperationKey(_workspace, OperationId(PublicId.generate()));

  // Loading.

  @override
  Future<ui.Ledger> load() => Perf.instance.timeLoad(_load);

  /// What the ledger holds of each stock, by code: shares and what they
  /// cost, from its own lots. The screens replay the same trades.
  Map<String, (int, int)> positions() {
    final held = <String, (int, int)>{};
    for (final account in _store.investmentAccounts(_workspace)) {
      for (final id in _store.positions(account.id)) {
        final instrument = _store.instrument(id);
        if (instrument == null) continue;
        var (shares, cost) = held[instrument.symbol] ?? (0, 0);
        for (final lot in _store.holdings(account.id, id)) {
          final quantity = lot.remainingQuantity;
          final unit = BigInt.from(10).pow(quantity.scale);
          shares += (quantity.coefficient ~/ unit).toInt();
          cost += _int(lot.remainingCost);
        }
        held[instrument.symbol] = (shares, cost);
      }
    }
    return held;
  }

  // Entries.

  @override
  Future<void> addEntries(List<ui.Entry> entries) async {
    for (final (i, entry) in entries.indexed) {
      try {
        await _add(entry);
      } on Object catch (error) {
        if (entries.length == 1) rethrow;
        throw PartlyKept(i, entries.length, error);
      }
    }
  }

  Future<PublicId> _add(ui.Entry e) async {
    final id = _newPosting(e.id);
    final account = _account(e.account);
    final day = _day(e.date);
    final refunded = e.refundOf;
    final template = _parse(e.recurring ?? '');
    if (template != null && await _confirm(id, e, account, day, template)) {
      await _note(id, e.note);
      return id;
    }
    switch (e.type) {
      case ui.EntryType.expense:
        await _spend(id, e, account, day);
      case ui.EntryType.income when refunded != null:
        await _refund(id, e, account, day, PublicId.parse(refunded));
      case ui.EntryType.income:
        await _earn(id, e, account, day);
      case ui.EntryType.transfer:
        await _transfer(id, e, account, day);
      case ui.EntryType.buy || ui.EntryType.sell || ui.EntryType.dividend:
        await _trade(id, e, account, day);
    }
    if (!_store.hasPosting(id)) return id;
    await _note(id, e.note);
    // A booking the ledger could not confirm, such as one on a card, is
    // still this item's, so it is not offered again.
    if (template != null) await _linkRecurring(id, template);
    return id;
  }

  Future<void> _spend(
    PublicId id,
    ui.Entry e,
    Account account,
    BusinessDate day,
  ) async {
    final shares = await _shares(e, income: false, account: account);
    if (account.kind != AccountKind.creditCard) {
      await _cashFlow(id, e, account, day, CashFlow.expense, shares);
      return;
    }
    final tags = await _tags(e.tags);
    final merchant = await _merchant(e.merchant);
    final charge = PublicId.generate();
    await _cards.post(
      PostCardCharge(
        operation: _op(),
        chargeId: charge,
        postingId: id,
        card: _ref(account),
        postedOn: day,
        settledAmount: _ntd(e.amount),
        fee: _ntd(0),
        allocations: shares,
        tags: tags,
        merchant: merchant,
      ),
    );
    if (e.installments > 1) {
      await _cards.planInstallments(
        PlanInstallments(
          operation: _op(),
          chargeId: charge,
          count: e.installments,
          fixedFee: _ntd(0),
        ),
      );
    }
  }

  Future<void> _earn(
    PublicId id,
    ui.Entry e,
    Account account,
    BusinessDate day,
  ) async {
    final shares = await _shares(e, income: true, account: account);
    if (account.kind == AccountKind.creditCard) {
      await _cards.adjust(
        AdjustCard(
          operation: _op(),
          chargeId: PublicId.generate(),
          postingId: id,
          card: _ref(account),
          postedOn: day,
          kind: CardAdjustment.credit,
          amount: _ntd(e.amount),
          allocations: shares,
        ),
      );
      return;
    }
    await _cashFlow(id, e, account, day, CashFlow.income, shares);
  }

  /// Records [e] as money in or out of a cash, bank or wallet [account].
  Future<void> _cashFlow(
    PublicId id,
    ui.Entry e,
    Account account,
    BusinessDate day,
    CashFlow flow,
    List<CategoryShare> shares,
  ) async {
    await _books.recordCashFlow(
      RecordCashFlow(
        operation: _op(),
        postingId: id,
        flow: flow,
        account: _ref(account),
        date: day,
        amount: _in(account, e.amount),
        allocations: shares,
        tags: await _tags(e.tags),
        merchant: await _merchant(e.merchant),
        homeValue: _homeOf(account, e),
      ),
    );
  }

  Future<void> _refund(
    PublicId id,
    ui.Entry e,
    Account account,
    BusinessDate day,
    PublicId original,
  ) async {
    final shares = _refundShares(original, _in(account, e.amount));
    final charge = _store.cardChargesByPosting(_workspace)[original];
    if (charge == null) {
      await _books.recordRefund(
        RecordRefund(
          operation: _op(),
          postingId: id,
          originalId: original,
          account: _ref(account),
          date: day,
          amount: _in(account, e.amount),
          allocations: shares,
        ),
      );
      return;
    }
    if (account.kind != AccountKind.creditCard) {
      throw const AppFailure(FailureKind.rejected, 'app.card-refund');
    }
    await _cards.refund(
      RefundCardCharge(
        operation: _op(),
        refundChargeId: PublicId.generate(),
        postingId: id,
        originalChargeId: charge,
        card: _ref(account),
        postedOn: day,
        amount: _ntd(e.amount),
        allocations: shares,
      ),
    );
  }

  /// [amount] of the spending [original] given back, spread over its
  /// categories in proportion, at the category versions it was booked
  /// with, as the ledger requires.
  List<CategoryShare> _refundShares(PublicId original, Money refund) {
    final amount = _int(refund);
    final posting = _store.postingById(original);
    final parts = posting?.allocations ?? const <Allocation>[];
    if (parts.isEmpty) return const [];
    final total = parts.fold(0, (sum, a) => sum + _int(a.amount));
    // Each part takes its share of the running total, so the parts always
    // add up to [amount] exactly.
    var running = 0;
    var given = 0;
    final shares = <CategoryShare>[];
    for (final a in parts) {
      running += _int(a.amount);
      final upTo = (amount * running / total).round();
      final value = upTo - given;
      given = upTo;
      if (value <= 0) continue;
      final version = a.expectedCategoryVersion ?? 1;
      final money = Money(refund.currency, BigInt.from(value));
      shares.add(CategoryShare(a.categoryId, version, money));
    }
    return shares;
  }

  Future<void> _transfer(
    PublicId id,
    ui.Entry e,
    Account from,
    BusinessDate day,
  ) async {
    final to = _account(e.to ?? '');
    if (from.kind == AccountKind.creditCard) {
      throw const AppFailure(FailureKind.rejected, 'app.card-transfer');
    }
    _requireHomeFee(from, e);
    final fee = e.fee > 0 ? _ntd(e.fee) : null;
    final feeShares = await _feeShares(e.fee);
    if (to.kind != AccountKind.creditCard) {
      await _books.recordTransfer(
        RecordTransfer(
          operation: _op(),
          postingId: id,
          source: _ref(from),
          destination: _ref(to),
          date: day,
          principal: _in(from, e.amount),
          received: _receivedIn(from, to, e),
          fee: fee,
          feeAllocations: feeShares,
        ),
      );
      return;
    }
    if (from.currency != homeCurrency) {
      throw const AppFailure(FailureKind.rejected, 'app.foreign-card-payment');
    }
    if (fee != null) {
      throw const AppFailure(FailureKind.rejected, 'app.card-fee');
    }
    await _cards.pay(
      PayCard(
        operation: _op(),
        paymentId: PublicId.generate(),
        postingId: id,
        source: _ref(from),
        card: _ref(to),
        statementClose: _lastClose(to.id, day),
        postedOn: day,
        amount: _ntd(e.amount),
      ),
    );
  }

  /// The close of the last statement before [day]: what a payment on
  /// [day] pays.
  BusinessDate _lastClose(PublicId card, BusinessDate day) {
    final terms = _store.cardTerms(card);
    if (terms == null) {
      throw const AppFailure(FailureKind.rejected, 'card.no-terms');
    }
    return terms.cycleFor(day).startsAfter;
  }

  @override
  Future<String> replaceEntry(ui.Entry before, ui.Entry after) async {
    final id = await _replace(before, after);
    final template = _parse(after.recurring ?? '');
    final posting = _parse(id);
    if (template != null &&
        posting != null &&
        !_recurringLinks().containsKey(posting)) {
      await _linkRecurring(posting, template);
    }
    return id;
  }

  Future<String> _replace(ui.Entry before, ui.Entry after) async {
    final id = _parse(before.id);
    if (id == null || !_store.hasPosting(id)) {
      return (await _add(after)).value;
    }
    if (_sameButNote(before, after)) {
      await _note(id, after.note);
      return id.value;
    }
    final plain =
        !_touchesCard(before) &&
        !_touchesCard(after) &&
        before.refundOf == null &&
        after.refundOf == null &&
        before.type == after.type;
    final account = _account(after.account);
    final day = _day(after.date);
    final replacement = PublicId.generate();
    if (plain &&
        (after.type == ui.EntryType.expense ||
            after.type == ui.EntryType.income)) {
      final income = after.type == ui.EntryType.income;
      await _books.correctCashFlow(
        CorrectCashFlow(
          operation: _op(),
          replacementId: replacement,
          originalId: id,
          reversalId: PublicId.generate(),
          account: _ref(account),
          date: day,
          amount: _in(account, after.amount),
          allocations: await _shares(after, income: income, account: account),
          tags: await _tags(after.tags),
          merchant: await _merchant(after.merchant),
          homeValue: _homeOf(account, after),
        ),
      );
      await _note(replacement, after.note);
      return replacement.value;
    }
    if (plain && after.type == ui.EntryType.transfer) {
      _requireHomeFee(account, after);
      final fee = after.fee > 0 ? _ntd(after.fee) : null;
      final destination = _account(after.to ?? '');
      await _books.correctTransfer(
        CorrectTransfer(
          operation: _op(),
          replacementId: replacement,
          originalId: id,
          reversalId: PublicId.generate(),
          source: _ref(account),
          destination: _ref(destination),
          date: day,
          principal: _in(account, after.amount),
          received: _receivedIn(account, destination, after),
          fee: fee,
          feeAllocations: await _feeShares(after.fee),
        ),
      );
      await _note(replacement, after.note);
      return replacement.value;
    }
    // The new form is added before the old one goes, so a stop in between
    // leaves both, one to delete, rather than neither. A recurring booking
    // must give up its occurrence first, and a form the ledger refuses
    // beside the old one (an edited sale) is tried after it is gone.
    if (before.recurring == null && after.recurring == null) {
      PublicId? added;
      try {
        added = await _add(after);
      } on AppFailure {
        added = null;
      }
      if (added != null) {
        try {
          await removeEntry(before);
        } on Object {
          await removeEntry(after.withId(added.value));
          rethrow;
        }
        return added.value;
      }
    }
    await removeEntry(before);
    try {
      return (await _add(after)).value;
    } on Object {
      // The new form was refused: put the old one back rather than lose it.
      await _add(before.withId(PublicId.generate().value));
      rethrow;
    }
  }

  @override
  Future<void> removeEntry(ui.Entry entry) async {
    final trade = _tradeOf(entry.id);
    if (trade != null) {
      final (account, instrument, tradeId) = trade;
      await _invest.voidTrade(
        VoidInvestmentTrade(
          operation: _op(),
          accountId: account,
          instrumentId: instrument,
          tradeId: tradeId,
          reversalId: PublicId.generate(),
        ),
      );
      return;
    }
    final id = _parse(entry.id);
    if (id == null || !_store.hasPosting(id)) return;
    final charge = _store.cardChargesByPosting(_workspace)[id];
    if (charge != null) {
      await _cards.voidCharge(
        VoidCardCharge(
          operation: _op(),
          chargeId: charge,
          reversalId: PublicId.generate(),
        ),
      );
      return;
    }
    final payment = _store.cardPaymentsByPosting(_workspace)[id];
    if (payment != null) {
      await _cards.voidPayment(
        VoidCardPayment(
          operation: _op(),
          paymentId: payment,
          reversalId: PublicId.generate(),
        ),
      );
      return;
    }
    await _books.deletePosting(
      DeletePosting(
        operation: _op(),
        reversalId: PublicId.generate(),
        originalId: id,
      ),
    );
  }

  bool _touchesCard(ui.Entry e) {
    for (final id in [e.account, e.to]) {
      if (id == null) continue;
      if (_findAccount(id)?.kind == AccountKind.creditCard) return true;
    }
    return false;
  }

  static bool _sameButNote(ui.Entry a, ui.Entry b) =>
      a.date == b.date &&
      a.type == b.type &&
      a.amount == b.amount &&
      a.account == b.account &&
      a.to == b.to &&
      a.category == b.category &&
      a.merchant == b.merchant &&
      listEquals(a.tags, b.tags) &&
      listEquals(a.parts, b.parts) &&
      a.fee == b.fee &&
      a.refundOf == b.refundOf &&
      a.installments == b.installments &&
      a.holding == b.holding &&
      a.shares == b.shares &&
      a.tax == b.tax &&
      a.average == b.average &&
      a.split == b.split &&
      a.home == b.home &&
      a.received == b.received;

  Future<void> _note(PublicId posting, String text) async {
    final current = _store.note(posting);
    if (current.text == text) return;
    await _books.setNote(
      SetNote(
        operation: _op(),
        postingId: posting,
        expectedRevision: current.revision,
        text: text,
      ),
    );
  }

  /// [id] when it is a free posting id, else a new one: a restored entry
  /// comes back under a new id, as its old posting stays reversed.
  PublicId _newPosting(String id) {
    final parsed = _parse(id);
    if (parsed != null && !_store.hasPosting(parsed)) return parsed;
    return PublicId.generate();
  }

  /// Books [e] as the next open occurrence of [template]. False when it
  /// cannot be: another account or kind, or nothing left to confirm; it is
  /// then booked as an ordinary entry.
  Future<bool> _confirm(
    PublicId id,
    ui.Entry e,
    Account account,
    BusinessDate day,
    PublicId template,
  ) async {
    final income = e.type == ui.EntryType.income;
    if (e.refundOf != null ||
        (e.type != ui.EntryType.expense && !income) ||
        account.kind == AccountKind.creditCard) {
      return false;
    }
    final saved = _template(template);
    if (saved == null) return false;
    final (kept, active) = saved;
    if (!active ||
        kept.accountId != account.id ||
        kept.amount.minorUnits.isNegative == income) {
      return false;
    }
    // The open occurrence nearest the entry: one booked a little early or
    // late settles its own day.
    BusinessDate? due;
    var gap = 1 << 30;
    final candidates = _store.dueRecurring(
      _workspace,
      after: _day(e.date.subtract(const Duration(days: 400))),
      through: _day(e.date.add(const Duration(days: 400))),
    );
    for (final candidate in candidates) {
      if (candidate.template.id != template) continue;
      final days = _date(candidate.dueDate).difference(e.date).inDays.abs();
      if (days < gap) {
        gap = days;
        due = candidate.dueDate;
      }
    }
    if (due == null) return false;
    try {
      await _planning.confirm(
        ConfirmRecurring(
          operation: _op(),
          postingId: id,
          templateId: template,
          expectedTemplateVersion: kept.version,
          dueDate: due,
          account: _ref(account),
          amount: _in(account, e.amount),
          date: day,
          allocations: await _shares(e, income: income, account: account),
          tags: await _tags(e.tags),
          merchant: await _merchant(e.merchant),
          homeValue: _homeOf(account, e),
        ),
      );
    } on AppFailure catch (error) {
      if (error.diagnostic.startsWith('recurring.')) return false;
      rethrow;
    }
    return true;
  }

  // Budgets and recurring items.

  /// The budget plans that apply this month, by the screens' name for
  /// them: [ui.Ledger.allSpending], a category, or `#` and a tag. Of
  /// several, the one that started last.
  Map<String, BudgetPlan> _applying(Map<PublicId, Category> categories) {
    final today = _clock.today();
    final now = today.year * 12 + today.month;
    final plans = <String, BudgetPlan>{};
    final key = _budgetKeys(categories);
    for (final plan in _store.budgetPlans(_workspace)) {
      final start = plan.month.year * 12 + plan.month.month;
      if (start > now || (start < now && !plan.repeats)) continue;
      final name = key(plan);
      if (name != null) plans[name] = plan;
    }
    return plans;
  }

  /// The screens' name for a plan: [ui.Ledger.allSpending], a category,
  /// or `#` and a tag; null when its category or tag is gone.
  String? Function(BudgetPlan plan) _budgetKeys(
    Map<PublicId, Category> categories,
  ) {
    final tags = {for (final t in _store.tags(_workspace)) t.id: t};
    return (plan) {
      if (plan.tagIds.isNotEmpty) {
        final tag = _live(tags, plan.tagIds.first, (t) => t.replacementId);
        return tag == null || tag.archived ? null : '#${tag.name}';
      }
      final category = plan.categoryId;
      if (category == null) return ui.Ledger.allSpending;
      return _live(categories, category, (c) => c.replacementId)?.name;
    };
  }

  Map<PublicId, Category> _categoryMap() => {
    for (final c in _store.categories(_workspace)) c.id: c,
  };

  @override
  Future<void> setBudget(ui.Budget budget) async {
    final key = budget.category;
    final tag = budget.tag;
    final category = key == ui.Ledger.allSpending || tag != null
        ? null
        : (await _category(key, income: false)).id;
    final tagId = tag == null ? null : (await _label(tag, merchant: false)).id;
    final current = _applying(_categoryMap())[key];
    final today = _clock.today();
    await _planning.setBudget(
      SetBudget(
        operation: _op(),
        budgetId: current?.id ?? PublicId.generate(),
        expectedVersion: current?.version ?? 0,
        month: current?.month ?? ReportMonth(today.year, today.month),
        limit: _ntd(budget.limit),
        categoryId: category,
        tagIds: {?tagId},
        warningPercent: budget.warning,
        repeats: true,
      ),
    );
  }

  @override
  Future<void> removeBudget(String category) async {
    final key = _budgetKeys(_categoryMap());
    for (final plan in _store.budgetPlans(_workspace)) {
      if (key(plan) != category) continue;
      await _planning.removeBudget(
        RemoveBudget(
          operation: _op(),
          budgetId: plan.id,
          expectedVersion: plan.version,
        ),
      );
    }
  }

  (RecurringTemplate, bool)? _template(PublicId id) {
    for (final saved in _store.recurringTemplates(_workspace)) {
      if (saved.$1.id == id) return saved;
    }
    return null;
  }

  ui.Recurring _recurringOf(
    RecurringTemplate t, {
    required bool active,
    required String Function(PublicId id) category,
    required String Function(PublicId? id) merchant,
  }) {
    final categoryId = t.categoryId;
    final last = t.lastDate;
    return ui.Recurring(
      id: t.id.value,
      name: t.label,
      amount: _int(t.amount).abs(),
      day: t.firstDate.day,
      account: t.accountId.value,
      category: categoryId == null ? '' : category(categoryId),
      active: active,
      unit: ui.RepeatUnit.values.byName(t.unit.name),
      every: t.every,
      start: _date(t.firstDate),
      end: last == null ? null : _date(last),
      income: !t.amount.minorUnits.isNegative,
      merchant: merchant(t.merchantId),
    );
  }

  @override
  Future<void> saveRecurring(ui.Recurring item) async {
    final id = _parse(item.id) ?? PublicId.generate();
    final current = _template(id);
    final account = _account(item.account);
    final category = item.category.isEmpty
        ? null
        : (await _category(item.category, income: item.income)).id;
    final merchant = item.merchant.isEmpty
        ? null
        : (await _label(item.merchant, merchant: true)).id;
    final today = _clock.today();
    final first = item.start ?? DateTime.utc(today.year, today.month, item.day);
    final end = item.end;
    await _planning.saveRecurring(
      SaveRecurring(
        operation: _op(),
        templateId: id,
        expectedVersion: current?.$1.version ?? 0,
        accountId: account.id,
        label: item.name,
        amount: _in(account, item.income ? item.amount : -item.amount),
        firstDate: _day(first),
        unit: RecurrenceUnit.values.byName(item.unit.name),
        every: item.every,
        active: item.active,
        lastDate: end == null ? null : _day(end),
        categoryId: category,
        merchantId: merchant,
      ),
    );
  }

  @override
  Future<void> removeRecurring(ui.Recurring item) async {
    final id = _parse(item.id);
    if (id == null || _template(id) == null) return;
    await saveRecurring(item.copyWith(active: false));
    await _append(_removedKind, {'template': id.value});
  }

  // Accounts.

  @override
  Future<void> saveAccount(ui.Account? before, ui.Account after) async {
    if (before == null) return _open(after);
    if (after.kind != before.kind) {
      throw const AppFailure(FailureKind.rejected, 'app.account-kind');
    }
    var account = _account(before.id);
    if (after.name != account.name) {
      await _books.renameAccount(
        RenameAccount(
          operation: _op(),
          accountId: account.id,
          expectedVersion: account.version,
          name: after.name,
        ),
      );
      account = _account(before.id);
    }
    if (after.inNetWorth != account.includeInNetWorth) {
      await _books.setNetWorthInclusion(
        SetNetWorthInclusion(
          operation: _op(),
          accountId: account.id,
          expectedVersion: account.version,
          included: after.inNetWorth,
        ),
      );
      account = _account(before.id);
    }
    if (after.archived != (account.state != AccountState.active)) {
      await _books.changeAccountState(
        ChangeAccountState(
          operation: _op(),
          accountId: account.id,
          expectedVersion: account.version,
          change: after.archived
              ? AccountStateChange.archive
              : AccountStateChange.reactivate,
        ),
      );
    }
    if (account.kind == AccountKind.creditCard) await _terms(account.id, after);
    final icon = after.icon;
    if (icon != null && icon != before.icon) {
      await _looks.save(account.id.value, (icon: icon, color: null));
    }
  }

  Future<void> _open(ui.Account a) async {
    final id = _parse(a.id) ?? PublicId.generate();
    final currency = Currency.of(a.currency);
    if (a.kind == ui.AccountKind.card && currency != homeCurrency) {
      throw const AppFailure(FailureKind.rejected, 'app.foreign-card');
    }
    final opening = a.opening == 0
        ? null
        : Money(currency, BigInt.from(a.opening));
    await _books.openAccount(
      OpenAccount(
        operation: _op(),
        accountId: id,
        name: a.name,
        kind: _kind(a.kind),
        currency: currency,
        openedOn: earliestBookingDate,
        includeInNetWorth: a.inNetWorth,
        openingBalance: opening,
        openingPostingId: opening == null ? null : PublicId.generate(),
      ),
    );
    if (a.kind == ui.AccountKind.card) await _terms(id, a);
    final icon = a.icon;
    if (icon != null) await _looks.save(id.value, (icon: icon, color: null));
  }

  /// Gives [card] the billing days and limit of [a], when they changed.
  Future<void> _terms(PublicId card, ui.Account a) async {
    final current = _store.cardTerms(card);
    final closing = a.closingDay ?? current?.closingDay ?? 1;
    final due = a.dueDay ?? current?.dueDay ?? 15;
    final limit = a.limit;
    final kept = current?.limit;
    if (current != null &&
        current.closingDay == closing &&
        current.dueDay == due &&
        (kept == null ? null : _int(kept)) == limit) {
      return;
    }
    final moved =
        current != null &&
        (current.closingDay != closing || current.dueDay != due);
    await _cards.setTerms(
      SetCardTerms(
        operation: _op(),
        cardId: card,
        expectedVersion: current?.version ?? 0,
        closingDay: closing,
        dueDay: due,
        limit: limit == null || limit <= 0 ? null : _ntd(limit),
        // Statements already closed keep their dates.
        effectiveFrom: moved ? _nextClose(closing) : null,
      ),
    );
  }

  /// The first close on [day] of the month after today.
  BusinessDate _nextClose(int day) {
    final today = _clock.today();
    for (final month in [today.month, today.month + 1]) {
      final last = DateTime.utc(today.year, month + 1, 0);
      final close = DateTime.utc(last.year, last.month, min(day, last.day));
      if (close.isAfter(_date(today))) return _day(close);
    }
    throw StateError('No close ahead.');
  }

  @override
  Future<void> moveClose(
    ui.Account card,
    DateTime scheduled,
    DateTime closesOn,
  ) async {
    final id = _account(card.id).id;
    final terms = _store.cardTerms(id);
    if (terms == null) {
      throw const AppFailure(FailureKind.rejected, 'card.no-terms');
    }
    // Still due when that statement was, also when it was moved before.
    final close = _day(scheduled);
    var dueOn = terms.cycleFor(close).dueOn;
    for (final o in terms.overrides) {
      if (o.scheduledClose == close) dueOn = o.dueOn;
    }
    await _cards.overrideCycle(
      OverrideCardCycle(
        operation: _op(),
        cardId: id,
        expectedVersion: terms.version,
        scheduledClose: close,
        closesOn: _day(closesOn),
        dueOn: dueOn,
      ),
    );
  }

  @override
  Future<void> setOpening(ui.Account account, int opening) async {
    final a = _account(account.id);
    await _books.setOpeningBalance(
      SetOpeningBalance(
        operation: _op(),
        postingId: PublicId.generate(),
        reversalId: PublicId.generate(),
        accountId: a.id,
        expectedVersion: a.rulesVersion,
        amount: _in(a, opening),
      ),
    );
  }

  @override
  Future<void> removeAccount(ui.Account account) async {
    final a = _account(account.id);
    if (a.state != AccountState.active) return;
    await _books.changeAccountState(
      ChangeAccountState(
        operation: _op(),
        accountId: a.id,
        expectedVersion: a.version,
        change: AccountStateChange.archive,
      ),
    );
  }

  Account? _findAccount(String id) {
    for (final a in _store.accounts(_workspace)) {
      if (a.id.value == id) return a;
    }
    return null;
  }

  Account _account(String id) {
    final account = _findAccount(id);
    if (account == null) {
      throw const AppFailure(FailureKind.notFound, 'account.not-found');
    }
    return account;
  }

  static AccountRef _ref(Account a) => AccountRef(a.id, a.rulesVersion);

  // Catalogs.

  @override
  Future<void> saveCategory(ui.Category? before, ui.Category after) async {
    final kind = after.income ? CategoryKind.income : CategoryKind.expense;
    final parent = _categoryId(after.parent, kind);
    if (before == null) {
      final id = PublicId.generate();
      await _catalog(
        CatalogType.category,
        CreateEntry(id, after.name, kind: kind, parentId: parent),
      );
      await _saveLook(id, after);
      return;
    }
    var row = await _category(before.name, income: before.income);
    if (after.name != row.name) {
      await _catalog(
        CatalogType.category,
        RenameEntry(row.id, row.version, after.name),
      );
      row = _categoryById(row.id);
    }
    if (parent != row.parentId) {
      await _catalog(
        CatalogType.category,
        MoveCategory(row.id, row.version, parent),
      );
      row = _categoryById(row.id);
    }
    if (after.archived != row.archived) {
      await _catalog(
        CatalogType.category,
        ArchiveEntry(row.id, row.version, archived: after.archived),
      );
    }
    if (after.icon != before.icon || after.color != before.color) {
      await _saveLook(row.id, after);
    }
  }

  Future<void> _saveLook(PublicId id, ui.Category c) =>
      _looks.save(id.value, (icon: c.icon, color: c.color.toARGB32()));

  @override
  Future<void> mergeCategory(ui.Category from, ui.Category into) async {
    final source = await _category(from.name, income: from.income);
    final target = await _category(into.name, income: into.income);
    await _catalog(
      CatalogType.category,
      MergeEntry(source.id, source.version, target.id, target.version),
    );
  }

  @override
  Future<void> relabel(String from, String to, {required bool merchant}) async {
    final labels = _labels(merchant: merchant);
    final source = labels.where((l) => l.name == from).firstOrNull;
    if (source == null) return;
    final target = labels.where((l) => l.name == to).firstOrNull;
    final CatalogChange change;
    if (to.isEmpty) {
      change = ArchiveEntry(source.id, source.version, archived: true);
    } else if (target != null) {
      change = MergeEntry(source.id, source.version, target.id, target.version);
    } else {
      change = RenameEntry(source.id, source.version, to);
    }
    await _catalog(merchant ? CatalogType.merchant : CatalogType.tag, change);
  }
}
