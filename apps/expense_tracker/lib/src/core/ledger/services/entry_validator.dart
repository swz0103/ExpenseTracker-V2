import '../../text/amounts.dart';
import '../models/models.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/holding_repository.dart';
import '../services/entry_query_service.dart';

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

  /// Why [e] cannot be kept, in words for the person; null when it can.
  /// [replacing] is the entry [e] edits, whose own shares and refund do
  /// not count against it. An import checks the shares of its trades
  /// together ([holdings] false).
  String? problemWith(Entry e, {Entry? replacing, bool holdings = true}) {
    final currency = _accounts.resolve(e.account).currency;
    final trade = e.type == EntryType.buy || e.type == EntryType.sell;
    final stock = e.type == EntryType.dividend && e.shares != 0;
    if (e.amount <= 0 && !stock) return trade ? '請輸入股數和成交價' : '請輸入金額';
    final transfer = e.type == EntryType.transfer;
    if (transfer && e.account == e.to) return '轉出與轉入不能是同一個帳戶';
    final cash = e.type == EntryType.expense || e.type == EntryType.income;
    if (cash && currency != homeCode && e.home == null) {
      return '還沒有匯率，請輸入折合台幣的金額';
    }
    if (transfer && _accounts.resolve(e.account).kind == AccountKind.card) {
      return '信用卡不能轉出，請記成支出';
    }
    if (transfer && e.fee > 0 && currency != homeCode) {
      return '外幣帳戶轉出時不能記手續費';
    }
    final to = transfer ? _accounts.resolve(e.to ?? '') : null;
    if (to != null && to.kind == AccountKind.card && e.fee > 0) {
      return '繳卡費不記手續費，請另記一筆支出';
    }
    if (to != null && to.currency != currency && e.received == null) {
      return '還沒有匯率，請輸入轉入金額';
    }
    if (to != null && currency != homeCode && to.kind == AccountKind.card) {
      return '外幣帳戶不能直接繳卡費';
    }
    if (e.isInvestment && currency != homeCode) return '投資請用新台幣帳戶';
    if (e.isInvestment && _accounts.resolve(e.account).kind.isDebt) {
      return '買賣股票要用現金或銀行帳戶付款';
    }
    if (e.isReduction) {
      final held = _heldBefore(e.holding ?? '', replacing);
      if (-e.shares > held) return '減少的股數超過持股（${groupDigits(held)} 股）';
    }
    if (e.type == EntryType.dividend && !e.isReduction && e.tax > e.amount) {
      return '補充保費不能超過股息';
    }
    if (e.isInvestment && e.holding == null) return '請選擇投資標的';
    if (trade && e.shares <= 0) return '請輸入股數';
    if (holdings &&
        (e.type == EntryType.sell || e.isReduction) &&
        !holdsWith([e], replacing: replacing)) {
      return '賣出股數超過持股';
    }
    final original = e.refundOf == null ? null : _entries.byId(e.refundOf!);
    if (original != null &&
        _accounts.resolve(original.account).kind == AccountKind.card &&
        e.account != original.account) {
      return '信用卡消費的退款要退回同一張卡';
    }
    if (original != null) {
      final left = _entryQueries.refundable(original);
      final own = replacing?.refundOf == e.refundOf ? replacing!.amount : 0;
      if (e.amount > left + own) return '超過可退金額 ${groupDigits(left)}';
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
