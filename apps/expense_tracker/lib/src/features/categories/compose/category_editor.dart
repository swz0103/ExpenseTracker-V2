import 'package:flutter/material.dart';

import '../../../core/look/glyphs.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/pickers.dart';

/// A dialog to name a category and pick its mark and colour. Returns the
/// category, or null when cancelled or left without a name.
Future<Category?> showCategoryEditor(
  BuildContext context, {
  required String title,
  required Category initial,
  required List<Color> colors,
  Ledger? ledger,
}) {
  return showSheet<Category>(
    context,
    (_) => _CategoryEditor(
      title: title,
      initial: initial,
      colors: colors,
      ledger: ledger,
    ),
  );
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({
    required this.title,
    required this.initial,
    required this.colors,
    this.ledger,
  });

  final String title;
  final Category initial;
  final List<Color> colors;

  /// The book, when an existing category may be moved, archived or
  /// merged.
  final Ledger? ledger;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.initial.name);
  late var _icon = widget.initial.icon;
  late var _color = widget.initial.color;
  late var _parent = widget.initial.parent;
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    // Categories are found by name: two with one name would be one.
    final taken = widget.ledger?.categories.any((c) => c.name == name) ?? false;
    if (taken && name != widget.initial.name) {
      setState(() => _problem = '已經有「$name」這個分類，可以改用合併');
      return;
    }
    final made = Category(
      name,
      _icon,
      _color,
      income: widget.initial.income,
      parent: _parent,
      archived: widget.initial.archived,
    );
    Navigator.of(context).pop(made);
  }

  void _archive(Ledger ledger) {
    final c = widget.initial;
    ledger.updateCategory(c.name, c.copyWith(archived: !c.archived));
    Navigator.of(context).pop();
  }

  Future<void> _merge(Ledger ledger) async {
    final c = widget.initial;
    final into = await pickOption<String>(
      context,
      title: '把「${c.name}」合併到',
      selected: null,
      options: categoryOptions(
        ledger,
        income: c.income,
        where: (o) => o.name != c.name,
      ),
    );
    if (into == null || !mounted) return;
    ledger.mergeCategory(c.name, into);
    Navigator.of(context).pop();
  }

  Widget _iconChoice(String key) {
    final picked = key == _icon;
    return InkWell(
      onTap: () => setState(() => _icon = key),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: picked ? softOf(_color) : Hue.tile,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: picked ? _color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: GlyphIcon(
          iconFor(key),
          color: picked ? _color : Hue.muted,
          tinted: picked,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final book = widget.initial.name.isEmpty ? null : ledger;
    final hasChildren =
        ledger?.categories.any((c) => c.parent == widget.initial.name) ?? false;
    final parents = [
      if (ledger != null)
        for (final c in ledger.categoriesFor(income: widget.initial.income))
          if (c.parent == null && c.name != widget.initial.name) c.name,
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(iconFor(_icon), _color, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: widget.initial.name.isEmpty,
                  decoration: InputDecoration(
                    hintText: widget.title,
                    isDense: true,
                    filled: true,
                    fillColor: Hue.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ),
            ],
          ),
          if (_problem case final problem?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(problem, style: const TextStyle(color: Hue.danger)),
            ),
          const SizedBox(height: 16),
          for (final (group, keys) in categoryIconGroups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Text(group, style: mutedSmall),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final key in keys) _iconChoice(key)],
            ),
          ],
          const SizedBox(height: 16),
          // One level only: a category with its own subcategories stays on
          // top.
          if (parents.isNotEmpty && !hasChildren) ...[
            const Text('放在哪個分類下', style: mutedSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('不放'),
                  selected: _parent == null,
                  onSelected: (_) => setState(() => _parent = null),
                ),
                for (final name in parents)
                  ChoiceChip(
                    label: Text(name),
                    selected: _parent == name,
                    onSelected: (_) => setState(() => _parent = name),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          const Text('顏色', style: mutedSmall),
          const SizedBox(height: 8),
          Wrap(
            runSpacing: 8,
            children: [
              for (final color in widget.colors)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkResponse(
                    onTap: () => setState(() => _color = color),
                    radius: 22,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == _color ? Hue.ink : Hue.panel,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (book != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => _merge(book),
                    style: TextButton.styleFrom(foregroundColor: Hue.accent),
                    child: const Text('合併到其他分類'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _archive(book),
                    style: TextButton.styleFrom(foregroundColor: Hue.danger),
                    child: Text(widget.initial.archived ? '恢復' : '封存'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: Hue.muted),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('儲存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
