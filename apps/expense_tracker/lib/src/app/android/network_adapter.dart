import 'platform_channel.dart';
import '../../core/diagnostics/error_log.dart';

/// Whether the phone is on Wi-Fi or another network that costs nothing
/// per byte (`NetworkHandler.kt`); false when it cannot tell.
Future<bool> androidUnmetered() async {
  try {
    return await platformChannel.invokeMethod<bool>('unmetered') ?? false;
  } on Object catch (error) {
    ErrorLog.instance.record('網路狀態', error);
    return false;
  }
}
