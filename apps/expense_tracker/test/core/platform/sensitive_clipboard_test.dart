import 'package:expense_tracker/src/core/platform/sensitive_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A recovery code copied is flagged sensitive and taken off the clipboard
/// after a minute, unless something else was copied since (SEC-12).
void main() {
  late String? clip;
  late List<String> flagged;

  setUp(() {
    clip = null;
    flagged = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clip = (call.arguments as Map)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return clip == null ? null : {'text': clip};
          }
          return null;
        });
  });
  tearDown(() => SensitiveClipboard.platformCopy = null);

  testWidgets('cleared after 60 seconds when unchanged', (tester) async {
    await SensitiveClipboard.copy('ETR1-AAAA');
    expect(clip, 'ETR1-AAAA');
    await tester.pump(const Duration(seconds: 59));
    expect(clip, 'ETR1-AAAA');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(clip, '');
  });

  testWidgets('left alone when something else was copied since', (
    tester,
  ) async {
    await SensitiveClipboard.copy('ETR1-AAAA');
    clip = 'a note copied later';
    await tester.pump(SensitiveClipboard.keepFor);
    await tester.pump();
    expect(clip, 'a note copied later');
  });

  testWidgets('copied through the phone, flagged sensitive, where it can', (
    tester,
  ) async {
    SensitiveClipboard.platformCopy = (text) async {
      flagged.add(text);
      clip = text;
    };
    await SensitiveClipboard.copy('ETR1-BBBB');
    expect(flagged, ['ETR1-BBBB']);
    await tester.pump(SensitiveClipboard.keepFor);
    await tester.pump();
    expect(clip, '');
  });
}
