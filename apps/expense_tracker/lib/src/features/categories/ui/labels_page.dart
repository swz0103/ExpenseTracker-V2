import 'package:flutter/material.dart';

import '../../../core/look/dialogs.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import '../model/project.dart';

/// The colours of the two halves of 標籤與商家.
const _tagHue = Palette.gold;
const _merchantHue = Palette.orange;

/// 標籤與商家: 標籤 and 商家 on two big segments. Tags: a cover for the
/// tag of the latest entry (its days, total, a day's spending and its
/// categories), then every tag under the year it was last used, three to
/// a row. Merchants: a podium of the three most visited, then the others
/// as chips with their visits. A tap opens that tag's or merchant's page.
class LabelsPage extends StatefulWidget {
  const LabelsPage({
    super.key,
    required this.ledger,
    required this.nav,
    this.merchants = false,
  });

  final Ledger ledger;
  final Nav nav;

  /// Opens on 商家, as on coming back from a merchant's page.
  final bool merchants;

  @override
  State<LabelsPage> createState() => _LabelsPageState();
}

class _LabelsPageState extends State<LabelsPage> {
  late var _merchants = widget.merchants;

  Ledger get ledger => widget.ledger;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final tags = ledger.tagStats;
        final merchants = ledger.merchantStats;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            CenterHeader('標籤與商家', onBack: widget.nav.back),
            Row(
              children: [
                Expanded(
                  child: _Half(
                    glyph: Glyph.ticket,
                    label: '標籤',
                    count: tags.length,
                    color: _tagHue,
                    chosen: !_merchants,
                    onTap: () => setState(() => _merchants = false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Half(
                    glyph: Glyph.store,
                    label: '商家',
                    count: merchants.length,
                    color: _merchantHue,
                    chosen: _merchants,
                    onTap: () => setState(() => _merchants = true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...(_merchants ? _merchantList(merchants) : _tagList()),
          ],
        );
      },
    );
  }

  List<Widget> _tagList() {
    final latest = latestTag(ledger);
    final project = latest == null ? null : projectOf(ledger, latest);
    if (project == null) {
      return const [
        EmptyState(
          glyph: Glyph.ticket,
          color: _tagHue,
          message: '記帳時在「標籤」加上 #名稱，\n同一趟旅行或計畫的花費就會收在這裡',
        ),
      ];
    }
    return [
      ProjectCard(
        ledger: ledger,
        project: project,
        recent: true,
        onTap: () => widget.nav.open(Pages.tag(project.tag)),
      ),
      for (final (year, names) in tagsByYear(ledger)) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
          child: Text(
            '$year',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Hue.muted,
            ),
          ),
        ),
        CardGrid(columns: 3, gap: 10, [
          for (final name in names)
            ColorCard(
              color: nameColor(name),
              radius: 16,
              label: '#$name',
              onTap: () => widget.nav.open(Pages.tag(name)),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Text(
                '#$name',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: deepOf(nameColor(name)),
                ),
              ),
            ),
        ]),
      ],
    ];
  }

  List<Widget> _merchantList(List<(String, int, int)> merchants) {
    if (merchants.isEmpty) {
      return const [
        EmptyState(
          glyph: Glyph.store,
          color: _merchantHue,
          message: '記帳時填上「商家」，\n最常去的店就會排在這裡',
        ),
      ];
    }
    final top = merchants.take(3).toList();
    final rest = merchants.skip(3).toList();
    final most = top.first.$2;
    // Second on the left, first in the middle, third on the right.
    final podium = [
      if (top.length > 1) (top[1], 1),
      (top[0], 0),
      if (top.length > 2) (top[2], 2),
    ];
    return [
      SizedBox(
        height: 220,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final ((name, count, _), rank) in podium) ...[
              if (rank != podium.first.$2) const SizedBox(width: 10),
              Expanded(
                child: _Step(
                  name: name,
                  count: count,
                  // The first stands tallest; the others by their visits.
                  height: 70 + 90 * count / most,
                  color: nameColor(name),
                  first: rank == 0,
                  onTap: () => widget.nav.open(Pages.merchant(name)),
                ),
              ),
            ],
          ],
        ),
      ),
      if (rest.isNotEmpty) ...[
        const RuleHead('其他'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (name, count, _) in rest)
              ColorCard(
                color: nameColor(name),
                radius: 14,
                label: '$name，$count 次',
                onTap: () => widget.nav.open(Pages.merchant(name)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(
                        text: '  $count 次',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    color: deepOf(nameColor(name)),
                  ),
                ),
              ),
          ],
        ),
      ],
    ];
  }
}

/// 標籤 6 or 商家 8: solid in its colour when chosen.
class _Half extends StatelessWidget {
  const _Half({
    required this.glyph,
    required this.label,
    required this.count,
    required this.color,
    required this.chosen,
    required this.onTap,
  });

  final Glyph glyph;
  final String label;
  final int count;
  final Color color;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = chosen ? const Color(0xFFFFFFFF) : deepOf(color);
    return Semantics(
      selected: chosen,
      button: true,
      label: '$label $count 個',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: chosen ? Hue.tileShadow : null,
        ),
        child: Material(
          color: chosen ? color : tintOf(color, 0.2),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GlyphIcon(glyph, size: 20, color: ink, tinted: false),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('$count', style: TextStyle(fontSize: 13, color: ink)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One step of the podium: the merchant's name over a column as tall as
/// its visits, the count on the column.
class _Step extends StatelessWidget {
  const _Step({
    required this.name,
    required this.count,
    required this.height,
    required this.color,
    required this.first,
    required this.onTap,
  });

  final String name;
  final int count;
  final double height;
  final Color color;
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return Semantics(
      button: true,
      label: '$name，去過 $count 次',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: first ? 17 : 15,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: height,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                  bottom: Radius.circular(8),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [tintOf(color, 0.45), tintOf(color, 0.2)],
                ),
              ),
              padding: const EdgeInsets.only(top: 12),
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: first ? 30 : 26,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  Text('次', style: TextStyle(fontSize: 12, color: ink)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tag as a big card in its colour: its days, the total spent, a day's
/// spending and how many entries, and a bar of its categories with each
/// one's share. On 標籤與商家 it is the latest tag's, with 最近 and the
/// name; on the tag's own page it carries the ⋯ menu instead.
class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.ledger,
    required this.project,
    this.recent = false,
    this.onTap,
    this.menu,
  });

  final Ledger ledger;
  final Project project;

  /// The cover of 標籤與商家: 最近 and the tag's name.
  final bool recent;
  final VoidCallback? onTap;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final color = nameColor(project.tag);
    final ink = deepOf(color);
    String day(DateTime d) => '${d.month}/${d.day}';
    final days = project.from == project.to
        ? day(project.from)
        : '${day(project.from)} – ${day(project.to)} · ${project.days} 天';
    final parts = project.byCategory;
    final spent = project.spent;
    final card = Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tintOf(color, 0.4), tintOf(color, 0.2)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (recent)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '最近',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                      ),
                    Text(
                      days,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    if (recent)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '#${project.tag}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ?menu,
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ledger.orDots(groupDigits(spent)),
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
          ),
          Text(
            '${project.days > 1 ? '每天約 ${ledger.orDots(groupDigits(project.perDay))} · ' : ''}'
            '${project.entries.length} 筆',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          if (parts.isNotEmpty && spent > 0) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final (i, (name, amount)) in parts.indexed) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: (amount * 1000 ~/ spent).clamp(1, 1000),
                        child: ColoredBox(
                          color: ledger.category(name).color,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final (name, amount) in parts.take(5))
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: ledger.category(name).color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$name ${amount * 100 ~/ spent}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
    final tap = onTap;
    if (tap == null) return card;
    return Semantics(
      button: true,
      label: '最近的標籤 #${project.tag}',
      child: Pressable(
        depth: 0.98,
        child: GestureDetector(onTap: tap, child: card),
      ),
    );
  }
}

/// A tag's page or a merchant's: the big card with ⋯ (改名, 合併到…,
/// 移除), then its entries on a white board, each opening that entry.
class LabelPage extends StatelessWidget {
  const LabelPage({
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
      ledger.renameMerchant(name, to);
    } else {
      ledger.renameTag(name, to);
    }
  }

  List<String> _others() => [
    for (final (other, _, _)
        in merchant ? ledger.merchantStats : ledger.tagStats)
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
        : projectOf(ledger, name)?.entries.length ?? 0;
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: Text(
                '合併到',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 14),
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
                        vertical: 16,
                        horizontal: 6,
                      ),
                      child: Text(
                        merchant ? other : '#$other',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
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
        : projectOf(ledger, name)?.entries.length ?? 0;
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
            : projectOf(ledger, name)?.entries ?? const <Entry>[];
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
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            CenterHeader(_shown, onBack: nav.back),
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
                  project: projectOf(ledger, name)!,
                  menu: menu,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 20, 6, 10),
                child: Text(
                  merchant ? '紀錄' : '紀錄 · ${entries.length} 筆',
                  style: const TextStyle(
                    fontSize: 15,
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
                      ledger.category(e.category).color,
                      size: 42,
                    ),
                    title: e.title,
                    detail: '${e.category} · ${e.date.month}/${e.date.day}',
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
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
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
                    fontSize: 14,
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
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const TextSpan(
                        text: ' 次',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '最近 ${last.month}/${last.day} · '
                  '第一次 ${first.year}/${first.month}/${first.day}',
                  style: TextStyle(
                    fontSize: 14,
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
        20,
        0,
        20,
        // showSheet already lifts the sheet over the keyboard.
        20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              '改名',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: tintOf(color, 0.25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                if (!widget.merchant)
                  Text(
                    '# ',
                    style: TextStyle(
                      fontSize: 24,
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
                      fontSize: 24,
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
