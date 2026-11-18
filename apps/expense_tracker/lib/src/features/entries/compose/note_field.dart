import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/look/glyphs.dart';
import '../../../core/look/shape.dart';
import '../../../core/look/spacing.dart';
import '../../../core/look/theme.dart';

/// An entry's note: a box to type in, [lines] tall and growing to three,
/// with [hint] while it is empty. While [viewing], the note is words on
/// the page, once, and nothing when there is none.
class NoteField extends StatelessWidget {
  const NoteField({
    super.key,
    required this.controller,
    required this.viewing,
    this.lines = 1,
    this.hint = '寫點備註…',
  });

  final TextEditingController controller;
  final bool viewing;
  final int lines;
  final String hint;

  @override
  Widget build(BuildContext context) {
    if (viewing) {
      if (controller.text.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.s1, Space.s2, Space.s1, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: Space.half),
              child: GlyphIcon(Glyph.note, size: 18, color: Hue.muted),
            ),
            const SizedBox(width: Space.s2),
            Expanded(
              child: Text(
                controller.text,
                style: const TextStyle(fontSize: TextSize.body),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: TextField(
        controller: controller,
        minLines: lines,
        maxLines: math.max(lines, 3),
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: Hue.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Radii.large),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// The note under a short form: folded to one line, 備註, until it is
/// tapped ([onOpen]) or [open]; a [NoteField] once open, written in, or
/// while [viewing].
class NoteRow extends StatelessWidget {
  const NoteRow({
    super.key,
    required this.controller,
    required this.viewing,
    required this.open,
    required this.onOpen,
  });

  final TextEditingController controller;
  final bool viewing;
  final bool open;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (open || controller.text.isNotEmpty || viewing) {
      return NoteField(controller: controller, viewing: viewing);
    }
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.medium),
        onTap: onOpen,
        child: const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s4,
          ),
          child: Row(
            children: [
              GlyphIcon(Glyph.note, size: 18, color: Hue.muted),
              SizedBox(width: Space.s2),
              Expanded(
                child: Text(
                  '備註',
                  style: TextStyle(
                    fontSize: TextSize.body,
                    fontWeight: FontWeight.w600,
                    color: Hue.muted,
                  ),
                ),
              ),
              RotatedBox(
                quarterTurns: 1,
                child: GlyphIcon(Glyph.next, size: 16, color: Hue.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
