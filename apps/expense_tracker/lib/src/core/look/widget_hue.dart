import 'theme.dart';

/// The home-screen widget 本月概況 as the phone draws it, for the web
/// preview and for 設定 › 桌面小工具: `WidgetFace` at full size
/// (summary_widget.xml) and `WidgetRow` one row high (quick_widget.xml),
/// from the snapshot the app writes (home_widget.dart). Its colours are
/// the widget's own (res/values*/colors.xml): light, or dark when the
/// phone is, as the app's own themes.
abstract final class WidgetLook {
  static const card = Shade(0xFFFFFFFF, 0xFF343F45);
  static const ink = Shade(0xFF26323A, 0xFFEEF2F3);
  static const muted = Shade(0xFF7A858B, 0xFFA3AEB3);
  static const day = Shade(0xFF9AA4A9, 0xFF8E9AA0);
  static const track = Shade(0xFFEEF1EF, 0xFF46535A);
  static const accent = Shade(0xFF35657A, 0xFFA5C7D4);
  static const bar = Shade(0xFFA9C0C8, 0xFF5F7D89);
  static const pace = Shade(0xFFC9A34A, 0xFFDDBE73);
  static const dot = Shade(0xFFD5DAD7, 0xFF55626A);
  static const expense = Shade(0xFF9F4535, 0xFFF1B2A3);
  static const income = Shade(0xFF276B58, 0xFF8CCEB6);
  static const rule = Shade(0xFFE1E4E0, 0xFF46535A);
  static const onButton = Shade(0xFFFFFFFF, 0xFF0F1A1F);
  static const expenseTint = Shade(0xFFF3E3DF, 0xFF4B3B39);
  static const incomeTint = Shade(0xFFDCEBE5, 0xFF2E4741);
}
