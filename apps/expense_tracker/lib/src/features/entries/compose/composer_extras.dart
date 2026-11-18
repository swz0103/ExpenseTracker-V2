part of 'composer.dart';

// The fold at the foot of the form: merchant, tags, note and receipt.

extension _Extras on _ComposerState {
  /// The merchant, tags, note and receipt under one heading at the foot
  /// of the form, opened and closed with it; closed, the heading shows
  /// what is filled in. Open, they are no list: the note a large box with
  /// the receipt beside it, merchants and tags words to tap in a row.
  Widget _extras(bool expense) {
    final filled = [
      if (expense && _f.merchant.isNotEmpty) _f.merchant,
      for (final tag in _f.tags) '#$tag',
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
      if (_f.receipt != null) '收據',
    ];
    final photos = widget.photos;
    final withPhoto = photos != null || _f.receipt != null;
    if (_viewing && filled.isEmpty) return const SizedBox.shrink();
    final open = _f.more || _viewing;
    final names = [if (expense) '商家', '標籤', '備註', if (withPhoto) '收據'];
    return _fold(
      key: Keys.extras,
      closed: filled.isEmpty ? names.join('、') : filled.join(' · '),
      open: open,
      body: [
        // The square as tall as the note box and level with it.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _noteField(lines: 3)),
              if (photos != null && (!_viewing || _f.receipt != null)) ...[
                const SizedBox(width: Space.s2),
                Padding(
                  padding: const EdgeInsets.only(top: Space.s2),
                  child: _receiptSquare(photos),
                ),
              ],
            ],
          ),
        ),
        if (expense && (!_viewing || _f.merchant.isNotEmpty)) ...[
          const GroupLabel('商家'),
          WordRow([
            for (final name in _merchantChoices())
              WordChip(
                name,
                () => _set(() {
                  if (name == _f.merchant) {
                    _f.merchant = '';
                  } else {
                    _f.pickMerchant(name);
                  }
                }),
                color: _color,
                picked: name == _f.merchant,
              ),
            if (!_viewing) WordChip('＋', _pickMerchant, color: _color),
          ]),
        ],
        if (!_viewing || _f.tags.isNotEmpty) ...[
          const GroupLabel('標籤'),
          WordRow([
            for (final tag in _tagChoices())
              WordChip(
                '#$tag',
                () => _set(() {
                  _f.tags = _f.tags.contains(tag)
                      ? [
                          for (final t in _f.tags)
                            if (t != tag) t,
                        ]
                      : [..._f.tags, tag];
                }),
                color: _color,
                picked: _f.tags.contains(tag),
              ),
            if (!_viewing) WordChip('＋', _pickTags, color: _color),
          ]),
        ],
      ],
    );
  }

  /// The merchants to tap: the one chosen first, then the most used.
  List<String> _merchantChoices() {
    final known = _ledger.entryQueryService.merchants.take(8).toList();
    final chosen = _f.merchant;
    return [
      if (chosen.isNotEmpty) chosen,
      for (final name in known)
        if (name != chosen) name,
    ];
  }

  /// The tags to tap: those on the entry first, then the others in use.
  List<String> _tagChoices() => [
    ..._f.tags,
    for (final tag in _ledger.reportService.tags.take(8))
      if (!_f.tags.contains(tag)) tag,
  ];

  /// A heading at the foot of the form that opens and closes [body]:
  /// closed, [closed] says what is in it.
  Widget _fold({
    Key? key,
    required String closed,
    required bool open,
    required List<Widget> body,
  }) {
    // Looked at, there is nothing to open or close: what is filled in
    // shows, with no heading repeating it.
    if (_viewing) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.s1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: body,
        ),
      );
    }
    final heading = InkWell(
      key: key,
      borderRadius: BorderRadius.circular(Radii.medium),
      onTap: _viewing ? null : () => _set(() => _f.more = !_f.more),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s1,
          vertical: Space.s3,
        ),
        child: Row(
          children: [
            const GlyphIcon(Glyph.note, size: 18, color: Hue.muted),
            const SizedBox(width: Space.s2),
            Expanded(
              child: Text(
                closed,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: TextSize.body,
                  fontWeight: open ? FontWeight.w700 : FontWeight.w600,
                  color: open ? Hue.ink : Hue.muted,
                ),
              ),
            ),
            if (!_viewing)
              RotatedBox(
                quarterTurns: open ? 3 : 1,
                child: const GlyphIcon(Glyph.next, size: 16, color: Hue.faint),
              ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: Space.s1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: body,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// The receipt photo as a square beside the note: its thumbnail, which
  /// opens it whole, or a camera mark that asks for one.
  Widget _receiptSquare(ReceiptPhotos photos) {
    final receipt = _f.receipt;
    Future<void> take({required bool camera}) async {
      try {
        final name = await photos.take(camera: camera);
        if (name != null) _set(() => _f.receipt = name);
      } on Object catch (error) {
        ErrorLog.instance.record('收據照片', error);
        _set(() => _problem = camera ? '無法開啟相機' : '無法讀取這張照片');
      }
    }

    const size = 84.0;
    if (receipt == null) {
      return TapArea(
        label: '收據',
        onTap: () async {
          final camera = await showPanel<bool>(
            context,
            (context) => CenterPanel(
              glyph: Glyph.camera,
              color: _color,
              title: '收據',
              body: CardGrid([
                for (final (glyph, word, camera) in [
                  (Glyph.camera, '拍照', true),
                  (Glyph.image, '從相簿', false),
                ])
                  ColorCard(
                    color: _color,
                    label: word,
                    onTap: () => Navigator.of(context).pop(camera),
                    child: Column(
                      children: [
                        SquareIcon(glyph, _color),
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
          if (camera != null) await take(camera: camera);
        },
        child: Container(
          width: size,
          constraints: const BoxConstraints(minHeight: size),
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
                '收據',
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
          onTap: () => unawaited(_showReceipt(photos.image(receipt))),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.large),
            child: Image(
              image: photos.image(receipt),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                width: size,
                height: size,
                child: Center(child: GlyphIcon(Glyph.image, color: Hue.faint)),
              ),
            ),
          ),
        ),
        if (!_viewing)
          Positioned(
            right: -10,
            top: -10,
            child: IconButton(
              tooltip: '移除收據',
              onPressed: () => _set(() => _f.receipt = null),
              style: IconButton.styleFrom(backgroundColor: Hue.white),
              icon: const GlyphIcon(Glyph.close, size: 14, color: Hue.muted),
            ),
          ),
      ],
    );
  }

  /// The whole receipt, to zoom into.
  Future<void> _showReceipt(ImageProvider image) => showDialog<void>(
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
}
