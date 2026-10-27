import 'channel.dart';

/// Whether the phone is on Wi-Fi or another network that costs nothing
/// per byte (`NetworkPart.kt`); false when it cannot tell.
Future<bool> androidUnmetered() async {
  try {
    return await platformChannel.invokeMethod<bool>('unmetered') ?? false;
  } on Object {
    return false;
  }
}
