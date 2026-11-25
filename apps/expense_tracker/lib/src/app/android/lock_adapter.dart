import '../../core/formatting/json_fields.dart';
import '../../core/platform/unlock_attempts.dart';
import 'platform_channel.dart';

/// How long the phone has run since it started, sleep included, and which
/// start that is (`LockHandler.kt`): a clock no setting moves, for the
/// wait after wrong passwords.
Future<Uptime?> androidUptime() async {
  final found = await platformChannel.invokeMapMethod<String, Object?>(
    'uptime',
  );
  return found == null ? null : uptimeOf(found);
}

/// The [Uptime] in what the phone answered; null when it lacks a part.
Uptime? uptimeOf(Map<String, Object?> found) {
  final json = JsonFields.from(found);
  final boot = json.text('boot');
  final up = json.whole('upMs');
  if (boot == null || up == null) return null;
  // Exception to the motion scale: a reading of the phone's clock, not a
  // movement.
  return (boot: boot, up: Duration(milliseconds: up));
}

/// Puts the app behind the others without closing it, as the home button
/// does: what back does on the first screen.
Future<void> androidMoveToBack() =>
    platformChannel.invokeMethod<void>('moveToBack');
