import 'package:core/app_core.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Where the app reads the time from: the phone's clock, or one a test
/// sets, so what depends on the day can be tried on any day. Code in `lib`
/// asks this and never `DateTime.now()` (a rule in layers_test).
abstract final class AppClock {
  static Clock _clock = const SystemClock();

  /// The time now, in the phone's own time zone, as `DateTime.now()` gives
  /// it.
  static DateTime now() => _clock.now().value.toLocal();

  /// Makes [clock] the app's, as a test needs; [reset] puts the phone's
  /// back.
  @visibleForTesting
  static void use(Clock clock) => _clock = clock;

  /// Puts the phone's clock back.
  @visibleForTesting
  static void reset() => _clock = const SystemClock();
}
