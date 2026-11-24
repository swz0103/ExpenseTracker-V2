import '../../../design_system/display/status_messages.dart';

/// What the screens say of 預定 entries: dated after today, counted in no
/// sum until their day comes (D25).
abstract final class PlannedText {
  /// Under a report whose period holds 預定 entries: how many, and what
  /// they will spend once their days come.
  static String report(int count, String spending) =>
      '${StatusWords.planned} $count 筆 · 支出 $spending，到日期才計入';
}
