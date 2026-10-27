import 'package:flutter/material.dart';

import '../../../core/look/glyphs.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/preferences.dart';
import '../model/overview_blocks.dart';

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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '調整總覽',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            '拖曳右側把手排序，關掉的區塊不會顯示',
            textAlign: TextAlign.center,
            style: mutedSmall,
          ),
          const SizedBox(height: 8),
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
                    title: Text(
                      block.label,
                      style: TextStyle(color: shown ? Hue.ink : Hue.muted),
                    ),
                    leading: Switch(
                      value: shown,
                      onChanged: (on) => _show(i, on),
                    ),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Semantics(
                          label: '拖曳排序',
                          child: const GlyphIcon(
                            Glyph.sliders,
                            size: 20,
                            color: Hue.muted,
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
