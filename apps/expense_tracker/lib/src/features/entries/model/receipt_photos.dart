import 'package:flutter/widgets.dart';

/// Receipt photos the phone keeps beside the ledger, by file name.
abstract interface class ReceiptPhotos {
  /// Takes a photo with the camera, or picks one from the gallery; the
  /// kept file's name, or null when the person cancels.
  Future<String?> take({required bool camera});

  /// A photo the camera took while the phone closed the app, kept the
  /// same way as one [take] returns; null when there is none, or when it
  /// could not be taken back, which the phone's side records and tells
  /// by itself (D84): this does not throw.
  Future<String?> takeLeftover();

  ImageProvider image(String name);
}
