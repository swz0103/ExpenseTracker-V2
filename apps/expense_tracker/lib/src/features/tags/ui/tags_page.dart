import 'package:flutter/material.dart';

import '../../../core/design_system/dialogs.dart';
import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/navigation/nav.dart';
import '../model/tag_summary.dart';
import 'tag_summary_blocks.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';

part 'tag_page.dart';

/// The colours of the two halves of 標籤與商家.
const _tagColor = Palette.gold;
const _merchantColor = Palette.orange;

/// 標籤與商家: 標籤 and 商家 on two big segments. Tags: a cover for the
/// tag of the latest entry (its days, total, a day's spending and its
/// categories), then every tag under the year it was last used, three to
/// a row. Merchants: a podium of the three most visited, then the others
/// as chips with their visits. A tap opens that tag's or merchant's page.
class TagsPage extends StatefulWidget {
  const TagsPage({
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
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  late var _merchants = widget.merchants;

  Ledger get ledger => widget.ledger;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final tags = ledger.reportService.tagStats;
        final merchants = ledger.reportService.merchantStats;
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s8),
          header: CenterHeader('標籤與商家', onBack: widget.nav.back),
          children: [
            Row(
              children: [
                Expanded(
                  child: _Half(
                    glyph: Glyph.ticket,
                    label: Words.tag,
                    count: tags.length,
                    color: _tagColor,
                    chosen: !_merchants,
                    onTap: () => setState(() => _merchants = false),
                  ),
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: _Half(
                    glyph: Glyph.store,
                    label: Words.merchant,
                    count: merchants.length,
                    color: _merchantColor,
                    chosen: _merchants,
                    onTap: () => setState(() => _merchants = true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s4),
            ...(_merchants ? _merchantList(merchants) : _tagList()),
          ],
        );
      },
    );
  }

  List<Widget> _tagList() {
    final latest = latestTag(ledger.entries, ledger.today);
    final project = latest == null
        ? null
        : tagSummaryOf(ledger.entries, latest, ledger.today);
    if (project == null) {
      return const [
        EmptyState(
          glyph: Glyph.ticket,
          color: _tagColor,
          message: '記帳時在「標籤」加上 #名稱，\n同一趟旅行或計畫的花費就會收在這裡',
        ),
      ];
    }
    return [
      TagSummaryCard(
        ledger: ledger,
        project: project,
        recent: true,
        onTap: () => widget.nav.open(AppRoutes.tag(project.tag)),
      ),
      for (final (year, names) in tagsByYear(ledger.entries)) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.s1,
            Space.s5,
            Space.s1,
            Space.s2,
          ),
          child: Text(
            '$year',
            style: const TextStyle(
              fontSize: TextSize.body,
              fontWeight: FontWeight.w800,
              color: AppColors.muted,
            ),
          ),
        ),
        CardGrid(columns: 3, gap: 10, [
          for (final name in names)
            ColorCard(
              color: nameColor(name),
              radius: Radii.large,
              label: '#$name',
              onTap: () => widget.nav.open(AppRoutes.tag(name)),
              padding: const EdgeInsets.symmetric(
                vertical: Space.s4,
                horizontal: Space.s2,
              ),
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

  /// A merchant under 其他: its name and how often it was visited, on
  /// its colour.
  Widget _merchantCard(String name, int count) => ColorCard(
    color: nameColor(name),
    radius: Radii.large,
    label: '$name，${countOf(count, CountUnit.times)}',
    onTap: () => widget.nav.open(AppRoutes.merchant(name)),
    padding: const EdgeInsets.symmetric(
      horizontal: Space.s4,
      vertical: Space.s2,
    ),
    // 48 dp to tap, with the padding.
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
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
          const SizedBox(width: Space.s2),
          Text(
            countOf(count, CountUnit.times),
            style: TextStyle(
              fontSize: TextSize.caption,
              color: deepOf(nameColor(name)),
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _merchantList(List<(String, int, int)> merchants) {
    if (merchants.isEmpty) {
      return const [
        EmptyState(
          glyph: Glyph.store,
          color: _merchantColor,
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
              if (rank != podium.first.$2) const SizedBox(width: Space.s2),
              Expanded(
                child: _Step(
                  name: name,
                  count: count,
                  // The first stands tallest; the others by their visits.
                  height: 70 + 90 * count / most,
                  color: nameColor(name),
                  first: rank == 0,
                  onTap: () => widget.nav.open(AppRoutes.merchant(name)),
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
          for (final (name, count, _) in rest) _merchantCard(name, count),
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
    return ReadAsButton(
      selected: chosen,
      label: '$label ${countOf(count, CountUnit.pieces)}',
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.large),
        ),
        child: Material(
          color: chosen ? chosenFill(color) : tintOf(color, 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.large),
            side: chosen ? chosenEdge(color) : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.large),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GlyphIcon(glyph, size: 20, color: ink, tinted: false),
                  const SizedBox(width: Space.s2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: TextSize.title,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(width: Space.s2),
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
    return ReadAsButton(
      label: '$name，去過 ${countOf(count, CountUnit.times)}',
      onTap: onTap,
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
                fontSize: first ? TextSize.title : TextSize.body,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            const SizedBox(height: Space.s2),
            Container(
              height: height,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(Radii.large),
                  bottom: Radius.circular(Radii.small),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [tintOf(color, 0.45), tintOf(color, 0.2)],
                ),
              ),
              padding: const EdgeInsets.only(top: Space.s3),
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: first ? TextSize.figure : TextSize.large,
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
class TagSummaryCard extends StatelessWidget {
  const TagSummaryCard({
    super.key,
    required this.ledger,
    required this.project,
    this.recent = false,
    this.onTap,
    this.menu,
  });

  final Ledger ledger;
  final TagSummary project;

  /// The cover of 標籤與商家: 最近 and the tag's name.
  final bool recent;
  final VoidCallback? onTap;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final color = nameColor(project.tag);
    final ink = deepOf(color);
    final parts = project.byCategory;
    final spent = project.spent;
    final card = Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TagSummaryHeading(
            project: project,
            recent: recent,
            menu: menu,
            today: ledger.today,
          ),
          const SizedBox(height: Space.s2),
          Text(
            ledger.orDots(groupDigits(spent)),
            style: const TextStyle(
              fontSize: TextSize.big,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '${project.days > 1 ? '每天約 ${ledger.orDots(groupDigits(project.perDay))} · ' : ''}'
            '${countOf(project.entries.length, CountUnit.entries)}',
            style: TextStyle(
              fontSize: TextSize.body,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          if (parts.isNotEmpty && spent > 0) ...[
            const SizedBox(height: Space.s4),
            TagCategoryShares(
              categories: [
                for (final (name, amount) in parts)
                  (
                    name,
                    amount,
                    shownColor(Color(ledger.category(name).color)),
                  ),
              ],
              spent: spent,
              ink: ink,
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
