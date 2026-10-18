import 'package:flutter/material.dart';

import '../compose/pickers.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import 'nav.dart';

/// 分類管理: spending and income categories four to a row. Tap one to
/// change its name, mark or colour; the last tile adds one.
class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  static const _colors = Hue.shades;

  Future<void> _edit(BuildContext context, Category category) async {
    final next = await showCategoryEditor(
      context,
      title: '編輯分類',
      initial: category,
      colors: _colors,
      ledger: ledger,
    );
    if (next != null) ledger.updateCategory(category.name, next);
  }

  Future<void> _add(BuildContext context, {required bool income}) async {
    final count = ledger.categories.length;
    final made = await showCategoryEditor(
      context,
      title: income ? '新增收入分類' : '新增支出分類',
      initial: Category(
        '',
        income ? 'income' : 'other',
        _colors[count % _colors.length],
        income: income,
      ),
      colors: _colors,
      ledger: ledger,
    );
    if (made != null) ledger.addCategory(made);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 20, 32),
        children: [
          PageHeader('分類管理', onBack: nav.back),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final income in const [false, true]) ...[
                  SectionHead(income ? '收入分類' : '支出分類'),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 0.95,
                    children: [
                      for (final c in _ordered(income))
                        _Tile(
                          icon: iconFor(c.icon),
                          color: c.color,
                          label: c.name,
                          under: c.parent,
                          onTap: () => _edit(context, c),
                        ),
                      _Tile(
                        icon: Glyph.add,
                        color: Hue.faint,
                        label: '新增分類',
                        onTap: () => _add(context, income: income),
                      ),
                    ],
                  ),
                ],
                if (_archived.isNotEmpty) ...[
                  const SectionHead('已封存'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in _archived)
                        ActionChip(
                          avatar: GlyphIcon(iconFor(c.icon), color: c.color),
                          label: Text(c.name),
                          onPressed: () => _edit(context, c),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Open categories of a kind, each followed by those under it.
  List<Category> _ordered(bool income) {
    final open = ledger.categoriesFor(income: income);
    final names = {for (final c in open) c.name};
    return [
      for (final c in open)
        if (c.parent == null || !names.contains(c.parent)) ...[
          c,
          for (final child in open)
            if (child.parent == c.name) child,
        ],
    ];
  }

  List<Category> get _archived => [
    for (final c in ledger.categories)
      if (c.archived) c,
  ];
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.under,
  });

  final Glyph icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  /// The category this one sits under.
  final String? under;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconBadge(icon, color, size: 44),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
          if (under case final parent?)
            Text(
              '‹ $parent',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: Hue.muted),
            ),
        ],
      ),
    );
  }
}

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
      options: [
        for (final o in ledger.categoriesFor(income: c.income))
          if (o.name != c.name)
            Option(o.name, o.name, iconFor(o.icon), o.color),
      ],
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
              child: Text(
                group,
                style: const TextStyle(fontSize: 12.5, color: Hue.muted),
              ),
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
            const Text(
              '放在哪個分類下',
              style: TextStyle(fontSize: 13, color: Hue.muted),
            ),
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
          const Text('顏色', style: TextStyle(fontSize: 13, color: Hue.muted)),
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
