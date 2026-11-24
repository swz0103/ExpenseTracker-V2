import 'dart:async';

import 'package:flutter/material.dart';

import '../core/diagnostics/error_log.dart';
import '../core/diagnostics/error_steps.dart';

import '../core/design_system/dialogs.dart';
import '../core/design_system/keys.dart';
import '../core/design_system/spacing.dart';
import '../core/ledger/persistence/upgrade_backup.dart';
import '../core/messages/loading_messages.dart';

/// A book kept by an earlier version, held back from its upgrade because
/// the copy kept first could not be written (D19): why, in words, how to
/// make room, and the ways on: try again, export the diagnostics, or go
/// on without the copy, which asks a second time.
class UpgradeHeldPage extends StatelessWidget {
  const UpgradeHeldPage({
    super.key,
    required this.failure,
    required this.onRetry,
    required this.onExport,
    required this.onWithoutBackup,
  });

  final UpgradeBackupFailed failure;
  final VoidCallback onRetry;
  final VoidCallback onExport;

  /// Brings the book up without the copy; only once asked twice.
  final VoidCallback onWithoutBackup;

  Future<void> _skip(BuildContext context) async {
    final sure = await confirm(
      context,
      upgradeHeldConfirm,
      upgradeHeldConfirmAction,
      danger: true,
      body: upgradeHeldConfirmBody,
    );
    if (sure) onWithoutBackup();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                upgradeHeldTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Space.s3),
              Text(
                upgradeHeldBody(failure.problem, failure.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.s3),
              Text(upgradeHeldSpace, textAlign: TextAlign.center),
              const SizedBox(height: Space.s6),
              FilledButton(
                key: Keys.upgradeHeld('retry'),
                onPressed: onRetry,
                child: const Text(upgradeHeldRetry),
              ),
              const SizedBox(height: Space.s2),
              OutlinedButton(
                key: Keys.upgradeHeld('export'),
                onPressed: onExport,
                child: const Text(upgradeHeldExport),
              ),
              const SizedBox(height: Space.s2),
              TextButton(
                key: Keys.upgradeHeld('skip'),
                onPressed: () => _skip(context),
                child: const Text(upgradeHeldSkip),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Holds a ledger's opening while the copy kept before its upgrade cannot
/// be written (D19): [held] says why, for [UpgradeHeldPage], until the
/// person tries again or chooses, twice, to go on without it ([choose]).
final class UpgradeHold extends ChangeNotifier {
  /// The copy that could not be kept, while the opening is held.
  UpgradeBackupFailed? get held => _held;
  UpgradeBackupFailed? _held;

  Completer<bool>? _choice;

  /// Brings the book up with [bringUp], as many times as the person asks,
  /// until it is (or the person went on without the copy).
  Future<void> prepare(
    Future<UpgradeBackupFailed?> Function({bool withoutBackup}) bringUp,
  ) async {
    var withoutBackup = false;
    for (;;) {
      final held = await bringUp(withoutBackup: withoutBackup);
      if (held == null) return;
      final choice = _choice = Completer<bool>();
      _held = held;
      notifyListeners();
      withoutBackup = await choice.future;
      if (withoutBackup) {
        ErrorLog.instance.record(
          ErrorSteps.upgradeBackup,
          StateError('skipped by choice'),
        );
      }
      _held = null;
      notifyListeners();
    }
  }

  /// What the person chose on the page: to try again, or to go on
  /// [withoutBackup]; nothing while nothing is held.
  void choose({required bool withoutBackup}) {
    final choice = _choice;
    if (choice == null || choice.isCompleted) return;
    choice.complete(withoutBackup);
  }
}
