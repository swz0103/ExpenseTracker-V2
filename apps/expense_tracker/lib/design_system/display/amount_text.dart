import 'package:flutter/widgets.dart';

import 'amount.dart';

export 'amount.dart' show AmountSense, readOut, spokenAmount, shownAmount;

/// An amount on screen. It is always read out with its direction in
/// words ([spokenAmount]: `支出 1,844 元`), so a screen reader never
/// depends on a minus sign being spoken.
class AmountText extends StatelessWidget {
  /// [shown] as written, read out as [spoken]. For a place that writes an
  /// amount its own way; [AmountText.of] covers the usual ones.
  const AmountText(
    this.shown, {
    super.key,
    required this.spoken,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
  });

  /// [minor] units of [currency] written and read out by its [sense]:
  /// `−1,844` read 支出 1,844 元; dots, read 金額已隱藏, while [hidden].
  AmountText.of(
    int minor, {
    Key? key,
    String currency = 'TWD',
    AmountSense sense = AmountSense.plain,
    bool hidden = false,
    TextStyle? style,
    TextAlign? textAlign,
    int? maxLines,
    TextOverflow? overflow,
  }) : this(
         shownAmount(minor, currency: currency, sense: sense, hidden: hidden),
         key: key,
         spoken: spokenAmount(
           minor,
           currency: currency,
           sense: sense,
           hidden: hidden,
         ),
         style: style,
         textAlign: textAlign,
         maxLines: maxLines,
         overflow: overflow,
       );

  /// [shown], a line with [minor] written in it, read out with the
  /// amount in words in its place ([readOut]): `已實現 +1,200` is read
  /// 已實現 正 1,200 元.
  AmountText.within(
    String shown,
    int minor, {
    Key? key,
    String currency = 'TWD',
    AmountSense sense = AmountSense.signed,
    bool hidden = false,
    TextStyle? style,
    TextAlign? textAlign,
    int? maxLines,
    TextOverflow? overflow,
  }) : this(
         shown,
         key: key,
         spoken: readOut(
           shown,
           minor,
           currency: currency,
           sense: sense,
           hidden: hidden,
         ),
         style: style,
         textAlign: textAlign,
         maxLines: maxLines,
         overflow: overflow,
       );

  final String shown;
  final String spoken;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: spoken,
    excludeSemantics: true,
    child: Text(
      shown,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
    ),
  );
}
