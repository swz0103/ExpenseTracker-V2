import 'dart:io';

/// Deletes plain copies an earlier run may have left behind when it was
/// stopped part way: files waiting in `exports` to be handed over (a
/// backup with photos, a CSV), and, in [cache], the camera's photo before
/// it was sealed, the photo made smaller, and the copy of a chosen backup
/// or file (`MainActivity.kt`). Runs at start, before anything is written
/// there again.
Future<void> clearLeftovers(Directory files, {Directory? cache}) async {
  final leftovers = <FileSystemEntity>[
    Directory('${files.path}/exports'),
    if (cache != null) ...[
      Directory('${cache.path}/camera'),
      File('${cache.path}/receipt-ready.jpg'),
      File('${cache.path}/restore.etbk'),
    ],
  ];
  for (final leftover in leftovers) {
    try {
      if (await leftover.exists()) await leftover.delete(recursive: true);
    } on FileSystemException {
      // Tried again at the next start.
    }
  }
}
