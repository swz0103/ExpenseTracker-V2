import 'package:flutter/foundation.dart';

import '../../core/quick_action.dart';
import 'channel.dart';

/// What a home-screen shortcut, the widget or a notification asked for:
/// `expense` or `income` opens the composer. Held until the app is open
/// to act on it.
final quickAction = ValueNotifier<QuickAction?>(null);

/// Takes the action the app was opened with, then listens for those
/// that arrive while it runs. Each action arrives once: the phone keeps
/// one for `takeQuickAction` until that call, and only after it sends
/// later ones as `quickAction` (`MainActivity.kt`). The handler is set
/// first, so none sent after the take is missed.
Future<void> listenForQuickActions() async {
  platformChannel.setMethodCallHandler((call) async {
    if (call.method == 'quickAction')
      quickAction.value = QuickAction.named(call.arguments as String?);
  });
  final first = await platformChannel.invokeMethod<String>('takeQuickAction');
  if (QuickAction.named(first) case final action?) {
    quickAction.value = action;
  }
}
