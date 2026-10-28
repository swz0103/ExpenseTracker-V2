import 'dart:io';

/// Deletes plain copies an earlier run may have left behind when it was
/// stopped part way: files waiting in `exports` to be handed over (a
/// backup with photos, a CSV), and, in [cache], the camera's photo before
/// it was sealed, the photo made smaller, and the copy of a chosen backup
/// or file (`PhotosPart.kt`, `FilesPart.kt`). Runs at start, before
/// anything is written there again.
///
/// A photo the camera took while the phone closed the app is kept for a
/// day for 記一筆 to take back (`receipt-leftover.jpg`), and the camera's
/// own file while it may still be on its way there.
Future<void> clearLeftovers(
  Directory files, {
  Directory? cache,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  bool older(FileSystemEntity entity, Duration than) {
    try {
      return at.difference(entity.statSync().modified) > than;
    } on FileSystemException {
      return true;
    }
  }

  final camera = cache == null ? null : Directory('${cache.path}/camera');
  final leftovers = <FileSystemEntity>[
    Directory('${files.path}/exports'),
    if (camera != null && camera.existsSync())
      for (final photo in camera.listSync())
        if (older(photo, const Duration(minutes: 5))) photo,
    if (cache != null) ...[
      File('${cache.path}/receipt-ready.jpg'),
      File('${cache.path}/restore.etbk'),
      // A newer version handed to the installer: installed, or not wanted.
      Directory('${cache.path}/updates'),
      for (final kept in [File('${cache.path}/receipt-leftover.jpg')])
        if (older(kept, const Duration(days: 1))) kept,
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
