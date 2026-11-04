part of 'composer.dart';

/// The spending a refund belongs to, at the top of the refund form.
class _OriginalTile extends StatelessWidget {
  const _OriginalTile({required this.ledger, required this.entry});

  final Ledger ledger;
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final currency = ledger.account(entry.account).currency;
    final category = ledger.category(entry.category);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Hue.tile,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          IconBadge(iconFor(category.icon), category.color, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '原支出 · ${entry.date.month}/${entry.date.day}',
                  style: mutedSmall,
                ),
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Text(
            '−${ledger.moneyIn(entry.amount, currency)}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Hue.negative,
            ),
          ),
        ],
      ),
    );
  }
}

class _TradeChips extends StatelessWidget {
  const _TradeChips({
    required this.trade,
    required this.locked,
    required this.onChanged,
  });

  final EntryType trade;
  final bool locked;
  final ValueChanged<EntryType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (type, label) in const [
          (EntryType.buy, '買進'),
          (EntryType.sell, '賣出'),
          (EntryType.dividend, '股息'),
        ])
          if (!locked || type == trade)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoicePill(
                label: label,
                selected: type == trade,
                onTap: locked ? null : () => onChanged(type),
              ),
            ),
      ],
    );
  }
}

/// One line of a trade's sums, such as its settlement day.
class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.color = Hue.ink});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13.5)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small white button in a block's heading, such as 拍照.
class _Chip extends StatelessWidget {
  const _Chip(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Small to look at, a full finger to tap.
    return TapArea(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Hue.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(label, style: accentLabel),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.label, {required this.solid});

  final String label;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: solid ? Hue.accent : Hue.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: solid ? Hue.onAccent : Hue.accent,
        ),
      ),
    );
  }
}

/// A merchant's name, typed or picked from those used before.
class _MerchantPicker extends StatefulWidget {
  const _MerchantPicker({required this.known, required this.initial});

  final List<String> known;
  final String initial;

  @override
  State<_MerchantPicker> createState() => _MerchantPickerState();
}

class _MerchantPickerState extends State<_MerchantPicker> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typed = _text.text.trim();
    final matches = [
      for (final name in widget.known)
        if (typed.isEmpty || name.toLowerCase().contains(typed.toLowerCase()))
          name,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _text,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          decoration: InputDecoration(
            hintText: '商家名稱',
            filled: true,
            fillColor: Hue.tile,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (typed.isNotEmpty && !widget.known.contains(typed))
                ListTile(
                  leading: const GlyphIcon(Glyph.add, color: Hue.accent),
                  title: Text('新增「$typed」'),
                  onTap: () => Navigator.of(context).pop(typed),
                ),
              for (final name in matches.take(12))
                ListTile(
                  leading: const GlyphIcon(Glyph.store, color: Hue.accent),
                  title: Text(name),
                  onTap: () => Navigator.of(context).pop(name),
                ),
              if (widget.initial.isNotEmpty)
                ListTile(
                  leading: const GlyphIcon(Glyph.close, color: Hue.muted),
                  title: const Text('不記商家'),
                  onTap: () => Navigator.of(context).pop(''),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tags to put on an entry: those in use, and new ones.
class _TagPicker extends StatefulWidget {
  const _TagPicker({required this.known, required this.initial});

  final List<String> known;
  final List<String> initial;

  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  late final _picked = [...widget.initial];
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    final tag = _text.text.trim().replaceAll('#', '');
    if (tag.isEmpty) return;
    setState(() {
      if (!_picked.contains(tag) && _picked.length < 16) _picked.add(tag);
      _text.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = {...widget.known, ..._picked}.toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in all)
              FilterChip(
                label: Text('#$tag'),
                selected: _picked.contains(tag),
                onSelected: (on) => setState(() {
                  if (on) {
                    if (_picked.length < 16) _picked.add(tag);
                  } else {
                    _picked.remove(tag);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: '新標籤',
                  filled: true,
                  fillColor: Hue.tile,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '加入',
              onPressed: _add,
              icon: const GlyphIcon(Glyph.add, color: Hue.accent),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_picked),
          style: FilledButton.styleFrom(
            backgroundColor: Hue.accent,
            minimumSize: const Size.fromHeight(44),
          ),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

/// The kinds of entry as words along the top, the chosen one underlined
/// in its colour; [onReset] adds 重填 at the end, as a mark.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.labels,
    required this.selected,
    required this.color,
    required this.onChanged,
    this.onReset,
  });

  final List<String> labels;
  final int selected;
  final Color color;
  final ValueChanged<int> onChanged;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final reset = onReset;
    return Row(
      children: [
        for (final (i, label) in labels.indexed)
          TapArea(
            selected: i == selected,
            onTap: () => onChanged(i),
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 10, right: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: i == selected ? Hue.ink : Hue.faint,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 22,
                    height: 3,
                    decoration: BoxDecoration(
                      color: i == selected ? color : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const Spacer(),
        if (reset != null)
          IconButton(
            tooltip: '重填',
            onPressed: reset,
            icon: const GlyphIcon(Glyph.reset, size: 20, color: Hue.faint),
          ),
      ],
    );
  }
}

/// The amount, centred, NT$ small at its foot; the calculator mark on
/// the right opens the keypad, as does a tap on the figure. [label] names
/// it for a screen reader, such as 金額 or 代墊金額. [under] goes below,
/// such as 常用.
class _AmountHero extends StatelessWidget {
  const _AmountHero({
    required this.label,
    required this.unit,
    required this.value,
    required this.color,
    required this.onTap,
    this.sub,
    this.under,
  });

  final String label;
  final String unit;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  final String? sub;
  final Widget? under;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    final note = sub;
    final below = under;
    // Two words with their feet level, so the figure reads on its own.
    // (Aligned to the end rather than to the baseline, which the sheet's
    // fill-the-height layout cannot measure.)
    final figure = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            unit,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Hue.faint,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            fontSize: 46,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: color,
          ),
        ),
      ],
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: 48),
            Expanded(
              child: Semantics(
                button: tap != null,
                label: label,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: tap,
                  child: FittedBox(fit: BoxFit.scaleDown, child: figure),
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: tap == null
                  ? null
                  : IconButton(
                      tooltip: label,
                      onPressed: tap,
                      style: IconButton.styleFrom(
                        backgroundColor: Hue.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      icon: const GlyphIcon(
                        Glyph.calculator,
                        size: 20,
                        color: Hue.muted,
                      ),
                    ),
            ),
          ],
        ),
        if (note != null)
          Text(note, textAlign: TextAlign.center, style: mutedSmall),
        if (below != null) ...[const SizedBox(height: 10), below],
      ],
    );
  }
}

/// Small rounded words under the amount, such as one of 常用.
class _Bubble extends StatelessWidget {
  const _Bubble(this.label, this.onTap, {this.color, this.ink});

  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? Hue.surface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: ink ?? Hue.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of [_Bubble]s, centred, sliding sideways when they do not fit.
class _Bubbles extends StatelessWidget {
  const _Bubbles(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// One square in a row of choices, such as a category or a holding: a
/// tinted mark over its name, ringed when [picked].
class _StripItem extends StatelessWidget {
  const _StripItem({
    required this.label,
    required this.color,
    required this.picked,
    required this.onTap,
    this.icon,
    this.code,
    this.solid = false,
    this.ring,
  });

  final String label;
  final Color color;
  final bool picked;
  final VoidCallback? onTap;
  final Glyph? icon;

  /// Words in place of the mark, white on [color], such as 0050.
  final String? code;

  /// Filled with [color] rather than tinted by it.
  final bool solid;

  /// The ring's colour when picked; the interface colour by default.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final mark = icon;
    final words = code;
    final filled = solid || words != null;
    return TapArea(
      onTap: onTap,
      selected: picked,
      child: SizedBox(
        width: 58,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: filled ? color : color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
                border: picked
                    ? Border.all(color: ring ?? Hue.accent, width: 2.5)
                    : null,
              ),
              child: words != null
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          words,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  : mark == null
                  ? null
                  : GlyphIcon(
                      mark,
                      size: 22,
                      color: solid ? Colors.white : color,
                    ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: picked ? FontWeight.w700 : FontWeight.w500,
                color: picked ? Hue.ink : Hue.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of [_StripItem]s that slides sideways, with [pinned] kept still
/// at its right end after a thin line, so it is never pushed out of view.
class _Strip extends StatelessWidget {
  const _Strip({required this.items, this.pinned});

  final List<Widget> items;
  final Widget? pinned;

  @override
  Widget build(BuildContext context) {
    final still = pinned;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: items),
            ),
          ),
          if (still != null) ...[
            Container(
              width: 1,
              height: 44,
              margin: const EdgeInsets.only(top: 6, left: 4, right: 4),
              color: Hue.line,
            ),
            still,
          ],
        ],
      ),
    );
  }
}

/// The parts of a split as one bar: each a stretch as wide as its share,
/// with its name and amount on it; a tap opens that part's amount.
class _AllocationBar extends StatelessWidget {
  const _AllocationBar({required this.parts, required this.onTap});

  final List<(Category, int)> parts;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 56,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, (category, amount)) in parts.indexed) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                flex: amount <= 0 ? 1 : amount,
                child: Material(
                  color: category.color,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            category.name,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            groupDigits(amount),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A white card with a mark and what was chosen, such as the account or
/// the day; [label] names it for a screen reader.
class _Pick extends StatelessWidget {
  const _Pick({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.iconColor = Hue.accent,
    this.valueColor = Hue.ink,
  });

  final Glyph icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Color iconColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      label: '$label：$value',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: Hue.tileShadow,
        ),
        child: Material(
          color: Hue.white,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    IconChip(icon, color: iconColor, background: Hue.tile),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: valueColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One end of a transfer: the account's mark and name, and what it will
/// hold once the transfer is made; [end] lays it out from the right.
class _TransferEnd extends StatelessWidget {
  const _TransferEnd({
    required this.account,
    required this.after,
    required this.label,
    required this.onTap,
    this.end = false,
  });

  final Account account;

  /// What the account holds afterwards, as words.
  final String after;

  /// What a screen reader calls it: 轉出帳戶 or 轉入帳戶.
  final String label;
  final VoidCallback onTap;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final color = accountColor(account.kind);
    final radius = BorderRadius.circular(18);
    final badge = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Hue.white,
        borderRadius: BorderRadius.circular(11),
      ),
      child: GlyphIcon(accountIcon(account), size: 18, color: color),
    );
    final text = Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          account.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        Text(
          after,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Hue.muted),
        ),
      ],
    );
    return Semantics(
      button: true,
      label: '$label：${account.name}，$after',
      excludeSemantics: true,
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: end
                    ? [Expanded(child: text), const SizedBox(width: 8), badge]
                    : [badge, const SizedBox(width: 8), Expanded(child: text)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card to tap for a figure of a trade, such as 股數, its name over
/// the figure; ringed while [current].
class _Figure extends StatelessWidget {
  const _Figure({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.current = false,
  });

  final Glyph icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: Hue.tileShadow,
      ),
      child: Material(
        color: Hue.white,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: current
              ? const BorderSide(color: Hue.investment, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconChip(icon, color: Hue.investment, background: Hue.tile),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Hue.investment,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Hue.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small words that open a figure to change it, with a pen after them.
class _EditWords extends StatelessWidget {
  const _EditWords(this.words, this.onTap);

  final String words;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    final text = Text.rich(
      TextSpan(
        text: words,
        children: [
          if (tap != null)
            const TextSpan(
              text: ' ✎',
              style: TextStyle(color: Hue.accent),
            ),
        ],
      ),
      style: mutedSmall,
    );
    if (tap == null) return text;
    return TapArea(
      onTap: tap,
      child: Align(alignment: Alignment.centerLeft, child: text),
    );
  }
}

/// A colour of its own for each holding's code, the same every time.
Color _codeColor(String code) {
  var sum = 0;
  for (final unit in code.codeUnits) {
    sum = (sum * 31 + unit) & 0x7fffffff;
  }
  return Hue.categoryColors[sum % Hue.categoryColors.length];
}

/// One holding in the list of them: its code as a coloured mark, its
/// name and how many shares are held.
class _HoldingRow extends StatelessWidget {
  const _HoldingRow({
    required this.code,
    required this.name,
    required this.held,
    required this.color,
    required this.picked,
    required this.onTap,
  });

  final String code;
  final String name;
  final String held;
  final Color color;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: picked ? Hue.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      code,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(held, style: mutedSmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
