part of 'backup_section.dart';

/// 匯出一份 or 還原: a tinted button with an icon.
class _Manual extends StatelessWidget {
  const _Manual({
    required this.glyph,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final Glyph glyph;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return ColorCard(
      color: color,
      radius: 18,
      amount: 0.18,
      label: label,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        vertical: Space.s4,
        horizontal: Space.s2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GlyphIcon(glyph, size: 20, color: ink, tinted: false),
          const SizedBox(width: Space.s2),
          Flexible(
            child: OneLine(
              label,
              style: TextStyle(
                fontSize: TextSize.title,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
