import 'package:flutter/material.dart';

import 'theme.dart';

/// A page's title row: an optional back arrow, the title in 22 px and
/// whatever sits on the right.
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.onBack, this.trailing});

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          if (back != null)
            IconButton(
              tooltip: '返回',
              onPressed: back,
              icon: const Icon(Icons.chevron_left, size: 26),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 「‹ 2026 / 10 ›」.
class MonthSwitch extends StatelessWidget {
  const MonthSwitch({
    super.key,
    required this.month,
    required this.onChanged,
    this.latest,
  });

  final (int, int) month;
  final ValueChanged<(int, int)> onChanged;

  /// The last month that may be chosen.
  final (int, int)? latest;

  (int, int) _step(int by) {
    final date = DateTime.utc(month.$1, month.$2 + by);
    return (date.year, date.month);
  }

  @override
  Widget build(BuildContext context) {
    final (year, m) = month;
    final last = latest;
    final atEnd = last != null && year * 12 + m >= last.$1 * 12 + last.$2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '上個月',
          onPressed: () => onChanged(_step(-1)),
          icon: const Icon(Icons.chevron_left, color: Hue.muted),
          visualDensity: VisualDensity.compact,
        ),
        Text(
          '$year / $m',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        IconButton(
          tooltip: '下個月',
          onPressed: atEnd ? null : () => onChanged(_step(1)),
          icon: const Icon(Icons.chevron_right, color: Hue.muted),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

/// A section's title in 17 px with something on the right.
class SectionHead extends StatelessWidget {
  const SectionHead(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// An icon on a soft square of its own colour.
class IconBadge extends StatelessWidget {
  const IconBadge(
    this.icon,
    this.color, {
    super.key,
    this.size = 40,
    this.filled = false,
  });

  final IconData icon;
  final Color color;
  final double size;

  /// Solid colour with a light icon, for the chosen option.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? color : softOf(color),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.55, color: filled ? Hue.white : color),
    );
  }
}

/// A rounded panel on the paper.
class SoftPanel extends StatelessWidget {
  const SoftPanel({
    super.key,
    required this.child,
    this.color = Hue.mist,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Material(
      color: color,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Small underlined text that toggles something, such as 「小額放大」.
class LinkToggle extends StatelessWidget {
  const LinkToggle(this.label, {super.key, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Hue.positive,
            decoration: TextDecoration.underline,
            decorationColor: Hue.positive,
          ),
        ),
      ),
    );
  }
}

/// Income and spending side by side in one bar, green from the left and
/// red from the right.
class Rail extends StatelessWidget {
  const Rail({super.key, required this.income, required this.expense});

  final int income;
  final int expense;

  @override
  Widget build(BuildContext context) {
    final total = income + expense;
    final left = total == 0 ? 1 : (income * 1000 / total).round();
    final right = total == 0 ? 1 : 1000 - left;
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            if (left > 0)
              Expanded(
                flex: left,
                child: Container(color: Hue.positive),
              ),
            if (left > 0 && right > 0) const SizedBox(width: 3),
            if (right > 0)
              Expanded(
                flex: right,
                child: Container(color: Hue.negative),
              ),
          ],
        ),
      ),
    );
  }
}

/// A label over an amount, the pair used across summaries.
class Figure extends StatelessWidget {
  const Figure(
    this.label,
    this.value, {
    super.key,
    this.color = Hue.ink,
    this.size = 17,
    this.end = false,
  });

  final String label;
  final String value;
  final Color color;
  final double size;
  final bool end;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Hue.muted)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Short feedback at the bottom, with an optional action.
void showNote(
  BuildContext context,
  String message, {
  String? action,
  VoidCallback? onAction,
}) {
  final act = onAction;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action == null || act == null
            ? null
            : SnackBarAction(
                label: action,
                textColor: Hue.selected,
                onPressed: act,
              ),
      ),
    );
}
