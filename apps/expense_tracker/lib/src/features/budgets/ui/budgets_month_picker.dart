part of 'budgets.dart';

/// A year of months, each saying how much of its budget was used: red
/// when over, gold from nine in ten.
class _MonthPicker extends StatefulWidget {
  const _MonthPicker({
    required this.ledger,
    required this.chosen,
    required this.first,
    required this.last,
  });

  final Ledger ledger;
  final (int, int) chosen;
  final (int, int) first;
  final (int, int) last;

  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  late var _year = widget.chosen.$1;

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final whole = ledger.budgets.forCategory(allSpending);
    int key((int, int) m) => m.$1 * 12 + m.$2;
    Widget arrow(Glyph glyph, String label, bool on, int by) => Material(
      color: on ? Hue.surface : Hue.paper,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: label,
        onPressed: on ? () => setState(() => _year += by) : null,
        icon: GlyphIcon(glyph, size: 20, color: on ? Hue.ink : Hue.faint),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              arrow(Glyph.back, '前一年', _year > widget.first.$1, -1),
              Expanded(
                child: Text(
                  '$_year',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: TextSize.heading,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              arrow(Glyph.next, '下一年', _year < widget.last.$1, 1),
            ],
          ),
          const SizedBox(height: 14),
          CardGrid(columns: 4, gap: 8, [
            for (var m = 1; m <= 12; m++)
              () {
                final on =
                    key((_year, m)) >= key(widget.first) &&
                    key((_year, m)) <= key(widget.last);
                final total = ledger.budgetService.allowance(whole, _year, m);
                final spent = ledger.reportService.expense(_year, m);
                final share = total == 0 ? null : spent * 100 ~/ total;
                final chosen = (_year, m) == widget.chosen;
                final tone = share == null
                    ? Hue.muted
                    : share > 100
                    ? Hue.negative
                    : share >= 90
                    ? Hue.goldText
                    : Hue.muted;
                return Semantics(
                  button: true,
                  selected: chosen,
                  enabled: on,
                  label: '$m 月',
                  excludeSemantics: true,
                  child: Material(
                    color: chosen ? Hue.selected : Hue.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: chosen
                          ? const BorderSide(color: Hue.accent, width: 2)
                          : BorderSide.none,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: on
                          ? () => Navigator.of(context).pop((_year, m))
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          children: [
                            Text(
                              '$m 月',
                              style: TextStyle(
                                fontSize: TextSize.title,
                                fontWeight: FontWeight.w800,
                                color: on ? Hue.ink : Hue.faint,
                              ),
                            ),
                            Text(
                              !on || share == null
                                  ? ' '
                                  : share > 100
                                  ? '超支'
                                  : '$share%',
                              style: TextStyle(
                                fontSize: TextSize.small,
                                fontWeight: FontWeight.w700,
                                color: tone,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }(),
          ]),
          const SizedBox(height: 12),
          const Text(
            '每個月下面寫用了幾成；超支紅、九成以上金色',
            textAlign: TextAlign.center,
            style: mutedSmall,
          ),
        ],
      ),
    );
  }
}

/// 幫哪個設額度: the spending categories without one, as squares, and the
/// tags without one, as chips.
class _AddLimit extends StatelessWidget {
  const _AddLimit({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final categories = [
      for (final c in ledger.categories.forEntries(income: false))
        if (ledger.budgets.forCategory(c.name).limit == 0) c,
    ];
    final tags = [
      for (final tag in ledger.reportService.tags)
        if (ledger.budgets.forCategory('#$tag').limit == 0) tag,
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              '幫哪個設額度',
              style: TextStyle(
                fontSize: TextSize.heading,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (categories.isNotEmpty) ...[
            const RuleHead('分類'),
            CardGrid(columns: 4, gap: 8, [
              for (final c in categories)
                ColorCard(
                  color: shownColor(Color(c.color)),
                  radius: 16,
                  label: c.name,
                  onTap: () => Navigator.of(context).pop(c.name),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 2,
                  ),
                  child: Column(
                    children: [
                      GlyphIcon(
                        iconFor(c.icon),
                        size: 26,
                        color: shownColor(Color(c.color)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: TextSize.small,
                          fontWeight: FontWeight.w700,
                          color: deepOf(shownColor(Color(c.color))),
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
          ],
          if (tags.isNotEmpty) ...[
            const RuleHead('標籤'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in tags)
                  ActionChip(
                    backgroundColor: Hue.surface,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    label: Text(
                      '#$tag',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    onPressed: () => Navigator.of(context).pop('#$tag'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            '已經設過額度的不會出現在這裡',
            textAlign: TextAlign.center,
            style: mutedSmall,
          ),
        ],
      ),
    );
  }
}

/// A budget's form, the card itself: its icon and name, the monthly
/// allowance in big figures (the calculator beside), this month's use on
/// a bar with the warning line; then the share to warn at, whether what
/// is left carries over, and 儲存. A category's or tag's has a bin.
class _BudgetEditor extends StatefulWidget {
  const _BudgetEditor({required this.ledger, required this.budget});

  final Ledger ledger;
  final Budget budget;

  @override
  State<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<_BudgetEditor> {
  late var _limit = widget.budget.limit;
  late var _warning = widget.budget.warning;
  late var _carry = widget.budget.carry;

  static const _shares = [70, 80, 90, 100];

  Future<void> _calculate() async {
    final value = await showCalculator(
      context,
      title: '每月額度',
      initial: _limit,
      color: Hue.accent,
    );
    if (value != null) setState(() => _limit = value);
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final name = widget.budget.category;
    final total = name == allSpending;
    final tag = name.startsWith('#');
    final category = total || tag ? null : ledger.category(name);
    final shade = category?.color;
    final color = shade == null ? Hue.accent : Color(shade);
    final glyph = total
        ? Glyph.cash
        : tag
        ? Glyph.tag
        : iconFor(category!.icon);
    final today = ledger.today;
    final used = total
        ? ledger.reportService.expense(today.year, today.month)
        : ledger.budgetService.spentAgainst(
            widget.budget,
            today.year,
            today.month,
          );
    final ink = deepOf(color);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
            decoration: BoxDecoration(
              color: tintOf(color, 0.24),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SquareIcon(glyph, color, size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            total ? '總預算' : name,
                            style: TextStyle(
                              fontSize: TextSize.large,
                              fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                          ),
                          Text(
                            total
                                ? '這個月所有支出'
                                : tag
                                ? '標籤額度'
                                : '分類額度',
                            style: TextStyle(
                              fontSize: TextSize.small,
                              color: ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!total)
                      Material(
                        color: Hue.white,
                        borderRadius: BorderRadius.circular(14),
                        child: IconButton(
                          tooltip: '移除額度',
                          onPressed: () {
                            ledger.budgetCommands.removeBudget(name);
                            Navigator.of(context).pop();
                          },
                          icon: const GlyphIcon(
                            Glyph.trash,
                            size: 18,
                            color: Hue.danger,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '每月額度',
                  style: TextStyle(
                    fontSize: TextSize.small,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                AmountTap(
                  label: '每月額度 $_limit',
                  onTap: _calculate,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'NT\$ ',
                          style: TextStyle(
                            fontSize: TextSize.heading,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: groupDigits(_limit),
                          style: const TextStyle(
                            fontSize: TextSize.hero,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, box) {
                    final share = _limit == 0
                        ? 0.0
                        : (used / _limit).clamp(0.0, 1.0);
                    final line = box.maxWidth * _warning / 100;
                    return SizedBox(
                      height: 18,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.centerLeft,
                        children: [
                          Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: Hue.white,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: share,
                            child: Container(
                              height: 10,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                          Positioned(
                            left: (line - 1).clamp(0, box.maxWidth - 2),
                            top: 0,
                            bottom: 0,
                            child: Container(width: 2, color: Hue.ink),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: '這個月已用 '),
                          TextSpan(
                            text: ledger.orDots(groupDigits(used)),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      style: TextStyle(fontSize: TextSize.small, color: ink),
                    ),
                    const Spacer(),
                    Text(
                      '$_warning% 時提醒',
                      style: TextStyle(fontSize: TextSize.small, color: ink),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '用到幾成時提醒',
            style: TextStyle(
              fontSize: TextSize.body,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (i, p) in _shares.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: p == _warning ? Hue.accent : Hue.surface,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _warning = p),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Center(
                          child: Text(
                            '$p%',
                            style: TextStyle(
                              fontSize: TextSize.title,
                              fontWeight: FontWeight.w800,
                              color: p == _warning ? Hue.onAccent : Hue.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          ColorCard(
            color: Hue.faint,
            amount: 0.15,
            radius: 18,
            onTap: () => setState(() => _carry = !_carry),
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '沒用完的留到下個月',
                        style: TextStyle(
                          fontSize: TextSize.body,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text('上個月剩的，加到這個月的額度', style: mutedSmall),
                    ],
                  ),
                ),
                TickSwitch(
                  value: _carry,
                  color: Hue.accent,
                  label: '沒用完的留到下個月',
                  onChanged: (on) => setState(() => _carry = on),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PanelButton(
            '儲存',
            color: Hue.accent,
            onTap: () {
              ledger.budgetCommands.setBudget(
                name,
                _limit,
                warning: _warning,
                carry: _carry,
              );
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
