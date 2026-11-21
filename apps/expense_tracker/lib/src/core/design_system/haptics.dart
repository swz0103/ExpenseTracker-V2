import 'package:flutter/services.dart';

/// How heavy a tap felt in the hand is.
enum HapticKind { tick, click, heavy }

/// Taps felt in the hand: a tick on choices, a tap on saving, a knock on
/// deleting. All of them stop when 設定 turns 震動 off; 標準 makes each
/// one step heavier than 輕.
abstract final class Haptics {
  /// Set by the app from the person's choice.
  static bool on = true;

  /// 標準 rather than 輕.
  static bool strong = true;

  /// Plays a tap; set by the app on Android to the phone's own effects,
  /// Flutter's elsewhere.
  static void Function(HapticKind kind) perform = _flutter;

  static void _flutter(HapticKind kind) {
    switch (kind) {
      case HapticKind.tick:
        HapticFeedback.selectionClick();
      case HapticKind.click:
        HapticFeedback.lightImpact();
      case HapticKind.heavy:
        HapticFeedback.mediumImpact();
    }
  }

  static void _play(HapticKind light, HapticKind standard) {
    if (on) perform(strong ? standard : light);
  }

  /// A choice made: a day, a tab, a chip.
  static void selection() => _play(HapticKind.tick, HapticKind.click);

  /// Something done: saved, moved.
  static void light() => _play(HapticKind.tick, HapticKind.click);

  /// Something weighty: deleted, locked.
  static void medium() => _play(HapticKind.click, HapticKind.heavy);
}
