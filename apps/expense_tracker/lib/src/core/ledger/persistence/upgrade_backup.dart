import 'dart:io';

import '../../diagnostics/error_log.dart';
import '../../diagnostics/error_steps.dart';

/// How keeping a copy of the book before it is brought up to this version
/// went (D19): kept, or not, and why. A book is brought up only once its
/// copy is kept, or when the person chose, twice, to go on without one.
sealed class UpgradeBackup {
  const UpgradeBackup();
}

/// The copy is kept.
final class UpgradeBackupKept extends UpgradeBackup {
  const UpgradeBackupKept();
}

/// The copy could not be kept: the book stays as it was, not brought up.
final class UpgradeBackupFailed extends UpgradeBackup {
  const UpgradeBackupFailed(this.problem, this.error);

  /// What kept it from being written, in the classes the screen words.
  final UpgradeBackupProblem problem;

  /// What was thrown, for the diagnostics; never shown as it is.
  final Object error;

  /// The failure of [error], thrown writing the copy.
  factory UpgradeBackupFailed.of(Object error) => UpgradeBackupFailed(
    _noSpace(error) ? UpgradeBackupProblem.noSpace : UpgradeBackupProblem.other,
    error,
  );

  /// The system's "no space left on the device": ENOSPC on Linux and
  /// Android, ERROR_DISK_FULL on Windows.
  static const _enospc = 28;
  static const _diskFull = 112;

  static bool _noSpace(Object error) => switch (error) {
    FileSystemException(osError: OSError(errorCode: _enospc || _diskFull)) =>
      true,
    _ => false,
  };
}

/// Keeps the copy with [keep], which throws when it cannot: how it went,
/// a failure noted in the diagnostics.
Future<UpgradeBackup> keepUpgradeBackup(Future<void> Function() keep) async {
  try {
    await keep();
    return const UpgradeBackupKept();
  } on Object catch (error) {
    ErrorLog.instance.record(ErrorSteps.upgradeBackup, error);
    return UpgradeBackupFailed.of(error);
  }
}

/// Why a copy before an upgrade could not be kept.
enum UpgradeBackupProblem {
  /// The phone has no room left for it.
  noSpace,

  /// Anything else; the diagnostics say what.
  other,
}
