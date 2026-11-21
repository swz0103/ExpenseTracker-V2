import 'platform_channel.dart';
import '../../core/design_system/haptics.dart';

/// Plays [kind] as Android's own tick, click or heavy click
/// (`HapticsHandler.kt`). A tap that cannot be played is not worth a word.
void androidHaptic(HapticKind kind) {
  platformChannel
      .invokeMethod<void>('haptic', {'kind': kind.name})
      .catchError((Object _) {});
}
