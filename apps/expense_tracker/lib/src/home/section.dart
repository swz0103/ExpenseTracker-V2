import 'package:flutter/material.dart';

import '../theme.dart';

/// One part of the home page: no box around it, just room and, between
/// parts, a hairline.
class Section extends StatelessWidget {
  const Section({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      child: child,
    );
    return onTap == null ? body : InkWell(onTap: onTap, child: body);
  }
}

/// A section's small title, with an optional note on the right.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Palette.muted, letterSpacing: 1);
    final note = trailing;
    return Row(
      children: [
        Text(title, style: style),
        const Spacer(),
        if (note != null) Text(note, style: style),
      ],
    );
  }
}
