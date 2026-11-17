import '../ledger/ledger.dart';
import '../text/amounts.dart';

/// What the person is told when the ledger will not keep an entry: every
/// reason's words, in one place.
String validationMessage(EntryValidationFailure failure) => switch (failure) {
  MissingAmount(trade: true) => '請輸入股數和成交價',
  MissingAmount() => '請輸入金額',
  SameAccountTransfer() => '轉出與轉入不能是同一個帳戶',
  MissingHomeAmount() => '還沒有匯率，請輸入折合台幣的金額',
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
  SaleExceedsHolding() => '賣出股數超過持股',
  RefundToOtherAccount() => '信用卡消費的退款要退回同一張卡',
  RefundExceedsRemaining(:final left) => '超過可退金額 ${groupDigits(left)}',
};
