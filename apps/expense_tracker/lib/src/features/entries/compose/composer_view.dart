part of 'composer.dart';

// An entry looked at: its own card, not the form it was written with.

extension _View on _ComposerState {
  /// The entry [e] as it stands: a card in its colour with its mark, what
  /// kind it is, its name and amount; then a tile for each thing written
  /// with it, two to a row. Nothing that was left empty shows, and a
  /// merchant or tag shows alone, not among the others to choose from.
  Widget _view(Entry e) {
    final title = entryTitle(_ledger, e);
    final photos = widget.photos;
    final receipt = _f.receipt;
    final cells = <Widget>[
      for (final (label, value) in entryDetails(_ledger, e, title))
        ViewFieldTile(label: label, value: value),
      if (photos != null && receipt != null)
        TapArea(
          label: '查看收據',
          onTap: () => unawaited(_showReceipt(photos.image(receipt))),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.large),
            child: Image(
              image: photos.image(receipt),
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const ViewFieldTile(label: '收據', value: '—'),
            ),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_marks.isNotEmpty || e.recurring != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: Wrap(
              spacing: 6,
              children: [
                if (e.recurring != null) const Pill('定期'),
                for (final (label, c) in _marks) Pill(label, color: c),
              ],
            ),
          ),
        _viewCard(e, title),
        const SizedBox(height: Space.s2),
        CardGrid(gap: 8, cells),
      ],
    );
  }

  /// The card on top of an entry looked at: in its colour with its mark,
  /// what kind it is, what it is called, and its amount.
  Widget _viewCard(Entry e, String title) {
    final category = _ledger.category(e.category);
    final mode = _f.mode;
    final trade = e.type.index >= EntryType.buy.index;
    final (Glyph glyph, Color color) = switch (e.type) {
      EntryType.transfer => (Glyph.transfer, Hue.transfer),
      _ when trade => (Glyph.investment, Hue.investment),
      _ => (iconFor(category.icon), shownColor(Color(category.color))),
    };
    final kind = switch (e.type) {
      EntryType.transfer => mode.label,
      _ when trade => mode.label,
      _ => '${mode.label} · ${category.name}',
    };
    final currency = _ledger.account(e.account).currency;
    return ColorCard(
      color: color,
      radius: Radii.largeIncreased,
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s4,
        Space.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SquareIcon(glyph, color, size: 52),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OneLine(kind, style: mutedSmall),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: TextSize.title,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${entrySign(e.type)}${_ledger.moneyIn(e.amount, currency)}',
              style: TextStyle(
                fontSize: TextSize.big,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: e.type == EntryType.transfer ? Hue.ink : mode.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
