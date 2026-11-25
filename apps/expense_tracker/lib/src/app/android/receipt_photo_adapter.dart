import 'dart:io';
import 'dart:ui' show Codec, ImmutableBuffer;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:vault/backup_security.dart';

import '../../features/entries/model/receipt_photos.dart';
import 'platform_channel.dart';
import '../../core/diagnostics/error_log.dart';
import '../../core/diagnostics/error_steps.dart';
import '../../core/messages/problem_messages.dart' show QuietStep;
import '../../core/platform/errands.dart';
import '../../core/time/app_clock.dart';

/// Receipt photos in the app's private `receipts` folder, each sealed
/// with the ledger's [FileBox], so a photo is as private as the ledger.
/// The phone makes a photo smaller first (`MainActivity.kt`). Photos kept
/// before sealing (`.jpg`) still show.
final class AndroidReceipts implements ReceiptPhotos {
  const AndroidReceipts(this.directory, this.box, {required this.failed});

  final Directory directory;
  final FileBox box;

  /// Told when the photo the camera left could not be taken back
  /// (QuietFailures, D84).
  final void Function(QuietStep step) failed;

  Directory get _folder => Directory('${directory.path}/receipts');

  @override
  Future<String?> take({required bool camera}) async => _seal(
    // The camera and the album are trips out of the app.
    await Errands.run(
      () =>
          platformChannel.invokeMethod<String>('takePhoto', {'camera': camera}),
    ),
  );

  @override
  Future<String?> takeLeftover() async {
    try {
      return await _seal(
        await platformChannel.invokeMethod<String>('takeLeftoverPhoto'),
      );
    } on Object catch (error) {
      ErrorLog.instance.record(ErrorSteps.receiptPhoto, error);
      failed(QuietStep.leftoverPhoto);
      return null;
    }
  }

  /// Seals the photo made ready at [ready] into the receipts folder and
  /// deletes the plain copy.
  Future<String?> _seal(String? ready) async {
    if (ready == null) return null;
    final source = File(ready);
    try {
      final name = '${AppClock.now().millisecondsSinceEpoch}.etr';
      await _folder.create(recursive: true);
      final sealed = await box.seal(name, await source.readAsBytes());
      await File('${_folder.path}/$name').writeAsBytes(sealed, flush: true);
      return name;
    } finally {
      if (source.existsSync()) await source.delete();
    }
  }

  @override
  ImageProvider image(String name) {
    final file = File('${_folder.path}/$name');
    return name.endsWith('.jpg') ? FileImage(file) : _SealedImage(file, box);
  }
}

/// A sealed photo, opened as it is drawn; the plain bytes stay in memory.
final class _SealedImage extends ImageProvider<_SealedImage> {
  const _SealedImage(this.file, this.box);

  final File file;
  final FileBox box;

  @override
  Future<_SealedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _SealedImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _open(decode), scale: 1);

  Future<Codec> _open(ImageDecoderCallback decode) async {
    final name = file.path.split('/').last;
    final plain = await box.open(name, await file.readAsBytes());
    return decode(await ImmutableBuffer.fromUint8List(plain));
  }

  @override
  bool operator ==(Object other) =>
      other is _SealedImage && other.file.path == file.path;

  @override
  int get hashCode => file.path.hashCode;
}
