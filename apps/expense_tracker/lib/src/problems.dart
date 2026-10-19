import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'model/journal.dart';

/// Shows why a command was refused, in words a person can act on.
void showProblem(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(describeProblem(error))));
}

String describeProblem(Object error) => switch (error) {
  final PartlyKept partly => _partly(partly),
  AppFailure(diagnostic: 'account.versionConflict') => '帳戶剛被修改過，請再試一次。',
  AppFailure(diagnostic: 'account.unavailable') => '這個帳戶已封存或結清，不能記帳。',
  AppFailure(diagnostic: 'account.invalidInput') => '帳戶名稱不能空白，最多 100 字。',
  AppFailure(diagnostic: 'ledger.invalidAmount') => '金額必須大於 0。',
  AppFailure(diagnostic: 'ledger.sameAccount') => '轉出與轉入不能是同一個帳戶。',
  AppFailure(diagnostic: 'posting.already-reversed') => '這筆已經沖銷過了。',
  AppFailure(diagnostic: 'investment.funding') => '買賣股票要用現金或銀行帳戶付款。',
  AppFailure(diagnostic: 'investment.no-holdings') => '這檔目前沒有持股。',
  AppFailure(diagnostic: 'investment.backdated') => '比最後一筆賣出或分割更早的交易不能補記。',
  AppFailure(diagnostic: 'investment.cost-method') => '同一檔股票的賣出要用同一種成本算法。',
  AppFailure(diagnostic: 'investment.trade-in-use') => '要先刪除之後的賣出或分割，才能刪除這筆。',
  AppFailure(diagnostic: 'app.account-kind') => '帳戶建立後不能更改類型。',
  AppFailure(diagnostic: 'app.card-transfer') => '信用卡不能轉出，請記成支出。',
  AppFailure(diagnostic: 'app.card-refund') => '信用卡消費的退款要退回同一張卡。',
  AppFailure(diagnostic: 'card.has-installments') => '分期中的消費不能刪除。',
  AppFailure(diagnostic: 'app.home-value') => '外幣紀錄要填折合台幣的金額。',
  AppFailure(diagnostic: 'app.received') => '不同幣別的轉帳要填轉入金額。',
  AppFailure(diagnostic: 'app.foreign-fee') => '外幣帳戶轉出時不能記手續費。',
  AppFailure(diagnostic: 'app.foreign-card-payment') => '外幣帳戶不能直接繳卡費。',
  AppFailure(diagnostic: 'app.foreign-card') => '信用卡只能用新台幣。',
  AppFailure(diagnostic: 'app.card-fee') => '繳卡費不記手續費，請另記一筆支出。',
  AppFailure(diagnostic: 'category.duplicate') => '已經有同名的分類。',
  AppFailure(diagnostic: 'category.hasChildren') => '這個分類底下還有子分類，請先移走。',
  AppFailure(diagnostic: 'category.unavailable') => '這個分類已封存或合併，不能再使用。',
  AppFailure(diagnostic: 'tag.duplicate') => '同一筆紀錄不能有重複的標籤。',
  AppFailure(:final diagnostic) => '無法完成（$diagnostic）。',
  MoneyException(code: MoneyError.precision) => '金額的小數位數太多。',
  PlatformException(code: 'busy') => '上一個檔案還在處理，請稍候再試。',
  PlatformException() => '手機沒有完成這個動作，請再試一次。',
  MoneyException() || FormatException() => '請輸入有效的金額。',
  _ => '發生未預期的錯誤。',
};

/// Which entry of a batch was refused, and what became of the rest.
String _partly(PartlyKept partly) {
  final PartlyKept(:kept, :total, :cause) = partly;
  final left = total - kept - 1;
  return '第 ${kept + 1} 筆無法記下：${describeProblem(cause)}'
      '前 $kept 筆已記下，其餘 $left 筆沒有記。';
}
