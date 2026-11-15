part of 'composer.dart';

/// A row of [_StripItem]s that slides sideways, with [pinned] kept still
/// at its right end after a thin line, so it is never pushed out of view.
class _Strip extends StatelessWidget {
  const _Strip({required this.items, this.pinned});

  final List<Widget> items;
  final Widget? pinned;

  @override
  Widget build(BuildContext context) {
    final still = pinned;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: items),
            ),
          ),
          if (still != null) ...[
            // Centred on the 50 dp squares beside it, not on their words.
            Container(
              width: 1,
              height: 34,
              margin: const EdgeInsets.only(top: 8, left: 4, right: 4),
              color: Hue.line,
            ),
            still,
          ],
        ],
      ),
    );
  }
}
