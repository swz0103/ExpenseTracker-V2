import 'package:flutter/widgets.dart';

/// Receipt photos the phone keeps beside the ledger, by file name.
abstract interface class ReceiptPhotos {
  /// Takes a photo with the camera, or picks one from the gallery; the
  /// kept file's name, or null when the person cancels.
  Future<String?> take({required bool camera});

  ImageProvider image(String name);
}
