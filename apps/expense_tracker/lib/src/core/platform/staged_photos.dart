import 'dart:io';

import '../diagnostics/error_log.dart';
import 'app_files.dart';

/// The receipt photos a backup carries, staged as it is restored: still
/// sealed, they open with the restored ledger's own key, and are moved in
/// only with the checked database. A photo under a name the app does not
/// keep is skipped, and counted.
final class StagedPhotos {
  /// The photos staged in the vault's [staged] files.
  StagedPhotos(Directory staged)
    : _folder = Directory('${staged.path}/${AppFiles.receipts}');

  final Directory _folder;
  var _skipped = 0;

  /// Stages the photo [name] holding [bytes].
  Future<void> add(String name, List<int> bytes) async {
    if (!RegExp(r'^[\w.-]+$').hasMatch(name)) {
      _skipped++;
      return;
    }
    await _folder.create(recursive: true);
    await File('${_folder.path}/$name').writeAsBytes(bytes, flush: true);
  }

  /// Notes how many photos were skipped, when any were.
  void noteSkipped() {
    if (_skipped == 0) return;
    ErrorLog.instance.record(
      '還原備份',
      StateError('$_skipped files with names not kept were skipped'),
    );
  }
}
