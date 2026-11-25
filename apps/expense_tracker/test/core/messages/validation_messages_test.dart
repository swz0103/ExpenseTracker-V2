import 'dart:io';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/messages/validation_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R12: too many shares is told as such', () {
    expect(validationMessage(const SharesTooLarge(maxShares)), '股數超過可記錄的上限');
  });

  /// Every reason the ledger refuses or warns, with the words the person
  /// reads (review 16: the validation message table).
  final table = <RecordIssue, String>{
    const MissingAmount(trade: true): '請輸入股數和成交價',
    const MissingAmount(trade: false): '請輸入金額',
    const AmountTooLarge(999999999): '金額超過可記錄的上限',
    const SharesTooLarge(1000): '股數超過可記錄的上限',
    const NegativeCharge(): '手續費和稅不能是負數',
    const DateNotMidnight(): '日期無效，請重新選擇',
    const UnknownAccount(): '找不到這個帳戶，請重新選擇',
    const MissingDestination(): '請選擇轉入帳戶',
    const SameAccountTransfer(): '轉出與轉入不能是同一個帳戶',
    const MissingHomeAmount(): '還沒有匯率，請輸入折合新台幣的金額',
    const CardTransferOut(): '信用卡不能轉出，請記成支出',
    const ForeignTransferFee(): '外幣帳戶轉出時不能記手續費',
    const CardPaymentFee(): '繳卡費不記手續費，請另記一筆支出',
    const MissingReceivedAmount(): '還沒有匯率，請輸入轉入金額',
    const ForeignCardPayment(): '外幣帳戶不能直接繳卡費',
    const ForeignInvestment(): '投資請用新台幣帳戶',
    const InvestmentFromDebt(): '買賣股票要用現金或銀行帳戶付款',
    const ReductionExceedsHolding(1500): '減少的股數超過持股（1,500 股）',
    const TaxExceedsDividend(): '補充保費不能超過股息',
    const MissingHolding(): '請選擇投資標的',
    const MissingShares(): '請輸入股數',
    const DayTradeNotSale(): '只有賣出可以是當日沖銷',
    const DateTooFarAhead(365): '日期最多只能排到 365 天後',
    const InvestmentPlanned(): '股票買賣與股息要在當天或之前記，不能預定',
    const SaleExceedsHolding(): '賣出股數超過持股',
    const SaleExceedsHolding(later: true): '這樣之後的賣出或減資會超過持股，請先改那一筆',
    const RefundToOtherAccount(): '信用卡消費的退款要退回同一張卡',
    const RefundOtherCurrency(): '退款要退回和原支出同一種幣別的帳戶',
    const EntryDeleted(): '這筆已刪除，可到「最近刪除」救回',
    const RefundExceedsRemaining(1200): '超過可退金額 1,200',
    const SplitPartNotPositive(): '拆分的每一項金額都要大於 0',
    const SplitTotalMismatch(1250): '拆分的金額要等於總額（差 1,250）',
    const InstallmentsOffCard(): '只有信用卡消費可以分期',
    const InstallmentsOutOfRange(36): '分期最多 36 期',
    const NegativeBalanceAfter(-2500): '扣款後餘額為負（-2,500）',
    const IntervalTooSmall(): '重複的間隔至少要 1',
    const DayOutOfRange(): '日期要在 1 到 31 日之間',
    const EndsBeforeStart(): '結束日不能早於開始日',
    const BlankName(): '請輸入帳戶名稱',
    const ClosingDayOutOfRange(): '結帳日要在 1 到 31 日之間',
    const DueDayOutOfRange(): '繳款日要在 1 到 31 日之間',
    const NegativeCreditLimit(): '信用額度不能是負數',
    const NegativeLoanRate(): '利率不能是負數',
    // 10000 hundredths of a percent is 100%.
    const LoanRateTooHigh(10000): '利率不能超過 100%，請確認是否打錯',
    const CloseMoveRefused(): '結帳日只能前後調整 7 天內，而且要在繳款日之前',
    const ArchivedOwing(): '還有沒結清的款項，結清後才能封存',
    const NegativeBudgetLimit(): '預算額度不能是負數',
    const WarningOutOfRange(): '提醒比例要在 1% 到 100% 之間',
  };

  test('every reason is said in its own words', () {
    for (final MapEntry(key: issue, value: words) in table.entries) {
      expect(validationMessage(issue), words, reason: '$issue');
    }
  });

  test('the table names every kind of reason the ledger has', () {
    final declared = RegExp(r'final class (\w+) extends RecordIssue')
        .allMatches(
          File('../../packages/ledger/entries/lib/rules/issues.dart')
              .readAsStringSync(),
        )
        .map((m) => m[1])
        .toSet();
    expect({for (final issue in table.keys) '$issue'}, declared);
  });
}
