part of 'backup_section.dart';

/// A setting on a [_BackupCard]: its name, and on the right its value
/// with › or a control.
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.color,
    required this.title,
    this.detail,
    this.value,
    this.trailing,
    this.onTap,
  });

  final Color color;
  final String title;
  final String? detail;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.medium),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  OneLine(
                    title,
                    style: TextStyle(
                      fontSize: TextSize.body,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: TextStyle(fontSize: TextSize.caption, color: ink),
                    ),
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(right: Space.s2),
                child: OneLine(
                  '${value!} ›',
                  style: TextStyle(fontWeight: FontWeight.w700, color: ink),
                ),
              ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
