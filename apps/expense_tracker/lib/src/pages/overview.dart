import 'package:flutter/material.dart';

import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import '../preferences.dart';
import 'getting_started.dart';
import 'nav.dart';
import 'overview/assets_section.dart';
import 'overview/daily_section.dart';
import 'overview/flow_section.dart';
import 'overview/market_section.dart';
import 'overview/plan_section.dart';
import 'overview/summary_section.dart';

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
  });

  final Ledger ledger;
  final Nav nav;

  /// Where the 開始使用 card keeps its progress; none hides the card.
  final Preferences? preferences;

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

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final nav = widget.nav;
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
        if (widget.preferences case final preferences?)
          GettingStarted(ledger: ledger, preferences: preferences, nav: nav),
        SummarySection(ledger: ledger, month: _month),
        PlanSection(ledger: ledger, nav: nav, month: _month),
        DailySection(
          ledger: ledger,
          nav: nav,
          month: _month,
          onMonth: _showMonth,
        ),
        _market,
        _assets,
        FlowSection(ledger: ledger, month: _month),
      ],
    );
  }
}
