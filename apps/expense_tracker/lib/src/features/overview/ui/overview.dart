import 'package:flutter/material.dart';

import '../../../core/look/glyphs.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/preferences.dart';
import '../model/overview_blocks.dart';
import 'overview_editor.dart';
import '../../../core/nav.dart';
import 'sections/assets_section.dart';
import 'sections/daily_section.dart';
import 'sections/flow_section.dart';
import 'sections/market_section.dart';
import 'sections/plan_section.dart';
import 'sections/summary_section.dart';

/// 總覽: the month in four figures, what falls due, a week of days with
/// the chosen day's entries, the market, spending against the budget,
/// where the assets are and six months of income and spending.
///
/// Each section follows the ledger and keeps its own choices, so a tap in
/// one draws that section again and leaves the others as they are. The
/// page itself keeps only the month they all show.
class OverviewPage extends StatefulWidget {
  const OverviewPage({
    super.key,
    required this.ledger,
    required this.nav,
    this.preferences,
    this.summaryKey,
  });

  final Ledger ledger;
  final Nav nav;

  /// The overview's own choices: its blocks and their order.
  final Preferences? preferences;

  /// On the month's figures, for the app's tour to find.
  final GlobalKey? summaryKey;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  late var _month = (widget.ledger.today.year, widget.ledger.today.month);

  /// The sections that do not show the month, made once: the same
  /// widget each time the page is built, so choosing another month leaves
  /// them as they are rather than building them again. Each follows the
  /// ledger on its own.
  late Widget _market = _marketSection();
  late Widget _assets = _assetsSection();

  Widget _marketSection() =>
      MarketSection(ledger: widget.ledger, nav: widget.nav);
  Widget _assetsSection() => AssetsSection(ledger: widget.ledger);

  @override
  void didUpdateWidget(OverviewPage old) {
    super.didUpdateWidget(old);
    if (old.ledger != widget.ledger || old.nav != widget.nav) {
      _market = _marketSection();
      _assets = _assetsSection();
    }
  }

  void _showMonth((int, int) month) {
    if (month != _month) setState(() => _month = month);
  }

  /// One of the blocks the person may move or hide.
  Widget _block(OverviewBlock block) {
    final ledger = widget.ledger;
    final nav = widget.nav;
    return switch (block) {
      OverviewBlock.plan => PlanSection(
        ledger: ledger,
        nav: nav,
        month: _month,
      ),
      OverviewBlock.daily => DailySection(
        ledger: ledger,
        nav: nav,
        month: _month,
        onMonth: _showMonth,
      ),
      OverviewBlock.market => _market,
      OverviewBlock.assets => _assets,
      OverviewBlock.flow => FlowSection(ledger: ledger, month: _month),
    };
  }

  @override
  Widget build(BuildContext context) {
    final preferences = widget.preferences;
    if (preferences == null) return _page();
    // The blocks follow the order and choice kept in the preferences.
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => _page(),
    );
  }

  Widget _page() {
    final ledger = widget.ledger;
    final preferences = widget.preferences;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      children: [
        ListenableBuilder(
          listenable: ledger,
          builder: (context, _) => PageHeader(
            '總覽',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: ledger.hidden ? '顯示金額' : '隱藏金額',
                  onPressed: ledger.toggleHidden,
                  icon: GlyphIcon(
                    ledger.hidden ? Glyph.eyeOff : Glyph.eye,
                    size: 20,
                    color: Hue.muted,
                  ),
                ),
                MonthSwitch(
                  month: _month,
                  latest: (ledger.today.year, ledger.today.month),
                  onChanged: _showMonth,
                ),
              ],
            ),
          ),
        ),
        KeyedSubtree(
          key: widget.summaryKey,
          child: SummarySection(ledger: ledger, month: _month),
        ),
        for (final (:block, :shown) in blocksFrom(preferences?.overview))
          if (shown) _block(block),
        if (preferences != null)
          Center(
            child: TextButton(
              onPressed: () => editOverview(context, preferences),
              style: TextButton.styleFrom(foregroundColor: Hue.muted),
              child: const Text('調整總覽'),
            ),
          ),
      ],
    );
  }
}
