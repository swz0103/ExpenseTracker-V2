import 'platform_channel.dart';
import '../../core/messages/native_messages.dart';

/// Puts [text] on the clipboard flagged sensitive, so Android leaves it
/// out of its clipboard preview (`ClipboardHandler.kt`), under the label
/// the app gives it.
Future<void> androidCopySensitive(String text) =>
    platformChannel.invokeMethod<void>('copySensitive', {
      'text': text,
      'label': NativeWords.clipboardLabel,
    });
