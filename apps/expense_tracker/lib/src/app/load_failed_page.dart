import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_system/keys.dart';
import '../core/diagnostics/error_log.dart';
import '../core/platform/startup.dart';
import '../core/platform/startup_state.dart';
import '../core/design_system/spacing.dart';
import '../core/messages/loading_messages.dart';
import '../core/messages/diagnostics_messages.dart';

/// The book could not be opened at all: never a dead end. Try again,
/// restore a backup, or export what went wrong. Also the page of an app
/// that could not start ([title], [body]), where no restore can be
/// offered ([onRestore] null).
class LoadFailedPage extends StatelessWidget {
  const LoadFailedPage({
    super.key,
    required this.onRetry,
    required this.onRestore,
    required this.onExport,
    this.title = loadFailedTitle,
    this.body = loadFailedBody,
    this.exportLabel = diagnosticsExport,
  });

  final VoidCallback onRetry;

  /// Restores a backup; none offered when null.
  final VoidCallback? onRestore;
  final VoidCallback onExport;

  /// What went wrong, and what is safe to do.
  final String title;
  final String body;

  /// The words of [onExport]'s button.
  final String exportLabel;

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
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Space.s3),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: Space.s6),
              FilledButton(
                key: Keys.loadFailed('retry'),
                onPressed: onRetry,
                child: const Text(loadFailedRetry),
              ),
              if (onRestore case final restore?) ...[
                const SizedBox(height: Space.s2),
                OutlinedButton(
                  key: Keys.loadFailed('restore'),
                  onPressed: restore,
                  child: const Text(loadFailedRestore),
                ),
              ],
              const SizedBox(height: Space.s2),
              TextButton(
                key: Keys.loadFailed('export'),
                onPressed: onExport,
                child: Text(exportLabel),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The ledger's file is damaged (D94): set aside, never opened empty.
/// Restore a backup, try again, or copy the diagnostics to report it:
/// before any book is open there is nowhere to save a file to.
class DamagedBookPage extends StatelessWidget {
  const DamagedBookPage({
    super.key,
    required this.onRetry,
    required this.onRestore,
  });

  /// The page of [startup] in [Damaged]: try again from the lock screen,
  /// or restore a backup there.
  DamagedBookPage.of(Startup startup, {Key? key})
    : this(
        key: key,
        onRetry: startup.retryAfterDamage,
        onRestore: startup.lockToRestore,
      );

  final VoidCallback onRetry;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) => LoadFailedPage(
    title: damagedTitle,
    body: damagedBody,
    exportLabel: startFailedCopy,
    onRetry: onRetry,
    onRestore: onRestore,
    onExport: () async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      await Clipboard.setData(ClipboardData(text: ErrorLog.instance.text));
      messenger?.showSnackBar(const SnackBar(content: Text(startFailedCopied)));
    },
  );
}
