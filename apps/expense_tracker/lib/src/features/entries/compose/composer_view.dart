part of 'composer.dart';

// An entry looked at: its own card, not the form it was written with.

extension _View on _ComposerState {
  /// The entry [e] as it stands: a card in its colour with its mark, what
  /// kind it is, its name and amount; then a tile for each thing written
  /// with it, two to a row. Nothing that was left empty shows, and a
  /// merchant or tag shows alone, not among the others to choose from.
  Widget _view(Entry e) {
    final ledger = _ledger;
    final account = ledger.account(e.account);
    final category = ledger.category(e.category);
    final mode = _f.mode;
    final tone = mode.color;
    final trade = e.type.index >= EntryType.buy.index;
    final (Glyph glyph, Color color) = switch (e.type) {
      EntryType.transfer => (Glyph.transfer, Hue.transfer),
      _ when trade => (Glyph.investment, Hue.investment),
      _ => (iconFor(category.icon), shownColor(Color(category.color))),
    };
    final sign = switch (e.type) {
      EntryType.expense || EntryType.buy => '−',
      EntryType.income || EntryType.sell || EntryType.dividend => '+',
      EntryType.transfer => '',
    };
    final kind = switch (e.type) {
      EntryType.transfer => mode.label,
      _ when trade => mode.label,
      _ => '${mode.label} · ${category.name}',
    };
    final title = switch (e.type) {
      EntryType.transfer =>
        '${account.name} → ${ledger.account(e.to ?? '').name}',
      _ when trade => e.holding ?? e.title,
      _ => e.title,
    };
    final tiles = <(String, String)>[
      if (e.type != EntryType.transfer) ('帳戶', account.name),
      ('日期', formatMMMEd(e.date)),
      if (e.merchant.isNotEmpty) ('商家', e.merchant),
      if (e.tags.isNotEmpty) ('標籤', e.tags.map((t) => '#$t').join(' ')),
      if (e.parts.isNotEmpty)
        (
          '拆分',
          [for (final (name, v) in e.parts) '$name ${groupDigits(v)}']
              .join('、'),
        ),
      if (e.installments > 1)
        (
          '分期',
          '${e.installments} 期 · 每期 ${groupDigits(e.amount ~/ e.installments)}',
        ),
      if (e.shares != 0) ('股數', '${groupDigits(e.shares.abs())} 股'),
      if (e.fee > 0) ('手續費', groupDigits(e.fee)),
      if (e.tax > 0)
        (e.type == EntryType.dividend ? '二代健保' : '稅', groupDigits(e.tax)),
      if (e.home != null) ('折合台幣', groupDigits(e.home!)),
      if (e.type == EntryType.transfer && e.received != null)
        ('轉入金額', amountIn(e.received!, ledger.account(e.to ?? '').currency)),
      if (e.note.isNotEmpty && e.note != title) ('備註', e.note),
    ];
    final photos = widget.photos;
    final receipt = _f.receipt;
    final cells = <Widget>[
      for (final (label, value) in tiles) _ViewTile(label: label, value: value),
      if (photos != null && receipt != null)
        TapArea(
          label: '查看收據',
          onTap: () => unawaited(_showReceipt(photos.image(receipt))),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image(
              image: photos.image(receipt),
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const _ViewTile(label: '收據', value: '—'),
            ),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_marks.isNotEmpty || e.recurring != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              children: [
                if (e.recurring != null) const Pill('定期'),
                for (final (label, c) in _marks) Pill(label, color: c),
              ],
            ),
          ),
        ColorCard(
          color: color,
          radius: 22,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SquareIcon(glyph, color, size: 52),
                  const SizedBox(width: 12),
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
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$sign${ledger.moneyIn(e.amount, account.currency)}',
                  style: TextStyle(
                    fontSize: TextSize.big,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: e.type == EntryType.transfer ? Hue.ink : tone,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        CardGrid(gap: 8, cells),
      ],
    );
  }
}

/// One thing written with an entry: its name small, what it is under.
class _ViewTile extends StatelessWidget {
  const _ViewTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: Hue.group,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OneLine(
          label,
          style: const TextStyle(fontSize: TextSize.caption, color: Hue.muted),
        ),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: TextSize.body,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
