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
        EntryViewCard(ledger: _ledger, entry: e, title: title, mode: _f.mode),
        const SizedBox(height: Space.s2),
        CardGrid(gap: 8, cells),
      ],
    );
  }
}
