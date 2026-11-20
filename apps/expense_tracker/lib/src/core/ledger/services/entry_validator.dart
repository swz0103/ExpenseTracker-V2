import '../models/models.dart';
import 'entry_validation_failure.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/holding_repository.dart';
import 'entry_query_service.dart';

/// What the ledger will not keep, said before it is asked: every form
/// that writes an entry checks it here.
final class EntryValidator {
  EntryValidator({
    required this._entries,
    required this._accounts,
    required this._holdings,
    required EntryQueryService entryQueryService,
  }) : _entryQueries = entryQueryService;

  final EntryReader _entries;
  final AccountReader _accounts;
  final HoldingReader _holdings;
  final EntryQueryService _entryQueries;

  /// Why [e] cannot be kept; null when it can. [replacing] is the entry
  /// [e] edits, whose own shares and refund do not count against it. An
  /// import checks the shares of its trades together ([holdings] false).
  EntryValidationFailure? validate(
    Entry e, {
    Entry? replacing,
    bool holdings = true,
  }) {
    final currency = _accounts.resolve(e.account).currency;
    final trade = e.type == EntryType.buy || e.type == EntryType.sell;
    final stock = e.type == EntryType.dividend && e.shares != 0;
    if (e.amount <= 0 && !stock) return MissingAmount(trade: trade);
    final transfer = e.type == EntryType.transfer;
    if (transfer && e.account == e.to) return const SameAccountTransfer();
    final cash = e.type == EntryType.expense || e.type == EntryType.income;
    if (cash && currency != homeCode && e.home == null) {
      return const MissingHomeAmount();
    }
    if (transfer && _accounts.resolve(e.account).kind == AccountKind.card) {
      return const CardTransferOut();
    }
    if (transfer && e.fee > 0 && currency != homeCode) {
      return const ForeignTransferFee();
    }
    final to = transfer ? _accounts.resolve(e.to ?? '') : null;
    if (to != null && to.kind == AccountKind.card && e.fee > 0) {
      return const CardPaymentFee();
    }
    if (to != null && to.currency != currency && e.received == null) {
      return const MissingReceivedAmount();
    }
    if (to != null && currency != homeCode && to.kind == AccountKind.card) {
      return const ForeignCardPayment();
    }
    if (e.isInvestment && currency != homeCode) {
      return const ForeignInvestment();
    }
    if (e.isInvestment && _accounts.resolve(e.account).kind.isDebt) {
      return const InvestmentFromDebt();
    }
    if (e.isReduction) {
      final held = _heldBefore(e.holding ?? '', replacing);
      if (-e.shares > held) return ReductionExceedsHolding(held);
    }
    if (e.type == EntryType.dividend && !e.isReduction && e.tax > e.amount) {
      return const TaxExceedsDividend();
    }
    if (e.isInvestment && e.holding == null) return const MissingHolding();
    if (trade && e.shares <= 0) return const MissingShares();
    if (holdings &&
        (e.type == EntryType.sell || e.isReduction) &&
        !holdsWith([e], replacing: replacing)) {
      return const SaleExceedsHolding();
    }
    final original = e.refundOf == null ? null : _entries.byId(e.refundOf!);
    if (original != null &&
        _accounts.resolve(original.account).kind == AccountKind.card &&
        e.account != original.account) {
      return const RefundToOtherAccount();
    }
    if (original != null) {
      final left = _entryQueries.refundable(original);
      final own = replacing?.refundOf == e.refundOf ? replacing!.amount : 0;
      if (e.amount > left + own) return RefundExceedsRemaining(left);
    }
    return null;
  }

  /// The shares of [code] held before [replacing], when that one is a
  /// reduction of them.
  int _heldBefore(String code, Entry? replacing) {
    final held = _holdings.byCode(code)?.shares ?? 0;
    if (replacing == null ||
        !replacing.isReduction ||
        replacing.holding != code) {
      return held;
    }
    return held - replacing.shares;
  }

  /// Whether [extra] can join the entries, in place of [replacing]: none
  /// of their trades sells more shares than are held by then.
  bool holdsWith(List<Entry> extra, {Entry? replacing}) {
    return _holdings.holdsWith([
      for (final e in _entries.all)
        if (replacing == null || e.id != replacing.id) e,
      ...extra,
    ]);
  }
}
