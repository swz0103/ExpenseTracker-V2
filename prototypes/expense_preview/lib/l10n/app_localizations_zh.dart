// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '記帳 V2';

  @override
  String get openingDateLabel => '起始日期（YYYY-MM-DD）';

  @override
  String get entryDateLabel => '日期（YYYY-MM-DD）';

  @override
  String get selectDate => '選擇日期';

  @override
  String get confirmDate => '確定';

  @override
  String get cancel => '取消';

  @override
  String get dateHelp => '選擇記帳日期';

  @override
  String get openingDateHelp => '選擇起始日期';

  @override
  String get calculateAmount => '計算金額';

  @override
  String get applyAmount => '套用結果';

  @override
  String get calculationSyntax => '請檢查算式、括號與小數點。';

  @override
  String get calculationDivisionByZero => '不能除以零，請修改算式。';

  @override
  String get calculationComplexity => '算式過長或過於複雜，請分段計算。';

  @override
  String get calculationRange => '計算結果超出可保存的金額範圍。';

  @override
  String calculationResult(String currency, String amount) {
    return '計算結果：$currency $amount';
  }

  @override
  String calculationRounded(String currency, int scale) {
    return '結果已依 $currency 小數 $scale 位四捨五入。';
  }

  @override
  String get calculationPercent => '10% = 0.1；折扣例：100 × (1 − 10%)。';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');
}
