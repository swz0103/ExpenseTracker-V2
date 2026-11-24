import 'dart:io';

import '../core/diagnostics/error_log.dart';
import '../core/diagnostics/error_steps.dart';
import '../core/ledger/persistence/quarantine.dart';

/// Which rows set aside as the book opened the person is told of (D18):
/// those that cannot be read, every opening; those a newer version wrote,
/// once per distinct set. The fingerprint of the set last told is kept in
/// [file], beside the keyring: where rows are kept and which version
/// wrote them, hashed, never an amount or anything else of them.
final class QuarantineNotices {
  const QuarantineNotices(this.file);

  final File file;

  /// Of [rows], those to tell now; remembers the newer set as told.
  Future<List<QuarantinedRow>> toTell(List<QuarantinedRow> rows) async {
    String? told;
    try {
      if (file.existsSync()) told = file.readAsStringSync().trim();
    } on Object catch (error) {
      // Unreadable: told again, which is the safe side.
      ErrorLog.instance.record(ErrorSteps.quarantineNotice, error);
    }
    final (:tell, :fingerprint) = quarantineToTell(rows, told: told);
    try {
      if (fingerprint == null) {
        if (file.existsSync()) await file.delete();
      } else if (fingerprint != told) {
        await file.writeAsString(fingerprint, flush: true);
      }
    } on Object catch (error) {
      ErrorLog.instance.record(ErrorSteps.quarantineNotice, error);
    }
    return tell;
  }
}
