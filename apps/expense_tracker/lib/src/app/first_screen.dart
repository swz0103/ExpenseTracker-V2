import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/platform/startup_state.dart';

import 'load_failed_page.dart';
import '../core/design_system/theme.dart';
import '../core/diagnostics/error_log.dart';
import '../core/diagnostics/error_steps.dart';
import '../core/messages/loading_messages.dart';
import '../core/platform/screen_privacy.dart';
import '../core/platform/preferences.dart';

/// What `main()` waits for before the first screen, each a step of its
/// own, so a test can make each one fail (ARC-06).
final class StartSteps {
  const StartSteps({
    required this.folder,
    required this.compose,
    this.keepLog,
    this.device,
    this.privacy,
    this.preferences,
    this.started,
  });

  /// The app's own folder, where the ledger is kept. Nothing opens
  /// without it.
  final Future<Directory> Function() folder;

  /// Keeps the diagnostics log in [folder] from now on.
  final void Function(Directory folder)? keepLog;

  /// The phone's fingerprint or face. Without it the ledger still opens,
  /// with its password or by itself.
  final Future<DeviceUnlock?> Function(Directory folder)? device;

  /// Keeping the screens out of screenshots. Without it the phone keeps
  /// them out as it starts (`MainActivity.kt`).
  final Future<ScreenPrivacy?> Function(Directory folder)? privacy;

  /// The settings kept in [folder], read and opened off the UI thread.
  /// Without them the app starts with the defaults, kept in memory only,
  /// so the file is not written over.
  final Future<Preferences> Function(Directory folder)? preferences;

  /// The app on what the steps found.
  final Widget Function(
    Directory folder,
    DeviceUnlock? device,
    ScreenPrivacy? privacy,
    Preferences preferences,
  )
  compose;

  /// What starts once the app is put together, beside its first frame.
  final void Function(Directory folder)? started;
}

/// Runs [steps] and gives the first screen: the app, or, when a step it
/// cannot do without fails, a page saying what happened with a way out
/// (try again with [retry], copy the diagnostics), never a blank app. A
/// step it can do without is noted and the app starts without it.
Future<Widget> firstScreen(
  StartSteps steps, {
  required VoidCallback retry,
}) async {
  final Directory folder;
  try {
    folder = await steps.folder();
  } on Object catch (error, stack) {
    ErrorLog.instance.record(ErrorSteps.startFolder, error, stack);
    return _failed(error, retry);
  }
  steps.keepLog?.call(folder);
  DeviceUnlock? device;
  try {
    device = await steps.device?.call(folder);
  } on Object catch (error, stack) {
    ErrorLog.instance.record(ErrorSteps.startDevice, error, stack);
  }
  ScreenPrivacy? privacy;
  try {
    privacy = await steps.privacy?.call(folder);
  } on Object catch (error, stack) {
    ErrorLog.instance.record(ErrorSteps.screenPrivacy, error, stack);
  }
  Preferences? preferences;
  try {
    preferences = await steps.preferences?.call(folder);
  } on Object catch (error, stack) {
    ErrorLog.instance.record(ErrorSteps.preferencesRead, error, stack);
  }
  final Widget app;
  try {
    app = steps.compose(folder, device, privacy, preferences ?? Preferences());
  } on Object catch (error, stack) {
    ErrorLog.instance.record(ErrorSteps.startScreen, error, stack);
    return _failed(error, retry);
  }
  steps.started?.call(folder);
  return app;
}

/// The failure page of [error], already kept in the error log, where
/// the copied diagnostics carry it.
Widget _failed(Object error, VoidCallback retry) =>
    StartFailedApp(retry: retry);

/// The whole app when it could not start: what happened, try again, or
/// copy the diagnostics to report it. No backup can be restored from
/// here: without the app's folder there is nowhere to restore it to.
class StartFailedApp extends StatefulWidget {
  const StartFailedApp({super.key, required this.retry});

  final VoidCallback retry;

  @override
  State<StartFailedApp> createState() => _StartFailedAppState();
}

class _StartFailedAppState extends State<StartFailedApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    // No preferences are read yet: the phone's own light or dark, as the
    // app itself starts with.
    Shade.dark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: ErrorLog.instance.text));
    _messenger.currentState?.showSnackBar(
      const SnackBar(content: Text(startFailedCopied)),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    scaffoldMessengerKey: _messenger,
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: LoadFailedPage(
      title: startFailedTitle,
      body: startFailedBody,
      exportLabel: startFailedCopy,
      onRetry: widget.retry,
      onRestore: null,
      onExport: _copy,
    ),
  );
}
