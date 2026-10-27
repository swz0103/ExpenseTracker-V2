import 'dart:io';
import 'dart:ui' show Codec, ImmutableBuffer;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:vault/backup_security.dart';

import '../../features/entries/model/receipt_photos.dart';
import 'channel.dart';

/// Receipt photos in the app's private `receipts` folder, each sealed
/// with the ledger's [FileBox], so a photo is as private as the ledger.
/// The phone makes a photo smaller first (`MainActivity.kt`). Photos kept
/// before sealing (`.jpg`) still show.
final class AndroidReceipts implements ReceiptPhotos {
  const AndroidReceipts(this.directory, this.box);

  final Directory directory;
  final FileBox box;

  Directory get _folder => Directory('${directory.path}/receipts');

  @override
  Future<String?> take({required bool camera}) async {
    final ready = await platformChannel.invokeMethod<String>('takePhoto', {
      'camera': camera,
    });
    if (ready == null) return null;
    final source = File(ready);
    try {
      final name = '${DateTime.now().millisecondsSinceEpoch}.etr';
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
