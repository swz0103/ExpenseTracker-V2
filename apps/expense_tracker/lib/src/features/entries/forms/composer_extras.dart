import 'package:flutter/material.dart';

import '../model/receipt_photos.dart';
import 'receipt_square.dart';
import 'composer_state.dart';

// The receipt beside the note, which reports to the form what it could
// not do.

extension ComposerExtras on ComposerState {
  /// The receipt photo as a square beside the note: its thumbnail, which
  /// opens it whole, or a camera mark that asks for one.
  Widget receiptBeside(ReceiptPhotos photos) => ReceiptSquare(
    photos: photos,
    receipt: form.receipt,
    color: color,
    removable: !viewing,
    onTaken: (name) => update(() => form.receipt = name),
    onFailed: ({required camera}) =>
        update(() => shownProblem = camera ? '無法開啟相機' : '無法讀取這張照片'),
    onRemove: () => update(() => form.receipt = null),
  );
}
