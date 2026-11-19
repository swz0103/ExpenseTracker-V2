import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/diagnostics/error_log.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/shape.dart';
import '../../../core/look/spacing.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../model/receipt_photos.dart';
import '../../../core/text/words.dart';

/// Shows [image] over the page, to pinch and zoom; a tap closes it.
Future<void> showReceipt(BuildContext context, ImageProvider image) =>
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(Space.s3),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            maxScale: 5,
            child: Image(image: image, fit: BoxFit.contain),
          ),
        ),
      ),
    );

/// The receipt of an entry as a square: an outline with 收據 to take or
/// pick a photo while there is none ([onTaken] gets its name; one that
/// cannot be had is recorded, and [onFailed] told whether it was the
/// camera), else the photo, tapped to see it whole, with a cross to
/// [onRemove] it while [removable].
class ReceiptSquare extends StatelessWidget {
  const ReceiptSquare({
    super.key,
    required this.photos,
    required this.receipt,
    required this.color,
    required this.removable,
    required this.onTaken,
    required this.onFailed,
    required this.onRemove,
  });

  final ReceiptPhotos photos;
  final String? receipt;
  final Color color;
  final bool removable;
  final ValueChanged<String> onTaken;
  final void Function({required bool camera}) onFailed;
  final VoidCallback onRemove;

  static const _size = 84.0;

  Future<void> _take({required bool camera}) async {
    try {
      final name = await photos.take(camera: camera);
      if (name != null) onTaken(name);
    } on Object catch (error) {
      ErrorLog.instance.record('收據照片', error);
      onFailed(camera: camera);
    }
  }

  /// 拍照 or 從相簿, in a panel; null when it is closed.
  Future<bool?> _askSource(BuildContext context) => showPanel<bool>(
    context,
    (context) => CenterPanel(
      glyph: Glyph.camera,
      color: color,
      title: Words.receipt,
      body: CardGrid([
        for (final (glyph, word, camera) in [
          (Glyph.camera, '拍照', true),
          (Glyph.image, '從相簿', false),
        ])
          ColorCard(
            key: Keys.receiptSource(camera: camera),
            color: color,
            label: word,
            onTap: () => Navigator.of(context).pop(camera),
            child: Column(
              children: [
                SquareIcon(glyph, color),
                const SizedBox(height: Space.s2),
                OneLine(
                  word,
                  style: const TextStyle(
                    fontSize: TextSize.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final shown = receipt;
    if (shown == null) {
      return TapArea(
        key: Keys.receipt,
        label: Words.receipt,
        onTap: () async {
          final camera = await _askSource(context);
          if (camera != null) await _take(camera: camera);
        },
        child: Container(
          width: _size,
          constraints: const BoxConstraints(minHeight: _size),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.large),
            border: Border.all(color: Hue.line, width: 1.5),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlyphIcon(Glyph.camera, size: 22, color: Hue.muted),
              SizedBox(height: Space.s1),
              Text(
                Words.receipt,
                style: TextStyle(
                  fontSize: TextSize.caption,
                  fontWeight: FontWeight.w700,
                  color: Hue.muted,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        TapArea(
          label: '查看收據',
          onTap: () => unawaited(showReceipt(context, photos.image(shown))),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.large),
            child: Image(
              image: photos.image(shown),
              width: _size,
              height: _size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                width: _size,
                height: _size,
                child: Center(child: GlyphIcon(Glyph.image, color: Hue.faint)),
              ),
            ),
          ),
        ),
        if (removable)
          Positioned(
            right: -10,
            top: -10,
            child: IconButton(
              tooltip: '移除收據',
              onPressed: onRemove,
              style: IconButton.styleFrom(backgroundColor: Hue.white),
              icon: const GlyphIcon(Glyph.close, size: 14, color: Hue.muted),
            ),
          ),
      ],
    );
  }
}
