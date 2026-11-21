import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/pickers.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';

// The page of people a spending is paid for, opened from the entry form.

/// The people money can be paid for, to tick any number of them: those
/// already in the spending ticked, 新增對象 at the end, and a button to
/// take the ticked ones back to the form.
class PeopleChoices extends StatefulWidget {
  const PeopleChoices({
    super.key,
    required this.people,
    required this.selected,
    required this.color,
    required this.onDone,
    required this.onAdd,
  });

  final List<Account> people;
  final List<String> selected;
  final Color color;
  final ValueChanged<List<String>> onDone;
  final Future<Account?> Function() onAdd;

  @override
  State<PeopleChoices> createState() => _PeopleChoicesState();
}

class _PeopleChoicesState extends State<PeopleChoices> {
  late final _people = [...widget.people];
  late final _picked = [...widget.selected];

  @override
  Widget build(BuildContext context) {
    const adding = '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OptionGrid<String>(
          columns: 3,
          ring: widget.color,
          selected: null,
          chosen: {..._picked},
          options: [
            for (final a in _people)
              Option(a.id, a.name, Glyph.heart, AppColors.muted),
            const Option(adding, '新增對象', Glyph.add, AppColors.muted),
          ],
          onPick: (id) async {
            if (id != adding) {
              setState(() {
                if (!_picked.remove(id)) _picked.add(id);
              });
              return;
            }
            final made = await widget.onAdd();
            if (made == null || !mounted) return;
            setState(() {
              _people.add(made);
              _picked.add(made.id);
            });
          },
        ),
        const SizedBox(height: Space.s2),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: () => widget.onDone(_picked),
            // With nobody picked it only closes the panel: a quiet button,
            // so 不代墊 does not read as the thing to press.
            style: _picked.isEmpty
                ? solidButton(
                    AppColors.surface,
                    ink: widget.color,
                    radius: Radii.large,
                  )
                : solidButton(widget.color, radius: Radii.large),
            child: Text(
              _picked.isEmpty ? '不代墊' : '好了（${_picked.length} 人）',
              style: const TextStyle(
                fontSize: TextSize.title,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
