part of 'composer.dart';

/// The parts of a split as one bar: each a stretch as wide as its share,
/// with its name and amount on it; a tap opens that part's amount.
class _AllocationBar extends StatelessWidget {
  const _AllocationBar({required this.parts, required this.onTap});

  final List<(Category, int)> parts;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      // 56 high, taller when the phone's text is larger.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, (category, amount)) in parts.indexed) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                flex: amount <= 0 ? 1 : amount,
                child: Material(
                  color: shownColor(Color(category.color)),
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              category.name,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: TextSize.caption,
                                fontWeight: FontWeight.w700,
                                color: wordsOn(
                                  shownColor(Color(category.color)),
                                ),
                              ),
                            ),
                            Text(
                              groupDigits(amount),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: TextSize.body,
                                fontWeight: FontWeight.w700,
                                color: wordsOn(
                                  shownColor(Color(category.color)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A white card with a mark and what was chosen, such as the account or
/// the day; [label] names it for a screen reader.
class _Pick extends StatelessWidget {
  const _Pick({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.valueColor = Hue.ink,
  });

  final Glyph icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      label: '$label：$value',
      excludeSemantics: true,
      child: Material(
        color: Hue.group,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  SquareIcon(icon, Hue.accent, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TextSize.title,
                        fontWeight: FontWeight.w700,
                        color: valueColor,
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

/// One end of a transfer on a grey card: the account's mark on the left,
/// its name over what it will hold once the transfer is made. [end] is
/// the right-hand card, with room on its inner side for the arrow.
class _TransferEnd extends StatelessWidget {
  const _TransferEnd({
    required this.account,
    required this.after,
    required this.label,
    required this.onTap,
    this.end = false,
  });

  final Account account;

  /// What the account holds afterwards, as words.
  final String after;

  /// What a screen reader calls it: 轉出帳戶 or 轉入帳戶.
  final String label;
  final VoidCallback onTap;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      label: '$label：${account.name}，$after',
      excludeSemantics: true,
      child: Material(
        color: Hue.surface,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: EdgeInsets.fromLTRB(end ? 22 : 12, 9, end ? 10 : 22, 9),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Hue.white,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: GlyphIcon(
                      accountIcon(account),
                      size: 17,
                      color: Hue.muted,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: TextSize.body,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          after,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: TextSize.caption,
                            color: Hue.muted,
                          ),
                        ),
                      ],
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

/// A white card to tap for a figure of a trade, such as 股數: a grey
/// mark and the name on the left, the figure large on the right; ringed
/// while [current].
class _Figure extends StatelessWidget {
  const _Figure({
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
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      label: '$label：$value',
      excludeSemantics: true,
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  SquareIcon(icon, Hue.accent, size: 30),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: TextSize.caption,
                      fontWeight: FontWeight.w700,
                      color: Hue.muted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FittedBox(
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

/// One sum in the line a trade settles at, such as 成交 1,000: its name
/// over the figure; white with a pen when it can be changed.
class _EqBox extends StatelessWidget {
  const _EqBox(this.label, this.value, this.onTap);

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    final radius = BorderRadius.circular(14);
    return Semantics(
      button: tap != null,
      label: '$label：$value',
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
class _CodePill extends StatelessWidget {
  const _CodePill({
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
      label: '$code $name',
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: picked ? Hue.investment.withValues(alpha: 0.12) : Hue.surface,
          borderRadius: BorderRadius.circular(13),
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
              const SizedBox(width: 6),
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

/// A holding's name cut to four characters at most, without the fund
/// house it starts with, such as 台灣50 for 元大台灣50.
String _shortName(String name) {
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
  for (final house in houses) {
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
class _HoldingCard extends StatelessWidget {
  const _HoldingCard({
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
    final radius = BorderRadius.circular(16);
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
          padding: const EdgeInsets.all(12),
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
class _SquareButton extends StatelessWidget {
  const _SquareButton({
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
          borderRadius: BorderRadius.circular(13),
        ),
        child: GlyphIcon(icon, size: 19, color: Hue.muted),
      ),
    );
  }
}
