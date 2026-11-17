part of 'tags_page.dart';

/// A tag's page or a merchant's: the big card with ⋯ (改名, 合併到…,
/// 移除), then its entries on a white board, each opening that entry.
class TagPage extends StatelessWidget {
  const TagPage({
    super.key,
    required this.ledger,
    required this.nav,
    required this.name,
    this.merchant = false,
  });

  final Ledger ledger;
  final Nav nav;
  final String name;
  final bool merchant;

  String get _shown => merchant ? name : '#$name';

  void _move(String to) {
    if (merchant) {
      ledger.entryCommands.renameMerchant(name, to);
    } else {
      ledger.entryCommands.renameTag(name, to);
    }
  }

  List<String> _others() => [
    for (final (other, _, _)
        in merchant
            ? ledger.reportService.merchantStats
            : ledger.reportService.tagStats)
      if (other != name) other,
  ];

  void _openOther(String other) =>
      nav.open(merchant ? Pages.merchant(other) : Pages.tag(other));

  Future<void> _rename(BuildContext context) async {
    final typed = await showSheet<String>(
      context,
      (_) => _RenameSheet(name: name, merchant: merchant),
    );
    if (typed == null || typed == name || !context.mounted) return;
    if (_others().contains(typed)) {
      final ok = await _askMerge(context, typed);
      if (!ok) return;
    }
    _move(typed);
    _openOther(typed);
  }

  Future<bool> _askMerge(BuildContext context, String into) {
    final count = merchant
        ? visitsTo(ledger, name).length
        : tagSummaryOf(ledger, name)?.entries.length ?? 0;
    final target = merchant ? into : '#$into';
    return confirm(
      context,
      '合併到 $target？',
      '合併',
      body: '$name 的 $count 筆紀錄會改成 $target，$_shown 就不見了。',
    );
  }

  Future<void> _merge(BuildContext context) async {
    final into = await showSheet<String>(
      context,
      (context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: Text(
                '合併到',
                style: TextStyle(
                  fontSize: TextSize.heading,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: Space.s4),
            Flexible(
              child: SingleChildScrollView(
                child: CardGrid(columns: 3, gap: 10, [
                  for (final other in _others())
                    ColorCard(
                      color: nameColor(other),
                      radius: 16,
                      label: merchant ? other : '#$other',
                      onTap: () => Navigator.of(context).pop(other),
                      padding: const EdgeInsets.symmetric(
                        vertical: Space.s4,
                        horizontal: Space.s2,
                      ),
                      child: Text(
                        merchant ? other : '#$other',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: TextSize.body,
                          fontWeight: FontWeight.w800,
                          color: deepOf(nameColor(other)),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
    if (into == null || !context.mounted) return;
    if (!await _askMerge(context, into)) return;
    _move(into);
    _openOther(into);
  }

  Future<void> _remove(BuildContext context) async {
    final count = merchant
        ? visitsTo(ledger, name).length
        : tagSummaryOf(ledger, name)?.entries.length ?? 0;
    final ok = await confirm(
      context,
      '移除 $_shown？',
      '移除',
      danger: true,
      body: merchant
          ? '$count 筆紀錄會拿掉這個商家，紀錄本身保留。'
          : '$count 筆紀錄會拿掉這個標籤，紀錄本身保留。',
    );
    if (!ok) return;
    _move('');
    nav.back();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final entries = merchant
            ? visitsTo(ledger, name)
            : tagSummaryOf(ledger, name)?.entries ?? const <Entry>[];
        final menu = DotsMenu([
          DotsItem(Glyph.edit, '改名', () => _rename(context)),
          if (_others().isNotEmpty)
            DotsItem(Glyph.merge, '合併到…', () => _merge(context)),
          DotsItem(
            Glyph.trash,
            merchant ? '移除商家' : '移除標籤',
            () => _remove(context),
            danger: true,
          ),
        ]);
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s8),
          header: CenterHeader(_shown, onBack: nav.back),
          children: [
            if (entries.isEmpty)
              EmptyState(
                glyph: merchant ? Glyph.store : Glyph.ticket,
                color: merchant ? _merchantHue : _tagHue,
                message: '沒有紀錄',
              )
            else ...[
              if (merchant)
                _VisitsCard(name: name, visits: entries, menu: menu)
              else
                ProjectCard(
                  ledger: ledger,
                  project: tagSummaryOf(ledger, name)!,
                  menu: menu,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.s2,
                  Space.s5,
                  Space.s2,
                  Space.s2,
                ),
                child: Text(
                  merchant ? '紀錄' : '紀錄 · ${entries.length} 筆',
                  style: const TextStyle(
                    fontSize: TextSize.body,
                    fontWeight: FontWeight.w800,
                    color: Hue.muted,
                  ),
                ),
              ),
              QuoteBoard([
                for (final e in entries.take(200))
                  QuoteRow(
                    lead: SquareIcon(
                      iconFor(ledger.category(e.category).icon),
                      shownColor(Color(ledger.category(e.category).color)),
                      size: 42,
                    ),
                    title: e.title,
                    detail: '${e.category} · ${formatMd(e.date)}',
                    trailing: RowFigure(ledger.orDots(groupDigits(e.amount))),
                    onTap: () => nav.showEntry(e),
                  ),
              ]),
            ],
          ],
        );
      },
    );
  }
}

/// A merchant's card: 去過 N 次, when last and first.
class _VisitsCard extends StatelessWidget {
  const _VisitsCard({
    required this.name,
    required this.visits,
    required this.menu,
  });

  final String name;
  final List<Entry> visits;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final color = nameColor(name);
    final ink = deepOf(color);
    final last = visits.first.date;
    final first = visits.last.date;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.s5,
        Space.s4,
        Space.s4,
        Space.s4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.extraLarge),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tintOf(color, 0.4), tintOf(color, 0.2)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '去過',
                  style: TextStyle(
                    fontSize: TextSize.body,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${visits.length}',
                        style: const TextStyle(
                          fontSize: TextSize.hero,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const TextSpan(
                        text: ' 次',
                        style: TextStyle(
                          fontSize: TextSize.heading,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.s2),
                Text(
                  '最近 ${formatMd(last)} · '
                  '第一次 ${formatYMd(first)}',
                  style: TextStyle(
                    fontSize: TextSize.body,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
          menu,
        ],
      ),
    );
  }
}

/// 改名: the name in a field on the tag's tint, `#` before a tag's;
/// 完成 on the keyboard saves it.
class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.name, required this.merchant});

  final String name;
  final bool merchant;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final _text = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done() {
    final typed = _text.text.trim().replaceFirst(RegExp('^#'), '');
    Navigator.of(context).pop(typed.isEmpty ? null : typed);
  }

  @override
  Widget build(BuildContext context) {
    final color = nameColor(widget.name);
    final ink = deepOf(color);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.s5,
        0,
        Space.s5,
        // showSheet already lifts the sheet over the keyboard.
        Space.s5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              '改名',
              style: TextStyle(
                fontSize: TextSize.heading,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: Space.s4),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s4,
              vertical: Space.s4,
            ),
            decoration: BoxDecoration(
              color: tintOf(color, 0.25),
              borderRadius: BorderRadius.circular(Radii.largeIncreased),
            ),
            child: Row(
              children: [
                if (!widget.merchant)
                  Text(
                    '# ',
                    style: TextStyle(
                      fontSize: TextSize.large,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                Expanded(
                  child: TextField(
                    controller: _text,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _done(),
                    style: TextStyle(
                      fontSize: TextSize.large,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                    decoration: const InputDecoration.collapsed(hintText: ''),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
