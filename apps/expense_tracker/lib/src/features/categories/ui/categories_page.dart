import 'package:flutter/material.dart';

import '../compose/category_editor.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/haptics.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';

/// 分類: 支出 or 收入 on two big segments, then that kind's categories
/// three to a row, each its solid icon and name on its own tint, a small
/// count of the ones under it; ＋ 新增 last. A long press picks a tile up
/// to drag it to another place. Archived ones sit under 已封存 as small
/// chips, a tap bringing one back.
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  static const _colors = Hue.categoryColors;

  var _income = false;

  /// The names in the order shown while one is being dragged; null when
  /// none is.
  List<String>? _dragging;

  Ledger get ledger => widget.ledger;

  Future<void> _edit(Category category) =>
      editCategory(context, ledger, category);

  Future<void> _add() async {
    final count = ledger.categories.length;
    final made = await showCategoryEditor(
      context,
      title: _income ? '新增收入分類' : '新增支出分類',
      initial: Category(
        '',
        _income ? 'income' : 'other',
        _colors[count % _colors.length],
        income: _income,
      ),
      colors: _colors,
      ledger: ledger,
    );
    if (made != null) ledger.addCategory(made);
  }

  /// Top-level open categories of the kind shown, in their order.
  List<Category> _tops(bool income) => [
    for (final c in ledger.categoriesFor(income: income))
      if (c.parent == null || ledger.category(c.parent!).archived) c,
  ];

  /// Keeps the order dragged to: this kind's tops as dragged, then
  /// everything else in the order it stands. Each kind is shown on its
  /// own, so only the order within a kind is seen.
  void _place(List<String> names) {
    ledger.placeCategories([
      ...names,
      for (final c in ledger.categories)
        if (!names.contains(c.name)) c.name,
    ]);
  }

  void _moveOver(String dragged, String target) {
    final order = _dragging;
    if (order == null || dragged == target) return;
    final from = order.indexOf(dragged);
    final to = order.indexOf(target);
    if (from < 0 || to < 0) return;
    setState(() {
      order
        ..removeAt(from)
        ..insert(to, dragged);
    });
    Haptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final tops = _tops(_income);
        final byName = {for (final c in tops) c.name: c};
        final order = _dragging ?? [for (final c in tops) c.name];
        final archived = [
          for (final c in ledger.categories)
            if (c.archived && c.income == _income) c,
        ];
        final children = <String, int>{};
        for (final c in ledger.categoriesFor(income: _income)) {
          if (c.parent case final parent?) {
            children[parent] = (children[parent] ?? 0) + 1;
          }
        }
        final tiles = <Widget>[
          for (final name in order)
            if (byName[name] case final c?)
              _Draggable(
                name: name,
                onStart: () =>
                    setState(() => _dragging = [for (final c in tops) c.name]),
                onOver: _moveOver,
                onEnd: () {
                  final done = _dragging;
                  setState(() => _dragging = null);
                  if (done != null) _place(done);
                },
                child: _Tile(
                  glyph: iconFor(c.icon),
                  color: c.color,
                  label: c.name,
                  count: children[c.name] ?? 0,
                  onTap: () => _edit(c),
                ),
              ),
          _Tile(
            glyph: Glyph.add,
            color: Hue.faint,
            label: '新增',
            plain: true,
            onTap: _add,
          ),
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            CenterHeader('分類', onBack: widget.nav.back),
            Row(
              children: [
                for (final (i, income) in const [false, true].indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: _Kind(
                      label: income ? '收入' : '支出',
                      count: _tops(income).length,
                      color: income ? Hue.positive : Hue.negative,
                      chosen: _income == income,
                      onTap: () => setState(() => _income = income),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            CardGrid(columns: 3, gap: 10, tiles),
            if (archived.isNotEmpty) ...[
              const RuleHead('已封存'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in archived)
                    ActionChip(
                      backgroundColor: Hue.surface,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      avatar: GlyphIcon(
                        iconFor(c.icon),
                        size: 18,
                        color: Hue.muted,
                      ),
                      label: Text(
                        c.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Hue.muted,
                        ),
                      ),
                      tooltip: '恢復「${c.name}」',
                      onPressed: () => ledger.updateCategory(
                        c.name,
                        c.copyWith(archived: false),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Opens [category] in the editor and keeps what is saved.
Future<void> editCategory(
  BuildContext context,
  Ledger ledger,
  Category category,
) async {
  final next = await showCategoryEditor(
    context,
    title: '編輯分類',
    initial: category,
    colors: Hue.categoryColors,
    ledger: ledger,
  );
  if (next != null) ledger.updateCategory(category.name, next);
}

/// 支出 10 or 收入 4: solid in its colour when chosen.
class _Kind extends StatelessWidget {
  const _Kind({
    required this.label,
    required this.count,
    required this.color,
    required this.chosen,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = chosen ? Hue.onAccent : Hue.muted;
    return Semantics(
      selected: chosen,
      button: true,
      label: '$label $count 個',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: chosen ? Hue.tileShadow : null,
        ),
        child: Material(
          color: chosen ? color : Hue.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Center(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: label,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(
                        text: '  $count',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                  style: TextStyle(color: ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A category picked up by a long press and dropped over another to take
/// its place.
class _Draggable extends StatelessWidget {
  const _Draggable({
    required this.name,
    required this.onStart,
    required this.onOver,
    required this.onEnd,
    required this.child,
  });

  final String name;
  final VoidCallback onStart;
  final void Function(String dragged, String target) onOver;
  final VoidCallback onEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        onOver(details.data, name);
        return true;
      },
      builder: (context, _, _) => LongPressDraggable<String>(
        data: name,
        hapticFeedbackOnStart: true,
        onDragStarted: onStart,
        onDragEnd: (_) => onEnd(),
        feedback: SizedBox(
          // A third of the page between its 20 dp sides and 10 dp gaps.
          width: (MediaQuery.sizeOf(context).width - 60) / 3,
          height: 110,
          child: Material(
            color: Colors.transparent,
            child: Transform.scale(scale: 1.06, child: child),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: child),
        child: child,
      ),
    );
  }
}

/// A category as a tile: its solid icon on its tint, its name under it,
/// and in the corner how many sit under it.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.glyph,
    required this.color,
    required this.label,
    required this.onTap,
    this.count = 0,
    this.plain = false,
  });

  final Glyph glyph;
  final Color color;
  final String label;
  final VoidCallback onTap;

  /// How many categories sit under this one.
  final int count;

  /// ＋ 新增: a white square on grey.
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final mark = plain
        ? Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Hue.white,
              borderRadius: BorderRadius.circular(15),
            ),
            alignment: Alignment.center,
            child: const GlyphIcon(Glyph.add, size: 24, color: Hue.ink),
          )
        : SquareIcon(glyph, color, size: 50);
    return ColorCard(
      color: plain ? Hue.faint : color,
      amount: plain ? 0.25 : 0.2,
      radius: 20,
      onTap: onTap,
      label: count > 0 ? '$label，$count 個子分類' : label,
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              mark,
              if (count > 0)
                Positioned(
                  right: -10,
                  top: -6,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Hue.white,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$count',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: deepOf(color),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: plain ? Hue.ink : deepOf(color),
            ),
          ),
        ],
      ),
    );
  }
}
