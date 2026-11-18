part of 'composer.dart';

// The receipt beside the note, which reports to the form what it could
// not do.

extension _Extras on _ComposerState {
  /// The receipt photo as a square beside the note: its thumbnail, which
  /// opens it whole, or a camera mark that asks for one.
  Widget _receiptSquare(ReceiptPhotos photos) => ReceiptSquare(
    photos: photos,
    receipt: _f.receipt,
    color: _color,
    removable: !_viewing,
    onTaken: (name) => _set(() => _f.receipt = name),
    onFailed: ({required camera}) =>
        _set(() => _problem = camera ? '無法開啟相機' : '無法讀取這張照片'),
    onRemove: () => _set(() => _f.receipt = null),
  );
}
