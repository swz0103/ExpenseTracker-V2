part of 'account_editor.dart';

/// The card on top of the form, and its first fields: the mark, the name
/// typed straight onto it and a dot of its colour that opens the
/// colours, over the balance.
class _EditCard extends StatelessWidget {
  const _EditCard({
    required this.color,
    required this.icon,
    required this.kind,
    required this.name,
    required this.balance,
    required this.balanceLabel,
    required this.onColor,
  });

  final Color color;
  final Glyph icon;
  final String kind;
  final TextEditingController name;
  final TextEditingController balance;
  final String balanceLabel;
  final VoidCallback onColor;

  @override
  Widget build(BuildContext context) {
    const plain = InputDecoration(
      isDense: true,
      border: InputBorder.none,
      contentPadding: EdgeInsets.symmetric(vertical: Space.s2),
    );
    return Material(
      color: softOf(color),
      borderRadius: BorderRadius.circular(Radii.largeIncreased),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s2,
          Space.s2,
          Space.s2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Hue.glass,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: GlyphIcon(icon, size: 17, color: color),
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: TextField(
                    controller: name,
                    style: const TextStyle(
                      fontSize: TextSize.title,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: plain.copyWith(
                      hintText: '帳戶名稱',
                      hintStyle: const TextStyle(color: Hue.faint),
                    ),
                  ),
                ),
                Text(kind, style: mutedSmall),
                Semantics(
                  button: true,
                  label: '卡片顏色',
                  excludeSemantics: true,
                  child: InkResponse(
                    onTap: onColor,
                    radius: 24,
                    child: SizedBox.square(
                      dimension: 48,
                      child: Center(
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Hue.white, width: 3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(balanceLabel, style: mutedSmall),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: TextField(
                    controller: balance,
                    textAlign: TextAlign.end,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(
                      fontSize: TextSize.large,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: plain.copyWith(
                      hintText: '0',
                      hintStyle: const TextStyle(color: Hue.faint),
                    ),
                  ),
                ),
                const SizedBox(width: Space.s2),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.number = false,
  });

  final TextEditingController controller;
  final String hint;
  final bool number;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Hue.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.medium),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// A day of the month in the closing or due day picker: a 48 dp key
/// named for a screen reader.
class _DayKey extends StatelessWidget {
  const _DayKey({required this.day, required this.picked, required this.onTap});

  final int day;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      label: '$day 日',
      selected: picked,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: picked ? Hue.accent : Hue.tile,
          borderRadius: BorderRadius.circular(Radii.small),
        ),
        child: Text(
          '$day',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: picked ? Hue.onAccent : Hue.ink,
          ),
        ),
      ),
    );
  }
}
