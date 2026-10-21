import 'amounts.dart';
import 'ledger.dart';

/// What the ledger will not keep, said before it is asked: every form
/// that writes an entry checks it here.
extension EntryChecks on Ledger {
  /// Why [e] cannot be kept, in words for the person; null when it can.
  /// [replacing] is the entry [e] edits, whose own shares and refund do
  /// not count against it.
  String? problemWith(Entry e, {Entry? replacing}) {
    final currency = account(e.account).currency;
    final trade = e.type == EntryType.buy || e.type == EntryType.sell;
    final stock = e.type == EntryType.dividend && e.shares != 0;
    if (e.amount <= 0 && !stock) return trade ? '請輸入股數和成交價' : '請輸入金額';
    final transfer = e.type == EntryType.transfer;
    if (transfer && e.account == e.to) return '轉出與轉入不能是同一個帳戶';
    final cash = e.type == EntryType.expense || e.type == EntryType.income;
    if (cash && currency != homeCode && e.home == null) {
      return '還沒有匯率，請輸入折合台幣的金額';
    }
    final to = transfer ? account(e.to ?? '') : null;
    if (to != null && to.currency != currency && e.received == null) {
      return '還沒有匯率，請輸入轉入金額';
    }
    if (to != null && currency != homeCode && to.kind == AccountKind.card) {
      return '外幣帳戶不能直接繳卡費';
    }
    if (e.isInvestment && currency != homeCode) return '投資請用新台幣帳戶';
    if (e.isReduction) {
      final held = _heldBefore(e.holding ?? '', replacing);
      if (-e.shares > held) return '減少的股數超過持股（${groupDigits(held)} 股）';
    }
    if (e.type == EntryType.dividend && !e.isReduction && e.tax > e.amount) {
      return '補充保費不能超過股息';
    }
    if (e.isInvestment && e.holding == null) return '請選擇投資標的';
    if (trade && e.shares <= 0) return '請輸入股數';
    final original = e.refundOf == null ? null : byId(e.refundOf!);
    if (original != null) {
      final left = refundable(original);
      final own = replacing?.refundOf == e.refundOf ? replacing!.amount : 0;
      if (e.amount > left + own) return '超過可退金額 ${groupDigits(left)}';
    }
    return null;
  }

  /// The shares of [code] held before [replacing], when that one is a
  /// reduction of them.
  int _heldBefore(String code, Entry? replacing) {
    final held = holding(code)?.shares ?? 0;
    if (replacing == null ||
        !replacing.isReduction ||
        replacing.holding != code) {
      return held;
    }
    return held - replacing.shares;
  }
}
