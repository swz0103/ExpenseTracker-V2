import 'package:flutter/widgets.dart';

/// The app's type scale: every size words are drawn at, by role. Pages
/// pick a role, never a number, so the same kind of words is the same
/// size everywhere; the phone's text size scales them all alike.
abstract final class TextSize {
  /// A mark's tiny label, such as 到期 under a day.
  static const tiny = 11.0;

  /// A footnote, a legend, a chip's word.
  static const caption = 12.0;

  /// Secondary words beside a heading: a count, a date, a line under a
  /// figure.
  static const small = 13.0;

  /// Words to read: a row's name, a field, a button's word.
  static const body = 15.0;

  /// A card's or a section's title.
  static const title = 17.0;

  /// A page's title and a panel's.
  static const heading = 20.0;

  /// A figure on a card.
  static const large = 24.0;

  /// The figure of a block that leads its page.
  static const figure = 28.0;

  /// The one figure a page is about, such as a balance.
  static const big = 34.0;

  /// The largest figure, such as the month left in the budget.
  static const hero = 44.0;

  /// The lock screen's and the code's digits.
  static const display = 56.0;
}

/// How much larger the phone draws words than the app sets them: 1 at
/// the standard size, about 1.9 for body words at Android's largest.
double textGrowth(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(TextSize.body) / TextSize.body;

/// The width [words] take on one line in [style], at the phone's text
/// size: to choose a layout that keeps a figure whole.
double wordsWidth(BuildContext context, String words, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: words,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
