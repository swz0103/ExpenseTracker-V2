import 'package:flutter/material.dart';

import '../../../core/look/dialogs.dart';
import '../../../core/text/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/ui/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import '../model/label_project.dart';
import '../../../core/ui/shown_amounts.dart';

part 'label_page.dart';

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
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          header: CenterHeader('標籤與商家', onBack: widget.nav.back),
          children: [
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
    final project = latest == null ? null : labelProjectOf(ledger, latest);
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
              fontSize: TextSize.body,
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
                  fontSize: TextSize.body,
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
        const SectionTitle('其他'),
        // Two to a row, each as wide as the other, so long and short
        // names line up.
        CardGrid(gap: 8, [
          for (final (name, count, _) in rest)
            ColorCard(
              color: nameColor(name),
              radius: 14,
              label: '$name，$count 次',
              onTap: () => widget.nav.open(Pages.merchant(name)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: OneLine(
                      name,
                      style: TextStyle(
                        fontSize: TextSize.body,
                        fontWeight: FontWeight.w800,
                        color: deepOf(nameColor(name)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$count 次',
                    style: TextStyle(
                      fontSize: TextSize.caption,
                      color: deepOf(nameColor(name)),
                    ),
                  ),
                ],
              ),
            ),
        ]),
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
    final ink = chosen ? chosenInk(color) : deepOf(color);
    return Semantics(
      selected: chosen,
      button: true,
      label: '$label $count 個',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: Material(
          color: chosen ? chosenFill(color) : tintOf(color, 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: chosen ? chosenEdge(color) : BorderSide.none,
          ),
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
                      fontSize: TextSize.title,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(fontSize: TextSize.small, color: ink),
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
                  Text(
                    '次',
                    style: TextStyle(fontSize: TextSize.caption, color: ink),
                  ),
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
  final LabelProject project;

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
                            fontSize: TextSize.caption,
                            fontWeight: FontWeight.w800,
                            color: Hue.onSolid,
                          ),
                        ),
                      ),
                    Text(
                      days,
                      style: TextStyle(
                        fontSize: TextSize.body,
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
                            fontSize: TextSize.large,
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
            style: const TextStyle(
              fontSize: TextSize.big,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '${project.days > 1 ? '每天約 ${ledger.orDots(groupDigits(project.perDay))} · ' : ''}'
            '${project.entries.length} 筆',
            style: TextStyle(
              fontSize: TextSize.body,
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
                          color: shownColor(Color(ledger.category(name).color)),
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
                          color: shownColor(Color(ledger.category(name).color)),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$name ${amount * 100 ~/ spent}%',
                        style: TextStyle(
                          fontSize: TextSize.small,
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
