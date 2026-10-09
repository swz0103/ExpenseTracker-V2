import 'dart:math';

import 'package:flutter/material.dart';

import '../charts/bar_scale.dart';
import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'nav.dart';

/// 投資與股息: unrealised and realised profit, dividends by month, and
/// each holding's profit as a bar on a shared scale.
class InvestmentsPage extends StatefulWidget {
  const InvestmentsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<InvestmentsPage> createState() => _InvestmentsPageState();
}

class _InvestmentsPageState extends State<InvestmentsPage> {
  late var _month = (widget.ledger.today.year, widget.ledger.today.month);
  var _scale = BarScale.enlarged;

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final value = ledger.investValue;
        final cost = ledger.investCost;
        final gain = value - cost;
        final (year, month) = _month;
        final holdings = ledger.holdings;
        final largest = holdings.fold(0, (m, h) => max(m, h.gain.abs()));
        final anyLoss = holdings.any((h) => h.gain < 0);
        final tone = gain < 0 ? Hue.negative : Hue.positive;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 32),
          children: [
            PageHeader('投資與股息', onBack: widget.nav.back),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SoftPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '未實現損益',
                              style: TextStyle(color: Hue.muted),
                            ),
                            const Spacer(),
                            LinkToggle(
                              '示意行情',
                              onTap: () =>
                                  showNote(context, '價格為示意收盤價，尚未接上自動行情'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            const Text(
                              'TWD ',
                              style: TextStyle(fontSize: 12, color: Hue.muted),
                            ),
                            Text(
                              moneySigned(gain),
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w600,
                                color: tone,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              percentOf(gain, cost),
                              style: TextStyle(fontSize: 15, color: tone),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(child: Figure('持股市值', money(value))),
                            Expanded(child: Figure('投入成本', money(cost))),
                            Expanded(
                              child: Figure(
                                '已實現損益',
                                moneySigned(ledger.realized),
                                end: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SectionHead(
                    '股息入帳',
                    trailing: MonthSwitch(
                      month: _month,
                      latest: (ledger.today.year, ledger.today.month),
                      onChanged: (m) => setState(() => _month = m),
                    ),
                  ),
                  Row(
                    children: [
                      const Text('本月股息 ', style: TextStyle(color: Hue.muted)),
                      Text(
                        money(ledger.dividends(year, month)),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            widget.nav.compose(type: EntryType.dividend),
                        icon: const GlyphIcon(Glyph.add, size: 16),
                        label: const Text('記股息'),
                      ),
                    ],
                  ),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: '累計股息  ',
                          style: TextStyle(fontSize: 12, color: Hue.muted),
                        ),
                        TextSpan(
                          text: money(ledger.totalDividends),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  SectionHead(
                    '持股損益',
                    trailing: LinkToggle(
                      _scale.label,
                      onTap: () => setState(() => _scale = _scale.other),
                    ),
                  ),
                  for (final h in holdings)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Hue.line)),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  h.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${h.code}  ${percentOf(h.gain, h.cost)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Hue.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: AxisBar(
                              value: h.gain,
                              largest: largest,
                              scale: _scale,
                              axis: anyLoss ? 0.3 : 0,
                              height: 10,
                            ),
                          ),
                          SizedBox(
                            width: 96,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  moneySigned(h.gain),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: h.gain < 0
                                        ? Hue.negative
                                        : Hue.positive,
                                  ),
                                ),
                                Text(
                                  '市值 ${money(h.value)}',
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
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
