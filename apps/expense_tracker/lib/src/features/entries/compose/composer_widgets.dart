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

/// A merchant's name, typed or picked from those used before.
class _MerchantPicker extends StatefulWidget {
  const _MerchantPicker({
    required this.known,
    required this.initial,
    required this.onDone,
  });

  final List<String> known;
  final String initial;
  final ValueChanged<String> onDone;

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
          onSubmitted: (value) => widget.onDone(value.trim()),
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
        Column(
          children: [
            if (typed.isNotEmpty && !widget.known.contains(typed))
              ListTile(
                leading: const GlyphIcon(Glyph.add, color: Hue.accent),
                title: Text('新增「$typed」'),
                onTap: () => widget.onDone(typed),
              ),
            for (final name in matches.take(12))
              ListTile(
                leading: const GlyphIcon(Glyph.store, color: Hue.accent),
                title: Text(name),
                onTap: () => widget.onDone(name),
              ),
            if (widget.initial.isNotEmpty)
              ListTile(
                leading: const GlyphIcon(Glyph.close, color: Hue.muted),
                title: const Text('不記商家'),
                onTap: () => widget.onDone(''),
              ),
          ],
        ),
      ],
    );
  }
}

/// Tags to put on an entry: those in use, and new ones.
class _TagPicker extends StatefulWidget {
  const _TagPicker({
    required this.known,
    required this.initial,
    required this.onDone,
  });

  final List<String> known;
  final List<String> initial;
  final ValueChanged<List<String>> onDone;

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
          onPressed: () => widget.onDone(_picked),
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

/// The kinds of entry along the top, sharing the width; the chosen one
/// in ink over a thick line of its colour, the others faint over a thin
/// one. [onReset] adds 重填 at the end, level with the words.
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
    Widget cell(Widget child, {required bool on}) => Container(
      height: 48,
      alignment: Alignment.center,
      foregroundDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: on ? color : Hue.line, width: on ? 3 : 1),
        ),
      ),
      child: child,
    );
    return Row(
      children: [
        for (final (i, label) in labels.indexed)
          Expanded(
            child: TapArea(
              selected: i == selected,
              onTap: () => onChanged(i),
              child: cell(
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: i == selected ? Hue.ink : Hue.faint,
                  ),
                ),
                on: i == selected,
              ),
            ),
          ),
        if (reset != null)
          SizedBox(
            width: 48,
            child: cell(
              IconButton(
                tooltip: '重填',
                onPressed: reset,
                icon: const GlyphIcon(Glyph.reset, size: 20, color: Hue.faint),
              ),
              on: false,
            ),
          ),
      ],
    );
  }
}

/// The title of a choice opened inside the sheet, centred, with the
/// arrow back to the form on its left.
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Hue.line)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: onBack,
            icon: const GlyphIcon(Glyph.back, size: 20, color: Hue.muted),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
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
        if (below != null) ...[const SizedBox(height: 12), below],
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

/// One square in a row of choices, such as a category: a grey mark over
/// its name, tinted and ringed in [color] when [picked]; [solid] fills it
/// with [color] instead, such as 拆分中.
class _StripItem extends StatelessWidget {
  const _StripItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.picked,
    required this.onTap,
    this.solid = false,
  });

  final String label;
  final Glyph icon;
  final Color color;
  final bool picked;
  final VoidCallback? onTap;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final lit = picked || solid;
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
                color: solid
                    ? color
                    : picked
                    ? color.withValues(alpha: 0.14)
                    : Hue.surface,
                borderRadius: BorderRadius.circular(16),
                border: picked ? Border.all(color: color, width: 2) : null,
              ),
              child: GlyphIcon(
                icon,
                size: 22,
                color: solid
                    ? Colors.white
                    : picked
                    ? color
                    : Hue.muted,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: lit ? FontWeight.w700 : FontWeight.w500,
                color: lit ? color : Hue.muted,
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
            // Centred on the 50 dp squares beside it, not on their words.
            Container(
              width: 1,
              height: 34,
              margin: const EdgeInsets.only(top: 8, left: 4, right: 4),
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
      // 56 high, taller when the phone's text is larger.
      child: IntrinsicHeight(
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
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              category.name,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: wordsOn(category.color),
                              ),
                            ),
                            Text(
                              groupDigits(amount),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: wordsOn(category.color),
                              ),
                            ),
                          ],
                        ),
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
    this.valueColor = Hue.ink,
  });

  final Glyph icon;
  final String label;
  final String value;
  final VoidCallback onTap;
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
                    IconChip(icon, color: Hue.muted, background: Hue.tile),
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

/// One end of a transfer on a grey card: the account's mark on the left,
/// its name over what it will hold once the transfer is made. [end] is
/// the right-hand card, with room on its inner side for the arrow.
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
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      label: '$label：${account.name}，$after',
      excludeSemantics: true,
      child: Material(
        color: Hue.surface,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: EdgeInsets.fromLTRB(end ? 22 : 12, 9, end ? 10 : 22, 9),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Hue.white,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: GlyphIcon(
                      accountIcon(account),
                      size: 17,
                      color: Hue.muted,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          after,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Hue.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A white card to tap for a figure of a trade, such as 股數: a grey
/// mark and the name on the left, the figure large on the right; ringed
/// while [current].
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
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: current
                ? const BorderSide(color: Hue.investment, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    IconChip(icon, color: Hue.muted, background: Hue.tile),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Hue.muted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          value,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Hue.ink,
                          ),
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

/// One sum in the line a trade settles at, such as 成交 1,000: its name
/// over the figure; white with a pen when it can be changed.
class _EqBox extends StatelessWidget {
  const _EqBox(this.label, this.value, this.onTap);

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    final radius = BorderRadius.circular(14);
    return Semantics(
      button: tap != null,
      label: '$label：$value',
      excludeSemantics: true,
      child: Material(
        color: tap == null ? Hue.surface : Hue.white,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: tap == null
              ? BorderSide.none
              : const BorderSide(color: Hue.line),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: tap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Hue.muted,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tap == null ? value : '$value ✎',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A holding as a pill in one row: its code bold, then its name cut
/// short; tinted and ringed when [picked].
class _CodePill extends StatelessWidget {
  const _CodePill({
    required this.code,
    required this.name,
    required this.picked,
    required this.onTap,
  });

  final String code;
  final String name;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      onTap: onTap,
      selected: picked,
      label: '$code $name',
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: picked ? Hue.investment.withValues(alpha: 0.12) : Hue.surface,
          borderRadius: BorderRadius.circular(13),
          border: picked ? Border.all(color: Hue.investment, width: 2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              code,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: picked ? Hue.investment : Hue.ink,
              ),
            ),
            if (name.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  color: picked ? Hue.investment : Hue.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A holding's name cut to four characters at most, without the fund
/// house it starts with, such as 台灣50 for 元大台灣50.
String _shortName(String name) {
  const houses = [
    '元大',
    '國泰',
    '富邦',
    '群益',
    '中信',
    '永豐',
    '凱基',
    '復華',
    '統一',
    '新光',
    '兆豐',
    '第一金',
    '台新',
    '華南永昌',
    '國票',
    '元富',
    '大華銀',
    '野村',
    '街口',
    '安聯',
    '摩根',
    '日盛',
    '台灣人壽',
  ];
  var short = name;
  for (final house in houses) {
    if (short.startsWith(house) && short.length > house.length) {
      short = short.substring(house.length);
      break;
    }
  }
  final chars = short.characters;
  return chars.length <= 4 ? short : chars.take(4).toString();
}

/// One holding in the page of them all: its code large, its short name
/// and how many shares are held; tinted and ringed when [picked].
class _HoldingCard extends StatelessWidget {
  const _HoldingCard({
    required this.code,
    required this.name,
    required this.held,
    required this.picked,
    required this.onTap,
  });

  final String code;
  final String name;
  final String held;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Material(
      color: picked ? Hue.investment.withValues(alpha: 0.12) : Hue.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: picked
            ? const BorderSide(color: Hue.investment, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                code,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: picked ? Hue.investment : Hue.ink,
                ),
              ),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(held, maxLines: 1, style: mutedSmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// A grey square with a mark, such as the one that opens every holding.
class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Glyph icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      onTap: onTap,
      label: label,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Hue.surface,
          borderRadius: BorderRadius.circular(13),
        ),
        child: GlyphIcon(icon, size: 19, color: Hue.muted),
      ),
    );
  }
}

/// One of 常用 under the amount: a small white pill with a grey mark,
/// its name and amount, a tap from a filled form. [strong] writes the
/// name in ink, for a switch such as 代墊 at the front of the row.
class _UsualChip extends StatelessWidget {
  const _UsualChip({
    required this.icon,
    required this.name,
    required this.onTap,
    this.amount,
    this.strong = false,
  });

  final Glyph icon;
  final String name;
  final String? amount;
  final VoidCallback onTap;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final figure = amount;
    return TapArea(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
        decoration: BoxDecoration(
          color: Hue.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Hue.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Hue.surface,
                shape: BoxShape.circle,
              ),
              child: GlyphIcon(icon, size: 14, color: Hue.muted),
            ),
            const SizedBox(width: 7),
            Text(
              name,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                color: strong ? Hue.ink : Hue.muted,
              ),
            ),
            if (figure != null) ...[
              const SizedBox(width: 6),
              Text(
                figure,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Hue.ink,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Someone's share of a spending paid partly for them: a pill tinted in
/// [color] with their name and amount, a tap to change it.
class _LentChip extends StatelessWidget {
  const _LentChip({
    required this.name,
    required this.amount,
    required this.color,
    required this.onTap,
  });

  final String name;
  final String amount;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      onTap: onTap,
      label: '幫$name付 $amount',
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Hue.white,
                shape: BoxShape.circle,
              ),
              child: GlyphIcon(Glyph.heart, size: 13, color: color),
            ),
            const SizedBox(width: 7),
            Text(
              name,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              amount,
              maxLines: 1,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 常用 as one row from the left that slides sideways; [lead], such as
/// 代墊, stays first with a thin line after it.
class _UsualRow extends StatelessWidget {
  const _UsualRow(this.children, {this.lead});

  final List<Widget> children;
  final Widget? lead;

  @override
  Widget build(BuildContext context) {
    final first = lead;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (first != null) ...[
            first,
            if (children.isNotEmpty)
              Container(
                width: 1,
                height: 22,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: Hue.line,
              ),
          ],
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            child,
          ],
        ],
      ),
    );
  }
}

/// Whom money is paid for or from, under the amount in place of 常用:
/// a tinted pill with the person's name, a tap to change them, and a
/// cross back to a plain entry.
class _PersonPill extends StatelessWidget {
  const _PersonPill({
    required this.text,
    required this.sub,
    required this.color,
    required this.onTap,
    this.onClear,
  });

  final String text;
  final String sub;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final clear = onClear;
    return Center(
      child: Container(
        padding: EdgeInsets.only(left: 5, right: clear == null ? 12 : 0),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: TapArea(
                onTap: onTap,
                label: '$text，$sub，換人',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Hue.white,
                        shape: BoxShape.circle,
                      ),
                      child: GlyphIcon(Glyph.heart, size: 13, color: color),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Hue.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (clear != null)
              IconButton(
                tooltip: '不是代墊',
                onPressed: clear,
                icon: GlyphIcon(Glyph.close, size: 14, color: color),
              ),
          ],
        ),
      ),
    );
  }
}

/// One sum someone still owes, as a card to tick: what it was for, when,
/// and what is left of it; ticked ones are what is being paid back.
class _OwedCard extends StatelessWidget {
  const _OwedCard({
    required this.title,
    required this.when,
    required this.amount,
    required this.picked,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String when;
  final String amount;
  final bool picked;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Semantics(
      button: true,
      selected: picked,
      label: '$title，$when，$amount',
      excludeSemantics: true,
      child: Material(
        color: picked ? color.withValues(alpha: 0.12) : Hue.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: picked ? BorderSide(color: color, width: 1.5) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: SizedBox(
            width: 150,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          when,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Hue.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          amount,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: picked ? color : Hue.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: picked ? color : Hue.white,
                      shape: BoxShape.circle,
                    ),
                    child: picked
                        ? const Text(
                            '✓',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A word to pick in a row of them, such as a merchant or a tag: grey,
/// or tinted and ringed in [color] when [picked].
class _WordChip extends StatelessWidget {
  const _WordChip(
    this.label,
    this.onTap, {
    required this.color,
    this.picked = false,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool picked;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      onTap: onTap,
      selected: picked,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: picked ? color.withValues(alpha: 0.12) : Hue.surface,
          borderRadius: BorderRadius.circular(12),
          border: picked ? Border.all(color: color, width: 1.5) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: picked ? color : Hue.ink,
          ),
        ),
      ),
    );
  }
}

/// Words in a row that slides sideways, such as the merchants.
class _WordRow extends StatelessWidget {
  const _WordRow(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(width: 7),
            child,
          ],
        ],
      ),
    );
  }
}

/// A small grey heading over a group of fields, such as 商家.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Hue.muted,
        ),
      ),
    );
  }
}

/// The form's fields one under another, stretched to the width, and at
/// least [minHeight] tall: height to spare goes above and below the child
/// at [grow], such as the amount, so the form keeps one size from tab to
/// tab with nothing left empty at its foot. Its own height without the
/// spare is told to [onHeight].
class _Fill extends MultiChildRenderObjectWidget {
  const _Fill({
    required this.minHeight,
    required this.grow,
    required this.onHeight,
    required super.children,
  });

  final double minHeight;
  final int grow;
  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFill(minHeight, grow, onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderFill renderObject) {
    renderObject
      ..minHeight = minHeight
      ..grow = grow
      ..onHeight = onHeight;
  }
}

class _FillData extends ContainerBoxParentData<RenderBox> {}

class _RenderFill extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FillData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FillData> {
  _RenderFill(this._minHeight, this._grow, this.onHeight);

  double _minHeight;
  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  int _grow;
  set grow(int value) {
    if (value == _grow) return;
    _grow = value;
    markNeedsLayout();
  }

  ValueChanged<double> onHeight;
  double? _told;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FillData) child.parentData = _FillData();
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final inner = BoxConstraints.tightFor(width: width);
    var natural = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(inner, parentUsesSize: true);
      natural += child.size.height;
      child = childAfter(child);
    }
    final height = constraints.constrainHeight(math.max(natural, _minHeight));
    final spare = math.max(0.0, height - natural);
    var y = 0.0;
    var i = 0;
    child = firstChild;
    while (child != null) {
      if (i == _grow) y += spare / 2;
      (child.parentData! as _FillData).offset = Offset(0, y);
      y += child.size.height;
      if (i == _grow) y += spare / 2;
      i++;
      child = childAfter(child);
    }
    size = constraints.constrain(Size(width, height));
    if (_told != natural) {
      _told = natural;
      final told = natural;
      WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(told));
    }
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final inner = BoxConstraints.tightFor(width: constraints.maxWidth);
    var natural = 0.0;
    var child = firstChild;
    while (child != null) {
      natural += child.getDryLayout(inner).height;
      child = childAfter(child);
    }
    return constraints.constrain(
      Size(constraints.maxWidth, math.max(natural, _minHeight)),
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    var sum = 0.0;
    var child = firstChild;
    while (child != null) {
      sum += child.getMinIntrinsicHeight(width);
      child = childAfter(child);
    }
    return math.max(sum, _minHeight);
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
