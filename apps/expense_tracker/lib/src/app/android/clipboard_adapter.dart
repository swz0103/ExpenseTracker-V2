import 'platform_channel.dart';

/// Puts [text] on the clipboard flagged sensitive, so Android leaves it
/// out of its clipboard preview (`ClipboardHandler.kt`).
Future<void> androidCopySensitive(String text) =>
    platformChannel.invokeMethod<void>('copySensitive', {'text': text});
