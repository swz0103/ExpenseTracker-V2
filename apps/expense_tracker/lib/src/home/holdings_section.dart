import 'package:flutter/material.dart';

import '../charts/chart_data.dart';
import '../theme.dart';
import 'home_data.dart';
import 'section.dart';

/// Investments: the total and today's move. Tap to list the holdings.
class HoldingsSection extends StatefulWidget {
  const HoldingsSection({super.key, required this.data});

  final HomeData data;

  @override
  State<HoldingsSection> createState() => _HoldingsSectionState();
}

class _HoldingsSectionState extends State<HoldingsSection> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final holdings = widget.data.holdings;
    final value = holdings.fold(0, (sum, h) => sum + h.value);
    final cost = holdings.fold(0, (sum, h) => sum + h.cost);
    final change = holdings.fold(0, (sum, h) => sum + h.change);
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    final gain = value - cost;
    return Section(
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading('投資', trailing: _open ? '收起' : '持股'),
          const SizedBox(height: 6),
          Text(
            groupDigits(value),
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: muted,
              children: [
                const TextSpan(text: '今日 '),
                TextSpan(
                  text: signed(change),
                  style: TextStyle(color: gainColor(change)),
                ),
                const TextSpan(text: '　未實現 '),
                TextSpan(
                  text: '${signed(gain)}（${percent(gain, cost)}）',
                  style: TextStyle(color: gainColor(gain)),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      children: [for (final h in holdings) _HoldingRow(h)],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// `1200` → `+1,200`.
String signed(int value) =>
    value > 0 ? '+${groupDigits(value)}' : groupDigits(value);

/// [part] of [whole] with a sign and one decimal, such as `+12.5%`.
String percent(int part, int whole) {
  if (whole == 0) return '—';
  final value = part * 100 / whole;
  return '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}%';
}

/// Taiwan's market colours, softened: red for up, green for down.
Color gainColor(int value) => value > 0
    ? Palette.clay
    : value < 0
    ? Palette.olive
    : Palette.muted;

class _HoldingRow extends StatelessWidget {
  const _HoldingRow(this.holding);

  final Holding holding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(holding.name, style: text.bodyMedium),
                Text(holding.code, style: muted),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(groupDigits(holding.value), style: text.bodyMedium),
              Text(
                percent(holding.gain, holding.cost),
                style: muted?.copyWith(color: gainColor(holding.gain)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
