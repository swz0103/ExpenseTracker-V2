import 'dart:io';

import 'package:expense_tracker/src/app/first_screen.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every wait before the first screen is guarded (ARC-06): each step is
/// made to fail on its own, and the app either starts without it or says
/// what happened with a way out; never a blank app.
void main() {
  final folder = Directory('/data/user/0/app/files');
  late List<String> did;
  late int retried;

  setUp(() {
    did = [];
    retried = 0;
  });

  /// The steps of `main()`, each doing what [fail] does not name.
  StartSteps steps({Set<String> fail = const {}}) {
    T step<T>(String name, T value) {
      did.add(name);
      if (fail.contains(name)) throw StateError('$name broke');
      return value;
    }

    return StartSteps(
      folder: () async => step('folder', folder),
      keepLog: (f) => did.add('log ${f.path}'),
      device: (_) async => step<DeviceUnlock?>('device', null),
      privacy: (_) async => step('privacy', null),
      compose: (f, device, privacy) =>
          step('compose', Text('app device=$device privacy=$privacy')),
      started: (f) => did.add('started ${f.path}'),
    );
  }

  Future<Widget> start(StartSteps steps) =>
      firstScreen(steps, retry: () => retried++);

  /// The newest entry of the diagnostics log.
  String newest() => ErrorLog.instance.entries.first.$2;

  test('all well: each step once, in order, then the app', () async {
    final screen = await start(steps());
    expect((screen as Text).data, 'app device=null privacy=null');
    expect(did, [
      'folder',
      'log /data/user/0/app/files',
      'device',
      'privacy',
      'compose',
      'started /data/user/0/app/files',
    ]);
  });

  testWidgets('no folder: the failure page says what happened, offers to '
      'try again and to copy the diagnostics, and nothing else runs', (
    tester,
  ) async {
    final screen = await tester.runAsync(() => start(steps(fail: {'folder'})));
    expect(did, ['folder']);
    expect(newest(), '啟動：帳本資料夾：StateError: Bad state: folder broke');
    await tester.pumpWidget(screen!);
    expect(find.text('記帳本無法啟動'), findsOneWidget);
    expect(
      find.textContaining('（StateError: Bad state: folder broke）'),
      findsOneWidget,
    );
    expect(
      find.byKey(Keys.loadFailed('restore')),
      findsNothing,
      reason: 'without the folder there is nowhere to restore to',
    );
    await tester.tap(find.byKey(Keys.loadFailed('retry')));
    expect(retried, 1);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await tester.tap(find.byKey(Keys.loadFailed('export')));
    await tester.pump();
    expect(copied, contains('啟動：帳本資料夾'));
    expect(find.text('已複製診斷資料'), findsOneWidget);
  });

  test('the fingerprint cannot be asked about: noted, and the app starts '
      'without it', () async {
    final screen = await start(steps(fail: {'device'}));
    expect((screen as Text).data, 'app device=null privacy=null');
    expect(newest(), '啟動：生物辨識解鎖：StateError: Bad state: device broke');
    expect(did.last, 'started /data/user/0/app/files');
  });

  test('the screen privacy cannot be set: noted, and the app starts '
      'without it', () async {
    final screen = await start(steps(fail: {'privacy'}));
    expect((screen as Text).data, 'app device=null privacy=null');
    expect(newest(), '螢幕隱私：StateError: Bad state: privacy broke');
    expect(did.last, 'started /data/user/0/app/files');
  });

  test('the app cannot be put together: the failure page, and nothing '
      'started beside it', () async {
    final screen = await start(steps(fail: {'compose'}));
    expect(screen, isA<StartFailedApp>());
    expect(newest(), '啟動：第一個畫面：StateError: Bad state: compose broke');
    expect(did, isNot(contains(startsWith('started'))));
  });
}
