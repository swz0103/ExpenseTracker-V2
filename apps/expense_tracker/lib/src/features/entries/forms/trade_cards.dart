import 'package:flutter/material.dart';

import '../../../core/ledger/ledger.dart';
import '../../../core/formatting/figures.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';

// The cards of a trade on the entry form: its figures, the sums it
// settles at, and the holdings to choose from.

/// A white card to tap for a figure of a trade, such as 股數: a grey
/// mark and the name on the left, the figure large on the right; ringed
/// while [current].
class TradeFigureCard extends StatelessWidget {
  const TradeFigureCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.current = false,
  });

  final Glyph icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Radii.large);
    final mark = SquareIcon(icon, Hue.accent, size: 30);
    const gap = SizedBox(width: Space.s2);
    final name = Text(
      label,
      style: const TextStyle(
        fontSize: TextSize.caption,
        fontWeight: FontWeight.w700,
        color: Hue.muted,
      ),
    );
    final figure = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        value,
        style: const TextStyle(
          fontSize: TextSize.large,
          fontWeight: FontWeight.w700,
          color: Hue.ink,
        ),
      ),
    );
    return ReadAsButton(
      label: '$label：$value',
      onTap: onTap,
      child: Material(
        color: Hue.group,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: current
              ? const BorderSide(color: Hue.investment, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s3),
              // With the phone's largest text the figure goes under its
              // name, where it has the card's whole width.
              child: textGrowth(context) > 1.6
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.s2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              mark,
                              gap,
                              Flexible(child: name),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: figure,
                          ),
                        ],
                      ),
                    )
                  : Row(
                      children: [
                        mark,
                        gap,
                        name,
                        const SizedBox(width: Space.s1),
                        Expanded(child: figure),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One sum in the line a trade settles at, such as 成交 1,000: its name
/// over the figure; white with a pen when it can be changed.
class SettlementBox extends StatelessWidget {
  const SettlementBox(this.label, this.value, this.onTap, {super.key});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    final radius = BorderRadius.circular(Radii.large);
    return Semantics(
      button: tap != null,
      label: '$label：$value',
      onTap: tap,
      excludeSemantics: true,
      child: Material(
        color: tap == null ? Hue.surface : Hue.white,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: tap == null
              ? BorderSide.none
              : const BorderSide(color: Hue.line),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: tap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s2,
                vertical: Space.s2,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: TextSize.tiny,
                      fontWeight: FontWeight.w700,
                      color: Hue.muted,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tap == null ? value : '$value ✎',
                      style: const TextStyle(
                        fontSize: TextSize.title,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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

/// A holding as a pill in one row: its code bold, then its name cut
/// short; tinted and ringed when [picked].
class HoldingCodePill extends StatelessWidget {
  const HoldingCodePill({
    super.key,
    required this.code,
    required this.name,
    required this.picked,
    required this.onTap,
  });

  final String code;
  final String name;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      onTap: onTap,
      selected: picked,
      label: name.isEmpty ? code : '$code $name',
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: Space.s3),
        decoration: BoxDecoration(
          color: picked ? Hue.investment.withValues(alpha: 0.12) : Hue.surface,
          borderRadius: BorderRadius.circular(Radii.medium),
          border: picked ? Border.all(color: Hue.investment, width: 2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              code,
              style: TextStyle(
                fontSize: TextSize.small,
                fontWeight: FontWeight.w800,
                color: picked ? Hue.investment : Hue.ink,
              ),
            ),
            if (name.isNotEmpty) ...[
              const SizedBox(width: Space.s2),
              Text(
                name,
                style: TextStyle(
                  fontSize: TextSize.small,
                  color: picked ? Hue.investment : Hue.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// [h]'s name cut to four characters at most, a fund's without the
/// house it starts with, such as 台灣50 for 元大台灣50; empty while its
/// name is not known, when the name is only its code again.
String shortHoldingName(Holding h) {
  final name = h.name;
  if (name.isEmpty || name == h.code) return '';
  const houses = [
    '元大',
    '國泰',
    '富邦',
    '群益',
    '中信',
    '永豐',
    '凱基',
    '復華',
    '統一',
    '新光',
    '兆豐',
    '第一金',
    '台新',
    '華南永昌',
    '國票',
    '元富',
    '大華銀',
    '野村',
    '街口',
    '安聯',
    '摩根',
    '日盛',
    '台灣人壽',
  ];
  var short = name;
  // Only a fund is named for its house; a company such as 中信金 is not
  // 金. Taiwan's exchange-traded funds are the codes that start with 00.
  for (final house in h.code.startsWith('00') ? houses : const <String>[]) {
    if (short.startsWith(house) && short.length > house.length) {
      short = short.substring(house.length);
      break;
    }
  }
  final chars = short.characters;
  return chars.length <= 4 ? short : chars.take(4).toString();
}

/// One holding in the page of them all: its code large, its short name
/// and how many shares are held; tinted and ringed when [picked].
class HoldingCard extends StatelessWidget {
  const HoldingCard({
    super.key,
    required this.code,
    required this.name,
    required this.held,
    required this.picked,
    required this.onTap,
  });

  final String code;
  final String name;
  final String held;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Radii.large);
    return Material(
      color: picked ? Hue.investment.withValues(alpha: 0.12) : Hue.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: picked
            ? const BorderSide(color: Hue.investment, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                code,
                maxLines: 1,
                style: TextStyle(
                  fontSize: TextSize.title,
                  fontWeight: FontWeight.w800,
                  color: picked ? Hue.investment : Hue.ink,
                ),
              ),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: TextSize.small,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(held, maxLines: 1, style: mutedSmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// A grey square with a mark, such as the one that opens every holding.
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Glyph icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      onTap: onTap,
      label: label,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Hue.surface,
          borderRadius: BorderRadius.circular(Radii.medium),
        ),
        child: GlyphIcon(icon, size: 19, color: Hue.muted),
      ),
    );
  }
}

/// What a trade comes to beyond its sums, on a grey block: its name and
/// what it rests on on the left, the figure on the right in [color].
class TradeOutcomeCard extends StatelessWidget {
  const TradeOutcomeCard({
    super.key,
    required this.title,
    required this.sub,
    required this.color,
    this.value,
  });

  final String title;
  final String sub;
  final String? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final figure = value;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s2,
      ),
      decoration: BoxDecoration(
        color: Hue.group,
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: TextSize.small,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: TextSize.caption,
                    color: Hue.muted,
                  ),
                ),
              ],
            ),
          ),
          if (figure != null)
            Text(
              figure,
              style: TextStyle(
                fontSize: TextSize.large,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
        ],
      ),
    );
  }
}

/// What a trade settles at, as a sum: the trade, then the fee added to a
/// buy or taken off a sale, and a sale's tax taken off. A charge still at
/// what was worked out for it says （試算）. Each is tapped to change it
/// ([onAmount], [onFee], [onTax]); none while only looked at.
class SettlementRow extends StatelessWidget {
  const SettlementRow({
    super.key,
    required this.sell,
    required this.amount,
    required this.fee,
    required this.suggestedFee,
    required this.tax,
    required this.suggestedTax,
    required this.onAmount,
    required this.onFee,
    required this.onTax,
  });

  final bool sell;
  final int amount;
  final int fee;
  final int suggestedFee;
  final int tax;
  final int suggestedTax;
  final VoidCallback? onAmount;
  final VoidCallback? onFee;
  final VoidCallback? onTax;

  static Widget _operator(String sign) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.s1),
    child: Text(
      sign,
      style: const TextStyle(
        fontSize: TextSize.title,
        fontWeight: FontWeight.w700,
        color: Hue.faint,
      ),
    ),
  );

  static Widget _charge(
    String label,
    int value,
    int suggested,
    VoidCallback? onTap,
  ) => SettlementBox(
    value == suggested ? '$label（試算）' : label,
    groupDigits(value),
    onTap,
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: SettlementBox('成交', groupDigits(amount), onAmount)),
        _operator(sell ? '−' : '＋'),
        Expanded(child: _charge(Words.fee, fee, suggestedFee, onFee)),
        if (sell) ...[
          _operator('−'),
          Expanded(child: _charge('證交稅', tax, suggestedTax, onTax)),
        ],
      ],
    );
  }
}

/// The holdings as one row of pills that slides sideways, [picked]
/// ringed, one picked that is not held yet first; the square at the
/// right end, kept still, opens them all and 新增 ([onAll]).
class HoldingCodeRow extends StatelessWidget {
  const HoldingCodeRow({
    super.key,
    required this.holdings,
    required this.picked,
    required this.onPick,
    required this.onAll,
  });

  final List<Holding> holdings;
  final String? picked;
  final ValueChanged<String> onPick;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final code = picked;
    final known = {for (final h in holdings) h.code};
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (code != null && !known.contains(code))
                    HoldingCodePill(
                      code: code,
                      name: '',
                      picked: true,
                      onTap: () {},
                    ),
                  for (final h in holdings) ...[
                    const SizedBox(width: Space.s2),
                    HoldingCodePill(
                      code: h.code,
                      name: shortHoldingName(h),
                      picked: h.code == code,
                      onTap: () => onPick(h.code),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.only(left: Space.s1),
            color: Hue.line,
          ),
          SquareIconButton(icon: Glyph.categories, label: '全部標的', onTap: onAll),
        ],
      ),
    );
  }
}
