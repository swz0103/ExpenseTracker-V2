import 'package:flutter/material.dart';

import '../core/design_system/keys.dart';
import '../core/design_system/spacing.dart';
import '../core/messages/loading_messages.dart';

/// The book could not be opened at all: never a dead end. Try again,
/// restore a backup, or export what went wrong.
class LoadFailedPage extends StatelessWidget {
  const LoadFailedPage({
    super.key,
    required this.onRetry,
    required this.onRestore,
    required this.onExport,
  });

  final VoidCallback onRetry;
  final VoidCallback onRestore;
  final VoidCallback onExport;

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
                loadFailedTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Space.s3),
              const Text(loadFailedBody, textAlign: TextAlign.center),
              const SizedBox(height: Space.s6),
              FilledButton(
                key: Keys.loadFailed('retry'),
                onPressed: onRetry,
                child: const Text(loadFailedRetry),
              ),
              const SizedBox(height: Space.s2),
              OutlinedButton(
                key: Keys.loadFailed('restore'),
                onPressed: onRestore,
                child: const Text(loadFailedRestore),
              ),
              const SizedBox(height: Space.s2),
              TextButton(
                key: Keys.loadFailed('export'),
                onPressed: onExport,
                child: const Text(loadFailedExport),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
