import 'package:flutter/material.dart';

import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import 'entries_filter_sheet.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';

/// The search box and 篩選 beside it, at the top of the entries.
class EntriesSearchRow extends StatelessWidget {
  const EntriesSearchRow({
    super.key,
    required this.text,
    required this.focus,
    required this.decoration,
    required this.onChanged,
    required this.filterCount,
    required this.onFilter,
  });

  /// What is typed, kept by the page so the line can be built again.
  final TextEditingController text;
  final FocusNode focus;

  /// The box's look, built again as the text changes (its clear button).
  final InputDecoration Function() decoration;
  final ValueChanged<String> onChanged;

  /// How many filters are on.
  final int filterCount;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: ListenableBuilder(
          listenable: text,
          builder: (context, _) => TextField(
            controller: text,
            focusNode: focus,
            textInputAction: TextInputAction.search,
            decoration: decoration(),
            onChanged: onChanged,
          ),
        ),
      ),
      const SizedBox(width: Space.s2),
      _FilterButton(count: filterCount, onTap: onFilter),
    ],
  );
}

/// The filters on, as pills under the search; each pill's ✕ takes its
/// filter off through [onChange].
class EntriesFilterPills extends StatelessWidget {
  const EntriesFilterPills({
    super.key,
    required this.filter,
    required this.accountName,
    required this.onChange,
  });

  final EntryFilter filter;

  /// The name of the account filtered on, if any.
  final String? accountName;

  /// Applies a change to the page's filter as it is then.
  final void Function(EntryFilter Function(EntryFilter) change) onChange;

  @override
  Widget build(BuildContext context) {
    final accountName = this.accountName;
    final category = filter.category;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (filter.kind != KindFilter.all)
            ChoicePill.removable(
              label: filter.kind.label,
              onRemove: () => onChange((f) => f.withKind(KindFilter.all)),
            ),
          if (filter.range case final range?)
            ChoicePill.removable(
              label: EntryFilter.rangeLabel(range),
              onRemove: () => onChange((f) => f.withoutRange()),
            ),
          if (filter.boundsAmount)
            ChoicePill.removable(
              label: filter.amountLabel,
              onRemove: () => onChange((f) => f.withoutAmounts()),
            ),
          if (accountName != null)
            ChoicePill.removable(
              label: accountName,
              onRemove: () => onChange((f) => f.withoutAccount()),
            ),
          if (category != null)
            ChoicePill.removable(
              label: category,
              onRemove: () => onChange((f) => f.withoutCategory()),
            ),
        ],
      ),
    );
  }
}

/// 篩選 beside the search: filled in the accent, with how many filters
/// are on, while any narrows the list.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = count > 0;
    return Tooltip(
      message: on ? '篩選（$count）' : '篩選',
      child: Material(
        color: on ? AppColors.accent : AppColors.white,
        borderRadius: BorderRadius.circular(Radii.large),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: on ? Space.s3 : Space.s4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GlyphIcon(
                    Glyph.sliders,
                    size: 18,
                    color: on ? AppColors.onAccent : AppColors.accent,
                  ),
                  if (on) ...[
                    const SizedBox(width: Space.s2),
                    Text(
                      '$count',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.onAccent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
