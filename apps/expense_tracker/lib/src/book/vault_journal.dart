import 'dart:convert';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:budgets/budgets.dart';
import 'package:categories/categories.dart';
import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/painting.dart' show Color;
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:ledger_vault/ledger_vault.dart';
import 'package:market_data/market_data.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:reports/reports.dart';

import '../model/ledger.dart' as ui;
import 'journal.dart';
import 'looks.dart';

part 'vault_investments.dart';

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
  Future<ui.Ledger> load() async {
    if (_store.categories(_workspace).isEmpty) await _addStarters();
    final looks = _looks.all();
    final categories = {for (final c in _store.categories(_workspace)) c.id: c};
    final tags = {for (final t in _store.tags(_workspace)) t.id: t};
    final merchants = {for (final m in _store.merchants(_workspace)) m.id: m};
    final reversed = _store.reversedPostings(_workspace);
    final instalments = _store.instalmentPurchases(_workspace);
    final confirmed = _recurringLinks();
    final postingTags = _store.postingTags(_workspace);
    final postingMerchants = _store.postingMerchants(_workspace);
    final notes = _store.postingNotes(_workspace);
    final homes = _store.postingHomeValues(_workspace);
    if (_rates.isEmpty) _rates.addAll(_keptRates());
    String nameOf(PublicId id) =>
        _live(categories, id, (c) => c.replacementId)?.name ?? '';
    String merchantOf(PublicId? id) {
      if (id == null) return '';
      final merchant = _live(merchants, id, (m) => m.replacementId);
      return merchant == null || merchant.archived ? '' : merchant.name;
    }

    final openings = <PublicId, int>{};
    final entries = <ui.Entry>[];
    for (final posting in _store.workspacePostings(_workspace)) {
      if (reversed.contains(posting.id)) continue;
      if (posting.kind == PostingKind.opening) {
        for (final leg in posting.legs) {
          final id = leg.account.id;
          openings[id] = (openings[id] ?? 0) + _int(leg.amount);
        }
        continue;
      }
      final tagNames = <String>[];
      for (final id in postingTags[posting.id] ?? const <PublicId>[]) {
        final tag = _live(tags, id, (t) => t.replacementId);
        if (tag != null && !tag.archived) tagNames.add(tag.name);
      }
      final entry = _entryOf(
        posting,
        category: nameOf,
        tags: tagNames,
        merchant: merchantOf(postingMerchants[posting.id]),
        note: notes[posting.id] ?? '',
        home: homes[posting.id],
        recurring: confirmed[posting.id]?.value,
        installments: instalments.contains(posting.id)
            ? _store.installments(posting.id).length
            : 0,
      );
      if (entry != null) entries.add(entry);
    }
    final (trades, holdings) = _investments();
    entries.addAll(trades);
    final today = _clock.today();
    final applying = _applying(categories);
    final accounts = _store.accounts(_workspace);
    return ui.Ledger(
      today: DateTime.utc(today.year, today.month, today.day),
      accounts: [
        for (final a in accounts)
          _accountOf(a, openings[a.id] ?? 0, looks[a.id.value]),
      ],
      cardDues: _cardDues(accounts, today),
      categories: [
        for (final c in categories.values)
          if (c.replacementId == null)
            _categoryOf(c, categories, looks[c.id.value]),
      ],
      entries: entries,
      holdings: holdings,
      budgets: [
        for (final MapEntry(key: category, value: plan) in applying.entries)
          ui.Budget(
            category == null ? ui.Ledger.allSpending : nameOf(category),
            _int(plan.limit),
            warning: plan.warningPercent,
          ),
      ],
      rates: _rates,
      recurring: [
        for (final (template, active) in _store.recurringTemplates(_workspace))
          _recurringOf(
            template,
            active: active,
            category: nameOf,
            merchant: merchantOf,
          ),
      ],
      journal: this,
    );
  }

  /// The screens' entry for [posting]; null for kinds not shown yet, such
  /// as trades.
  ui.Entry? _entryOf(
    Posting posting, {
    required String Function(PublicId id) category,
    required List<String> tags,
    required String merchant,
    required String note,
    required int installments,
    Money? home,
    String? recurring,
  }) {
    final date = DateTime.utc(
      posting.date.year,
      posting.date.month,
      posting.date.day,
    );
    final principal = [
      for (final leg in posting.legs)
        if (leg.role == LegRole.principal) leg,
    ];
    final fee = posting.legs
        .where((leg) => leg.role == LegRole.fee)
        .fold(0, (sum, leg) => sum + _int(leg.amount).abs());
    switch (posting.kind) {
      case PostingKind.income || PostingKind.expense || PostingKind.refund:
        final income = posting.kind != PostingKind.expense;
        final parts = [
          for (final a in posting.allocations)
            (category(a.categoryId), _int(a.amount)),
        ];
        final amount = posting.legs.fold(
          0,
          (sum, leg) => sum + _int(leg.amount),
        );
        final fallback = income ? '其他收入' : ui.Ledger.feeCategory;
        return ui.Entry(
          id: posting.id.value,
          date: date,
          type: income ? ui.EntryType.income : ui.EntryType.expense,
          amount: amount.abs(),
          account: posting.legs.first.account.id.value,
          category: parts.isEmpty ? fallback : parts.first.$1,
          note: note,
          merchant: merchant,
          tags: tags,
          parts: parts.length > 1 ? parts : const [],
          refundOf: posting.refundOf?.value,
          installments: installments,
          recurring: recurring,
          home: home == null ? null : _int(home),
        );
      case PostingKind.transfer:
        final from = principal.where((leg) => _int(leg.amount) < 0);
        final to = principal.where((leg) => _int(leg.amount) > 0);
        if (from.isEmpty || to.isEmpty) return null;
        final sent = from.first.amount;
        final arrived = to.first.amount;
        return ui.Entry(
          id: posting.id.value,
          date: date,
          type: ui.EntryType.transfer,
          amount: _int(sent).abs(),
          account: from.first.account.id.value,
          to: to.first.account.id.value,
          category: '轉帳',
          note: note,
          fee: fee,
          received: arrived.currency == sent.currency ? null : _int(arrived),
        );
      default:
        return null;
    }
  }

  /// What is still to pay on each card's last closed statement, as the
  /// ledger's own billing works it out.
  Map<String, int> _cardDues(List<Account> accounts, BusinessDate today) {
    final dues = <String, int>{};
    for (final a in accounts) {
      if (a.kind != AccountKind.creditCard) continue;
      final terms = _store.cardTerms(a.id);
      if (terms == null) continue;
      final closed = terms.cycleFor(today).startsAfter;
      final due = _int(_store.statement(a.id, closed).remainingDue);
      dues[a.id.value] = due < 0 ? 0 : due;
    }
    return dues;
  }

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

  ui.Account _accountOf(Account a, int opening, Look? look) {
    final card = a.kind == AccountKind.creditCard;
    final terms = card ? _store.cardTerms(a.id) : null;
    final limit = terms?.limit;
    return ui.Account(
      a.id.value,
      a.name,
      _uiKind(a.kind),
      opening,
      icon: look?.icon,
      closingDay: terms?.closingDay,
      dueDay: terms?.dueDay,
      limit: limit == null ? null : _int(limit),
      archived: a.state != AccountState.active,
      inNetWorth: a.includeInNetWorth,
      currency: a.currency.code,
    );
  }

  ui.Category _categoryOf(Category c, Map<PublicId, Category> all, Look? look) {
    final income = c.kind == CategoryKind.income;
    final parentId = c.parentId;
    final starter = _starters.where((s) => s.$1 == c.name).firstOrNull;
    final icon = look?.icon ?? starter?.$2 ?? (income ? 'income' : 'other');
    final hash = c.name.codeUnits.fold(0, (h, u) => h + u);
    final shade = _palette[hash % _palette.length];
    final color = look?.color ?? starter?.$3 ?? shade;
    return ui.Category(
      c.name,
      icon,
      Color(color),
      income: income,
      parent: parentId == null ? null : all[parentId]?.name,
      archived: c.archived,
    );
  }

  Future<void> _addStarters() async {
    for (final (name, icon, color, income) in _starters) {
      final id = PublicId.generate();
      final kind = income ? CategoryKind.income : CategoryKind.expense;
      await _catalog(CatalogType.category, CreateEntry(id, name, kind: kind));
      await _looks.save(id.value, (icon: icon, color: color));
    }
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
    if (_store.hasPosting(id)) await _note(id, e.note);
    return id;
  }

  Future<void> _spend(
    PublicId id,
    ui.Entry e,
    Account account,
    BusinessDate day,
  ) async {
    final shares = await _shares(e, income: false, account: account);
    final tags = await _tags(e.tags);
    final merchant = await _merchant(e.merchant);
    if (account.kind != AccountKind.creditCard) {
      await _books.recordCashFlow(
        RecordCashFlow(
          operation: _op(),
          postingId: id,
          flow: CashFlow.expense,
          account: _ref(account),
          date: day,
          amount: _in(account, e.amount),
          allocations: shares,
          tags: tags,
          merchant: merchant,
          homeValue: _homeOf(account, e),
        ),
      );
      return;
    }
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
    await _books.recordCashFlow(
      RecordCashFlow(
        operation: _op(),
        postingId: id,
        flow: CashFlow.income,
        account: _ref(account),
        date: day,
        amount: _in(account, e.amount),
        allocations: shares,
        tags: await _tags(e.tags),
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
    final posting = _store
        .workspacePostings(_workspace)
        .where((p) => p.id == original)
        .firstOrNull;
    final parts = posting?.allocations ?? const <Allocation>[];
    if (parts.isEmpty) return const [];
    final total = parts.fold(0, (sum, a) => sum + _int(a.amount));
    var left = amount;
    final shares = <CategoryShare>[];
    for (final (i, a) in parts.indexed) {
      final value = i == parts.length - 1
          ? left
          : (amount * _int(a.amount) / total).round();
      left -= value;
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
    if (fee != null) {
      await _books.recordCashFlow(
        RecordCashFlow(
          operation: _op(),
          postingId: PublicId.generate(),
          flow: CashFlow.expense,
          account: _ref(from),
          date: day,
          amount: fee,
          allocations: feeShares,
        ),
      );
    }
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

  static const _linkKind = '${appEventPrefix}recurring-link';

  /// The recurring item behind each booking: the ones the ledger
  /// confirmed, and edited bookings the app linked again.
  Map<PublicId, PublicId> _recurringLinks() {
    final links = _store.recurringByPosting(_workspace);
    final rows = _vault.store.select(
      'SELECT payload FROM events WHERE workspace = ? AND kind = ? '
      'ORDER BY seq',
      [_workspace.toString(), _linkKind],
    );
    for (final row in rows) {
      final json =
          jsonDecode(row['payload']! as String) as Map<String, Object?>;
      final posting = PublicId.parse(json['posting']! as String);
      links[posting] = PublicId.parse(json['template']! as String);
    }
    return links;
  }

  /// Keeps an edited booking linked to [template]: the ledger's own
  /// confirmation stays with the entry it replaced.
  Future<void> _linkRecurring(PublicId posting, PublicId template) {
    final payload = jsonEncode({
      'posting': posting.value,
      'template': template.value,
    });
    return _books.exclusive(() async {
      await _vault.store.write((t) async {
        t.append(
          id: PublicId.generate(),
          workspace: _workspace,
          kind: _linkKind,
          payload: payload,
        );
      });
    });
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
    await removeEntry(before);
    return (await _add(after)).value;
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
        account.kind == AccountKind.creditCard ||
        account.currency != homeCurrency) {
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
          amount: _ntd(e.amount),
          date: day,
          allocations: await _shares(e, income: income),
          tags: await _tags(e.tags),
          merchant: await _merchant(e.merchant),
        ),
      );
    } on AppFailure catch (error) {
      if (error.diagnostic.startsWith('recurring.')) return false;
      rethrow;
    }
    return true;
  }

  // Prices and rates; trades are in vault_investments.dart.

  static const _ratesKind = '${appEventPrefix}rates';

  /// The board last fetched, kept so foreign accounts are valued offline.
  Map<String, double> _keptRates() {
    final rows = _vault.store.select(
      'SELECT payload FROM events WHERE workspace = ? AND kind = ? '
      'ORDER BY seq DESC LIMIT 1',
      [_workspace.toString(), _ratesKind],
    );
    if (rows.isEmpty) return const {};
    final json =
        jsonDecode(rows.single['payload']! as String) as Map<String, Object?>;
    final rates = json['rates']! as Map<String, Object?>;
    return {
      for (final MapEntry(:key, :value) in rates.entries)
        key: (value! as num).toDouble(),
    };
  }

  /// Fetches 臺灣銀行's board: the spot buying rate of each currency, what
  /// a foreign balance is worth in NT$. Returns whether any rate changed.
  Future<bool> refreshRates() async {
    final market = _market;
    if (market == null) return false;
    final board = (await market.bankRates()).value;
    if (board == null) return false;
    final fetched = <String, double>{};
    for (final MapEntry(key: code, value: row) in board.rates.entries) {
      final rate = row.valuation;
      if (rate != null) fetched[code] = rate.numerator / rate.denominator;
    }
    if (fetched.isEmpty || mapEquals(fetched, _rates)) return false;
    _rates
      ..clear()
      ..addAll(fetched);
    final payload = jsonEncode({'asOf': '${board.asOf}', 'rates': fetched});
    await _books.exclusive(() async {
      await _vault.store.write((t) async {
        t.append(
          id: PublicId.generate(),
          workspace: _workspace,
          kind: _ratesKind,
          payload: payload,
        );
      });
    });
    return true;
  }

  /// Fetches the latest close of every instrument still held, for the
  /// holdings' value; a TWSE listing not found there is tried on TPEx.
  /// Returns whether any price changed.
  Future<bool> refreshQuotes() async {
    final market = _market;
    if (market == null) return false;
    final held = <String, InvestmentInstrument>{};
    for (final account in _store.investmentAccounts(_workspace)) {
      for (final id in _store.positions(account.id)) {
        final instrument = _store.instrument(id);
        if (instrument != null) held[instrument.symbol] = instrument;
      }
    }
    var changed = false;
    for (final MapEntry(key: symbol, value: instrument) in held.entries) {
      try {
        var result = await market.stockClose(instrument);
        if (result.state == MarketState.missing &&
            instrument.marketCode == 'TWSE') {
          result = await market.stockClose(
            InvestmentInstrument(
              id: instrument.id,
              kind: instrument.kind,
              marketCode: 'TPEX',
              symbol: instrument.symbol,
              name: instrument.name,
              tradingCurrency: instrument.tradingCurrency,
            ),
          );
        }
        final close = result.value;
        final price = close == null
            ? null
            : double.tryParse(close.decimalPrice);
        if (price == null || _quotes[symbol] == price) continue;
        _quotes[symbol] = price;
        changed = true;
      } on Object {
        continue;
      }
    }
    return changed;
  }

  // Budgets and recurring items.

  /// The budget plans that apply this month, by category (null for all
  /// spending): of several, the one that started last.
  Map<PublicId?, BudgetPlan> _applying(Map<PublicId, Category> categories) {
    final today = _clock.today();
    final now = today.year * 12 + today.month;
    final plans = <PublicId?, BudgetPlan>{};
    for (final plan in _store.budgetPlans(_workspace)) {
      final start = plan.month.year * 12 + plan.month.month;
      if (start > now || (start < now && !plan.repeats)) continue;
      final category = plan.categoryId;
      final key = category == null
          ? null
          : _live(categories, category, (c) => c.replacementId)?.id;
      plans[key] = plan;
    }
    return plans;
  }

  Map<PublicId, Category> _categoryMap() => {
    for (final c in _store.categories(_workspace)) c.id: c,
  };

  @override
  Future<void> setBudget(ui.Budget budget) async {
    final category = budget.category == ui.Ledger.allSpending
        ? null
        : (await _category(budget.category, income: false)).id;
    final current = _applying(_categoryMap())[category];
    final today = _clock.today();
    await _planning.setBudget(
      SetBudget(
        operation: _op(),
        budgetId: current?.id ?? PublicId.generate(),
        expectedVersion: current?.version ?? 0,
        month: current?.month ?? ReportMonth(today.year, today.month),
        limit: _ntd(budget.limit),
        categoryId: category,
        warningPercent: budget.warning,
        repeats: true,
      ),
    );
  }

  @override
  Future<void> removeBudget(String category) async {
    final all = category == ui.Ledger.allSpending;
    final id = all ? null : _categoryId(category, CategoryKind.expense);
    if (!all && id == null) return;
    final categories = _categoryMap();
    for (final plan in _store.budgetPlans(_workspace)) {
      final planned = plan.categoryId;
      final key = planned == null
          ? null
          : _live(categories, planned, (c) => c.replacementId)?.id;
      if (key != id) continue;
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
        accountId: _account(item.account).id,
        label: item.name,
        amount: _ntd(item.income ? item.amount : -item.amount),
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
    await _cards.setTerms(
      SetCardTerms(
        operation: _op(),
        cardId: card,
        expectedVersion: current?.version ?? 0,
        closingDay: closing,
        dueDay: due,
        limit: limit == null || limit <= 0 ? null : _ntd(limit),
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

  Future<void> _catalog(CatalogType type, CatalogChange change) async {
    await _books.changeCatalog(
      ChangeCatalog(operation: _op(), catalog: type, change: change),
    );
  }

  Category _categoryById(PublicId id) =>
      _store.categories(_workspace).firstWhere((c) => c.id == id);

  PublicId? _categoryId(String? name, CategoryKind kind) {
    if (name == null) return null;
    for (final c in _store.categories(_workspace)) {
      if (c.replacementId == null && c.kind == kind && c.name == name) {
        return c.id;
      }
    }
    return null;
  }

  /// The live category [name] of the kind, made when there is none.
  Future<Category> _category(String name, {required bool income}) async {
    final kind = income ? CategoryKind.income : CategoryKind.expense;
    final found = _categoryId(name, kind);
    if (found != null) return _categoryById(found);
    final id = PublicId.generate();
    await _catalog(CatalogType.category, CreateEntry(id, name, kind: kind));
    return _categoryById(id);
  }

  /// The categories of [e], counted in the currency of the [account] it
  /// is booked in; a foreign entry is never split.
  Future<List<CategoryShare>> _shares(
    ui.Entry e, {
    required bool income,
    Account? account,
  }) {
    final currency = account?.currency ?? homeCurrency;
    final parts = e.parts.isNotEmpty && currency == homeCurrency
        ? e.parts
        : [if (e.category.isNotEmpty) (e.category, e.amount)];
    return _sharesOf(parts, income: income, currency: currency);
  }

  /// The category of a transfer's [fee], none without one.
  Future<List<CategoryShare>> _feeShares(int fee) async {
    if (fee <= 0) return const [];
    return _sharesOf([(ui.Ledger.feeCategory, fee)], income: false);
  }

  Future<List<CategoryShare>> _sharesOf(
    List<(String, int)> parts, {
    required bool income,
    Currency? currency,
  }) async {
    final shares = <CategoryShare>[];
    for (final (name, amount) in parts) {
      final c = await _category(name, income: income);
      final money = Money(currency ?? homeCurrency, BigInt.from(amount));
      shares.add(CategoryShare(c.id, c.version, money));
    }
    return shares;
  }

  List<_Label> _labels({required bool merchant}) => merchant
      ? [
          for (final m in _store.merchants(_workspace))
            if (m.replacementId == null)
              (id: m.id, name: m.name, version: m.version),
        ]
      : [
          for (final t in _store.tags(_workspace))
            if (t.replacementId == null)
              (id: t.id, name: t.name, version: t.version),
        ];

  /// The live tag or merchant [name], made or brought back when needed.
  Future<_Label> _label(String name, {required bool merchant}) async {
    final type = merchant ? CatalogType.merchant : CatalogType.tag;
    _Label? find() =>
        _labels(merchant: merchant).where((l) => l.name == name).firstOrNull;
    final found = find();
    if (found == null) {
      await _catalog(type, CreateEntry(PublicId.generate(), name));
    } else if (_archived(found.id, merchant: merchant)) {
      await _catalog(
        type,
        ArchiveEntry(found.id, found.version, archived: false),
      );
    } else {
      return found;
    }
    final made = find();
    if (made == null) throw StateError('「$name」was not kept.');
    return made;
  }

  bool _archived(PublicId id, {required bool merchant}) => merchant
      ? _store.merchants(_workspace).any((m) => m.id == id && m.archived)
      : _store.tags(_workspace).any((t) => t.id == id && t.archived);

  Future<List<TagSelection>> _tags(List<String> names) async {
    final selections = <TagSelection>[];
    for (final name in {...names}) {
      final tag = await _label(name, merchant: false);
      selections.add(TagSelection(tag.id, tag.version));
    }
    return selections;
  }

  Future<MerchantSelection?> _merchant(String name) async {
    if (name.isEmpty) return null;
    final merchant = await _label(name, merchant: true);
    return MerchantSelection(merchant.id, merchant.version);
  }
}

/// Follows merges from [id] to the row that replaced it.
T? _live<T>(Map<PublicId, T> rows, PublicId id, PublicId? Function(T) next) {
  var row = rows[id];
  for (var hops = 0; row != null && hops < 32; hops++) {
    final replacement = next(row);
    if (replacement == null) return row;
    row = rows[replacement];
  }
  return row;
}

PublicId? _parse(String id) {
  try {
    return PublicId.parse(id);
  } on Object {
    return null;
  }
}

Money _ntd(int amount) => Money(homeCurrency, BigInt.from(amount));

/// [amount] in the smallest unit of [account]'s currency.
Money _in(Account account, int amount) =>
    Money(account.currency, BigInt.from(amount));

/// What a foreign entry [e] in [account] was worth in NT$, which the
/// ledger keeps for reports, budgets and net worth; none for NT$.
Money? _homeOf(Account account, ui.Entry e) {
  if (account.currency == homeCurrency) return null;
  final home = e.home;
  if (home == null || home <= 0) {
    throw const AppFailure(FailureKind.rejected, 'app.home-value');
  }
  return _ntd(home);
}

/// What reached [to] when it is kept in another currency than [from].
Money? _receivedIn(Account from, Account to, ui.Entry e) {
  if (from.currency == to.currency) return null;
  final received = e.received;
  if (received == null || received <= 0) {
    throw const AppFailure(FailureKind.rejected, 'app.received');
  }
  return _in(to, received);
}

/// A transfer's fee is counted as NT$ spending, so only an NT$ account
/// pays one.
void _requireHomeFee(Account from, ui.Entry e) {
  if (e.fee > 0 && from.currency != homeCurrency) {
    throw const AppFailure(FailureKind.rejected, 'app.foreign-fee');
  }
}

int _int(Money money) => money.minorUnits.toInt();

BusinessDate _day(DateTime date) =>
    BusinessDate(date.year, date.month, date.day);

DateTime _date(BusinessDate day) => DateTime.utc(day.year, day.month, day.day);

/// Whole shares in a quantity written as decimal text.
int _whole(Object? quantity) =>
    quantity is String ? int.parse(quantity.split('.').first) : 0;

/// [amount] over [shares] to six decimals: the ledger takes a gross one
/// unit off price times quantity, which this stays within up to two
/// million shares.
String _unitPrice(int amount, int shares) {
  final count = BigInt.from(shares < 1 ? 1 : shares);
  final doubled = BigInt.from(amount) * BigInt.from(2000000) + count;
  final scaled = doubled ~/ (count * BigInt.two);
  final digits = scaled.toString().padLeft(7, '0');
  final whole = digits.substring(0, digits.length - 6);
  final fraction = digits
      .substring(digits.length - 6)
      .replaceAll(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

AccountKind _kind(ui.AccountKind kind) => switch (kind) {
  ui.AccountKind.cash => AccountKind.cash,
  ui.AccountKind.bank => AccountKind.bank,
  ui.AccountKind.wallet => AccountKind.eWallet,
  ui.AccountKind.card => AccountKind.creditCard,
  ui.AccountKind.loan => AccountKind.loan,
  ui.AccountKind.receivable => AccountKind.receivable,
};

ui.AccountKind _uiKind(AccountKind kind) => switch (kind) {
  AccountKind.cash => ui.AccountKind.cash,
  AccountKind.bank || AccountKind.manual => ui.AccountKind.bank,
  AccountKind.eWallet => ui.AccountKind.wallet,
  AccountKind.creditCard => ui.AccountKind.card,
  AccountKind.loan => ui.AccountKind.loan,
  AccountKind.receivable => ui.AccountKind.receivable,
};
