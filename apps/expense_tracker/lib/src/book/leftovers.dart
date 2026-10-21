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

/// Deletes the sealed receipt photos in [files]' `receipts` folder that no
/// entry keeps any more, [kept] being those still linked (deleted entries'
/// included until they leave the trash): a photo replaced or taken away,
/// or one taken for an entry that was never saved.
Future<void> sweepReceipts(Directory files, Set<String> kept) async {
  final folder = Directory('${files.path}/receipts');
  if (!await folder.exists()) return;
  await for (final entity in folder.list()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (kept.contains(name)) continue;
    try {
      await entity.delete();
    } on FileSystemException {
      // Tried again at the next start.
    }
  }
}
