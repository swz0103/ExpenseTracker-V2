import 'package:flutter/material.dart';

import '../compose/category_editor.dart';
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
              style: const TextStyle(fontSize: 11.5, color: Hue.muted),
            ),
        ],
      ),
    );
  }
}
