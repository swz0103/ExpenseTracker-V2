import 'package:flutter/services.dart';

/// Taps felt in the hand: a tick on choices, a tap on saving, a knock on
/// deleting. All of them stop when 設定 turns 震動回饋 off.
abstract final class Haptics {
  /// Set by the app from the person's choice.
  static bool on = true;

  static void selection() {
    if (on) HapticFeedback.selectionClick();
  }

  static void light() {
    if (on) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (on) HapticFeedback.mediumImpact();
  }
}
