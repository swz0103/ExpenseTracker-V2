import 'package:ledger_loans/model/rate.dart' show rateText;

import '../ledger/ledger.dart';
import '../../../design_system/display/amount.dart';
import '../formatting/words.dart';

/// What a loan's form says when its rate as typed is no number, rather
/// than keep it as no rate (D118).
const loanRateUnreadable = '利率要填數字，例如 2.15';

/// What a loan's form says when its rate is above nothing but less than
/// the least kept, 0.01%: it would be kept as no interest (review 33).
const loanRateTooSmall = '利率最小是 0.01%';

/// What the person is told when the ledger will not keep a record, or
/// warns before keeping it: every reason's words, in one place.
String validationMessage(RecordIssue issue) => switch (issue) {
  MissingAmount(trade: true) => '請輸入股數和成交價',
  MissingAmount() => '請輸入金額',
  // Exception to glossary: 記錄 is the verb here.
  AmountTooLarge() => '金額超過可記錄的上限',
  NegativeCharge() => '手續費和稅不能是負數',
  DateNotMidnight() => '日期無效，請重新選擇',
  UnknownAccount() => '找不到這個帳戶，請重新選擇',
  MissingDestination() => '請選擇轉入帳戶',
  SameAccountTransfer() => '轉出與轉入不能是同一個帳戶',
  MissingHomeAmount() => '還沒有匯率，請輸入${Words.homeWorth}的金額',
  CardTransferOut() => '信用卡不能轉出，請記成支出',
  ForeignTransferFee() => '外幣帳戶轉出時不能記手續費',
  CardPaymentFee() => '繳卡費不記手續費，請另記一筆支出',
  MissingReceivedAmount() => '還沒有匯率，請輸入轉入金額',
  ForeignCardPayment() => '外幣帳戶不能直接繳卡費',
  ForeignInvestment() => '投資請用新台幣帳戶',
  InvestmentFromDebt() => '買賣股票要用現金或銀行帳戶付款',
  ReductionExceedsHolding(:final held) => '減少的股數超過持股（${groupDigits(held)} 股）',
  TaxExceedsDividend() => '補充保費不能超過股息',
  MissingHolding() => '請選擇投資標的',
  MissingShares() => '請輸入股數',
  // Exception to glossary: 記錄 is the verb here.
  SharesTooLarge() => '股數超過可記錄的上限',
  DayTradeNotSale() => '只有賣出可以是當日沖銷',
  DateTooFarAhead(:final days) => '日期最多只能排到 $days 天後',
  InvestmentPlanned() => '股票買賣與股息要在當天或之前記，不能預定',
  SaleExceedsHolding(later: false) => '賣出股數超過持股',
  SaleExceedsHolding(later: true) => '這樣之後的賣出或減資會超過持股，請先改那一筆',
  RefundToOtherAccount() => '信用卡消費的退款要退回同一張卡',
  RefundOtherCurrency() => '退款要退回和原支出同一種幣別的帳戶',
  EntryDeleted() => '這筆已刪除，可到「最近刪除」救回',
  RefundExceedsRemaining(:final left) => '超過可退金額 ${groupDigits(left)}',
  SplitPartNotPositive() => '拆分的每一項金額都要大於 0',
  SplitTotalMismatch(:final difference) =>
    '拆分的金額要等於總額（差 ${groupDigits(difference)}）',
  InstallmentsOffCard() => '只有信用卡消費可以分期',
  InstallmentsOutOfRange(:final max) => '分期最多 $max 期',
  NegativeBalanceAfter(:final after) => '扣款後餘額為負（${groupDigits(after)}）',
  IntervalTooSmall() => '重複的間隔至少要 1',
  DayOutOfRange() => '日期要在 1 到 31 日之間',
  EndsBeforeStart() => '結束日不能早於開始日',
  BlankName() => '請輸入帳戶名稱',
  ClosingDayOutOfRange() => '結帳日要在 1 到 31 日之間',
  DueDayOutOfRange() => '繳款日要在 1 到 31 日之間',
  NegativeCreditLimit() => '信用額度不能是負數',
  NegativeLoanRate() => '利率不能是負數',
  LoanRateTooHigh(:final max) => '利率不能超過 ${rateText(max)}%，請確認是否打錯',
  ArchivedOwing() => '還有沒結清的款項，結清後才能封存',
  CloseMoveRefused() => '結帳日只能前後調整 7 天內，而且要在繳款日之前',
  NegativeBudgetLimit() => '預算額度不能是負數',
  WarningOutOfRange() => '提醒比例要在 1% 到 100% 之間',
};
