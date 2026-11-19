import 'package:flutter/material.dart';

import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/haptics.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/platform/preferences.dart';
import '../model/overview_blocks.dart';
import '../../../core/design_system/spacing.dart';

/// Lets the person put 總覽's blocks in another order and hide some;
/// each change is kept at once.
Future<void> editOverview(BuildContext context, Preferences preferences) =>
    showSheet<void>(context, (_) => _OverviewEditor(preferences: preferences));

class _OverviewEditor extends StatefulWidget {
  const _OverviewEditor({required this.preferences});

  final Preferences preferences;

  @override
  State<_OverviewEditor> createState() => _OverviewEditorState();
}

class _OverviewEditorState extends State<_OverviewEditor> {
  late var _choices = blocksFrom(widget.preferences.overview);

  void _keep(List<BlockChoice> choices) {
    setState(() => _choices = choices);
    widget.preferences.overviewSet(blocksToKeep(choices));
  }

  void _move(int from, int to) {
    Haptics.selection();
    final next = [..._choices];
    // [to] already counts the block taken out.
    next.insert(to, next.removeAt(from));
    _keep(next);
  }

  void _show(int index, bool shown) {
    final next = [..._choices];
    next[index] = (block: next[index].block, shown: shown);
    _keep(next);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '調整總覽',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: TextSize.heading,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.s1),
          const Text(
            '拖曳右側把手排序，關掉的區塊不會顯示',
            textAlign: TextAlign.center,
            style: mutedSmall,
          ),
          const SizedBox(height: Space.s2),
          ReorderableListView(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            onReorderItem: _move,
            children: [
              for (final (i, (:block, :shown)) in _choices.indexed)
                Material(
                  key: ValueKey(block),
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    // The whole row shows or hides the block.
                    onTap: () => _show(i, !shown),
                    title: Text(
                      block.label,
                      style: TextStyle(
                        color: shown ? AppColors.ink : AppColors.muted,
                      ),
                    ),
                    leading: TickSwitch(
                      value: shown,
                      label: block.label,
                      onChanged: (on) => _show(i, on),
                    ),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.all(Space.s3),
                        child: Semantics(
                          label: '拖曳排序',
                          child: const GlyphIcon(
                            Glyph.sliders,
                            size: 20,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          TextButton(
            onPressed: () {
              widget.preferences.overviewSet(null);
              setState(() => _choices = blocksFrom(null));
            },
            child: const Text('恢復預設'),
          ),
        ],
      ),
    );
  }
}
