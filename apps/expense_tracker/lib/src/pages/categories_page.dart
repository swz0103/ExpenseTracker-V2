import 'package:flutter/material.dart';

import '../demo/ledger.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'dialogs.dart';
import 'nav.dart';

/// 分類管理: spending and income categories four to a row. Tap one to
/// rename it everywhere; the last tile adds one.
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

  Future<void> _rename(BuildContext context, Category category) async {
    final name = await askText(context, '重新命名', initial: category.name);
    if (name != null) ledger.renameCategory(category.name, name);
  }

  Future<void> _add(BuildContext context, {required bool income}) async {
    final name = await askText(context, income ? '新增收入分類' : '新增支出分類');
    if (name == null) return;
    final count = ledger.categories.length;
    ledger.addCategory(
      Category(
        name,
        categoryIconKeys[count % categoryIconKeys.length],
        _colors[count % _colors.length],
        income: income,
      ),
    );
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
                          onTap: () => _rename(context, c),
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
