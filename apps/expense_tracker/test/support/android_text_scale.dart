import 'package:flutter/widgets.dart';

/// Text scaled as Android 14 and later scales it at a font scale of 200%,
/// the largest it offers: small text twice as large, large text much less,
/// so a big figure does not grow out of its place (FontScaleConverterFactory
/// in the Android framework; Flutter takes the same curve from the phone).
/// Between the sizes of the table it is read along a straight line.
final class AndroidTextScaler200 extends TextScaler {
  const AndroidTextScaler200();

  static const _fromSp = [8.0, 10, 12, 14, 18, 20, 24, 30, 100];
  static const _toDp = [16.0, 20, 24, 26, 30, 34, 36, 38, 100];

  @override
  double scale(double fontSize) {
    if (fontSize <= _fromSp.first) {
      return fontSize * _toDp.first / _fromSp.first;
    }
    if (fontSize >= _fromSp.last) return fontSize;
    for (var i = 1; i < _fromSp.length; i++) {
      if (fontSize <= _fromSp[i]) {
        final share =
            (fontSize - _fromSp[i - 1]) / (_fromSp[i] - _fromSp[i - 1]);
        return _toDp[i - 1] + share * (_toDp[i] - _toDp[i - 1]);
      }
    }
    return fontSize;
  }

  @override
  // The scale Android reports for the setting, as Flutter passes it on.
  // ignore: deprecated_member_use
  double get textScaleFactor => 2;

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) => maxScaleFactor < 2 ? TextScaler.linear(maxScaleFactor) : this;

  @override
  bool operator ==(Object other) => other is AndroidTextScaler200;

  @override
  int get hashCode => (AndroidTextScaler200).hashCode;
}
