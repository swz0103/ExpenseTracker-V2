import 'package:flutter/material.dart';

import '../core/design_system/keys.dart';
import '../core/design_system/spacing.dart';
import '../core/messages/loading_messages.dart';

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
    this.exportLabel = loadFailedExport,
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
