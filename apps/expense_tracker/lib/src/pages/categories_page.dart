import 'package:flutter/material.dart';

import '../demo/ledger.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'nav.dart';

/// 分類管理: spending and income categories four to a row. Tap one to
/// change its name, mark or colour; the last tile adds one.
class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  static const _colors = [
    Color(0xFF78906D),
    Color(0xFFC28B60),
    Color(0xFF6E929B),
    Color(0xFF927EAA),
    Color(0xFFB19A56),
    Color(0xFFB77380),
  ];

  Future<void> _edit(BuildContext context, Category category) async {
    final next = await showCategoryEditor(
      context,
      title: '編輯分類',
      initial: category,
      colors: _colors,
    );
    if (next != null) ledger.editCategory(category.name, next);
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
                      for (final c in ledger.categoriesFor(income: income))
                        _Tile(
                          icon: iconFor(c.icon),
                          color: c.color,
                          label: c.name,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final Glyph icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

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
}) {
  return showDialog<Category>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Hue.panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: _CategoryEditor(title: title, initial: initial, colors: colors),
    ),
  );
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({
    required this.title,
    required this.initial,
    required this.colors,
  });

  final String title;
  final Category initial;
  final List<Color> colors;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.initial.name);
  late var _icon = widget.initial.icon;
  late var _color = widget.initial.color;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final made = Category(name, _icon, _color, income: widget.initial.income);
    Navigator.of(context).pop(made);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
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
          const SizedBox(height: 16),
          const Text('圖示', style: TextStyle(fontSize: 13, color: Hue.muted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final key in categoryIconKeys)
                InkWell(
                  onTap: () => setState(() => _icon = key),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: key == _icon ? softOf(_color) : null,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: key == _icon ? _color : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: GlyphIcon(
                      iconFor(key),
                      color: key == _icon ? _color : Hue.muted,
                      tinted: key == _icon,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('顏色', style: TextStyle(fontSize: 13, color: Hue.muted)),
          const SizedBox(height: 8),
          Row(
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
          const SizedBox(height: 20),
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
