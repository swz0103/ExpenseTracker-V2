part of 'composer.dart';

/// A tinted block of the composer.
class _Block extends StatelessWidget {
  const _Block({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: Hue.tile,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

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
                  style: const TextStyle(fontSize: 13, color: Hue.accent),
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
            '−${amountIn(entry.amount, currency)}',
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
              child: GestureDetector(
                onTap: locked ? null : () => onChanged(type),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: type == trade ? Hue.accent : Hue.tile,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: type == trade ? Hue.onAccent : Hue.accent,
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({
    required this.category,
    required this.picked,
    required this.onTap,
  });

  final Category category;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 0.25,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Hue.white,
                shape: BoxShape.circle,
                border: picked
                    ? Border.all(color: Hue.accent, width: 2.5)
                    : null,
              ),
              alignment: Alignment.center,
              child: GlyphIcon(
                iconFor(category.icon),
                size: 24,
                color: category.color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: picked ? FontWeight.w700 : FontWeight.w400,
                color: picked ? Hue.accent : Hue.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({
    required this.category,
    required this.amount,
    required this.share,
    required this.onTap,
  });

  final Category category;
  final int amount;
  final double share;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0x263B6C80))),
        ),
        child: Row(
          children: [
            IconBadge(iconFor(category.icon), category.color, size: 28),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: Text(category.name, style: const TextStyle(fontSize: 14)),
            ),
            Expanded(
              child: LinearProgressIndicator(
                value: share.clamp(0.0, 1.0),
                minHeight: 5,
                borderRadius: BorderRadius.circular(3),
                color: category.color,
                backgroundColor: const Color(0x263B6C80),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              groupDigits(amount),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountEnd extends StatelessWidget {
  const _AccountEnd({
    required this.label,
    required this.account,
    required this.balance,
    required this.onTap,
    this.end = false,
  });

  final String label;
  final Account account;
  final int balance;
  final VoidCallback onTap;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final badge = IconBadge(
      accountIcon(account),
      accountColor(account.kind),
      size: 34,
    );
    final text = Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Hue.muted)),
        Text(
          account.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(
          '餘額 ${amountIn(balance, account.currency)}',
          style: const TextStyle(fontSize: 12, color: Hue.muted),
        ),
      ],
    );
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: end
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: end
            ? [Flexible(child: text), const SizedBox(width: 8), badge]
            : [badge, const SizedBox(width: 8), Flexible(child: text)],
      ),
    );
  }
}

/// One line of a trade's sums.
class _Line extends StatelessWidget {
  const _Line(
    this.label,
    this.value, {
    this.strong = false,
    this.color = Hue.ink,
  });

  final String label;
  final String value;
  final bool strong;
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
              fontSize: strong ? 16 : 14.5,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small white button in a block's heading, such as 拆分.
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
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Hue.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, color: Hue.accent),
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
