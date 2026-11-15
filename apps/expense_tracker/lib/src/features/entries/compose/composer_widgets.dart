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
          RoundIcon(
            iconFor(category.icon),
            shownColor(category.color),
            size: 36,
          ),
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
              fontSize: TextSize.title,
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
          style: solidButton(Hue.accent, minimumSize: Size.fromHeight(44)),
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
                    fontSize: TextSize.title,
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
              style: const TextStyle(
                fontSize: TextSize.title,
                fontWeight: FontWeight.w700,
              ),
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
              fontSize: TextSize.title,
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
            fontSize: TextSize.hero,
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
              fontSize: TextSize.small,
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
                fontSize: TextSize.caption,
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
