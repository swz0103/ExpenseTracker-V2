import 'dart:io';

import 'package:flutter/material.dart';

import '../core/design_system/keys.dart';
import '../core/diagnostics/error_log.dart';
import '../core/diagnostics/error_steps.dart';
import '../core/ledger/persistence/quarantine.dart';
import '../core/messages/loading_messages.dart';

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

/// Tells how many of [rows] were set aside as the book opened, with a way
/// to report them ([onExport]), to restore a backup (true), or to go on
/// with the rest of the book (false).
Future<bool> showQuarantineNotice(
  BuildContext context,
  List<QuarantinedRow> rows, {
  required VoidCallback onExport,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(quarantineTitle(rows.length)),
        content: Text(quarantineBody(rows)),
        actions: [
          TextButton(
            key: Keys.quarantine('export'),
            onPressed: onExport,
            child: const Text(quarantineExport),
          ),
          TextButton(
            key: Keys.quarantine('restore'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(quarantineRestore),
          ),
          FilledButton(
            key: Keys.quarantine('continue'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(quarantineContinue),
          ),
        ],
      ),
    ) ??
    false;
