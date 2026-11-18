import 'package:flutter/material.dart';

import '../../../core/look/glyphs.dart';
import '../../../core/ui/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/look/shape.dart';
import '../../../core/look/spacing.dart';
import '../model/category_form.dart';
import 'category_form_widgets.dart';

/// 編輯分類: a big card in the category's tint with its icon (tapped to
/// choose another) and name, a row of colours, the ones under it four to
/// a row with ＋子分類, and 合併, 封存 and 儲存 along the bottom. Returns
/// the category, or null when cancelled or left without a name.
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
  /// The fields and what the book allows.
  late final _f = CategoryForm(widget.initial, ledger: widget.ledger);
  late final _name = TextEditingController(text: widget.initial.name);
  String? _problem;

  /// The icons are open to choose from.
  var _icons = false;

  Color get _color => Color(_f.color);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final made = _f.build(_name.text);
    if (made == null) return;
    final problem = _f.problemOf(made.name);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.of(context).pop(made);
  }

  void _archive(Ledger ledger) {
    final c = widget.initial;
    ledger.categoryCommands.updateCategory(
      c.name,
      c.copyWith(archived: !c.archived),
    );
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
    ledger.categoryCommands.mergeCategory(c.name, into);
    Navigator.of(context).pop();
  }

  Future<void> _addChild(Ledger ledger) async {
    final made = await showCategoryEditor(
      context,
      title: '新增子分類',
      initial: _f.newChild,
      colors: widget.colors,
      ledger: ledger,
    );
    if (made != null) ledger.categoryCommands.addCategory(made);
    if (mounted) setState(() {});
  }

  Future<void> _editChild(Ledger ledger, Category child) async {
    final next = await showCategoryEditor(
      context,
      title: '編輯分類',
      initial: child,
      colors: widget.colors,
      ledger: ledger,
    );
    if (next != null) ledger.categoryCommands.updateCategory(child.name, next);
    if (mounted) setState(() {});
  }

  Future<void> _pickParent(Ledger ledger) async {
    final picked = await pickOption<String>(
      context,
      title: '放在哪個分類下',
      selected: _f.parent ?? '',
      options: [
        const Option('', '不放', Glyph.close, Hue.muted),
        for (final name in _f.parents)
          Option(
            name,
            name,
            iconFor(ledger.category(name).icon),
            shownColor(Color(ledger.category(name).color)),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _f.parent = picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final book = _f.book;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              widget.title,
              style: const TextStyle(
                fontSize: TextSize.heading,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: Space.s4),
          _card(),
          if (_problem case final problem?)
            Padding(
              padding: const EdgeInsets.only(top: Space.s2),
              child: Text(problem, style: const TextStyle(color: Hue.danger)),
            ),
          if (_icons)
            for (final (group, keys) in categoryIconGroups) ...[
              Padding(
                padding: const EdgeInsets.only(top: Space.s3, bottom: Space.s2),
                child: Text(group, style: mutedSmall),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final key in keys)
                    IconChoice(
                      icon: key,
                      color: _color,
                      picked: key == _f.icon,
                      onTap: () => setState(() {
                        _f.icon = key;
                        _icons = false;
                      }),
                    ),
                ],
              ),
            ],
          const SizedBox(height: Space.s4),
          ColorChoiceRow(
            colors: widget.colors,
            chosen: _color,
            onChosen: (color) => setState(() => _f.color = color.toARGB32()),
          ),
          if (book != null && _f.offersChildren) ..._children(book),
          if (ledger != null && _f.offersParent) ...[
            const SizedBox(height: Space.s2),
            ParentCategoryChoice(
              parent: _f.parent,
              onTap: () => _pickParent(ledger),
            ),
          ],
          const SizedBox(height: Space.s4),
          _actions(book),
        ],
      ),
    );
  }

  /// The card that is the form: the icon, tapped to choose another, and
  /// the name on the category's tint.
  Widget _card() {
    final ink = deepOf(_color);
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: tintOf(_color, 0.22),
        borderRadius: BorderRadius.circular(Radii.largeIncreased),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: '換圖示',
            child: GestureDetector(
              onTap: () => setState(() => _icons = !_icons),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  SquareIcon(iconFor(_f.icon), _color, size: 64),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Hue.white,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: GlyphIcon(Glyph.edit, size: 13, color: ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: Space.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '名稱',
                  style: TextStyle(
                    fontSize: TextSize.caption,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                TextField(
                  controller: _name,
                  autofocus: _f.isNew,
                  style: TextStyle(
                    fontSize: TextSize.large,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                  decoration: InputDecoration.collapsed(
                    hintText: '點這裡取個名字',
                    hintStyle: TextStyle(
                      fontSize: TextSize.heading,
                      color: ink.withValues(alpha: 0.6),
                    ),
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 子分類: those under it, four to a row, and ＋子分類.
  List<Widget> _children(Ledger book) => [
    const SizedBox(height: Space.s2),
    const Text(
      '子分類',
      style: TextStyle(
        fontSize: TextSize.body,
        fontWeight: FontWeight.w700,
        color: Hue.muted,
      ),
    ),
    const SizedBox(height: Space.s2),
    CardGrid(columns: 4, gap: 8, [
      for (final c in _f.children)
        SubcategoryTile(
          label: c.name,
          glyph: iconFor(c.icon),
          color: _color,
          onTap: () => _editChild(book, c),
        ),
      SubcategoryTile(
        label: '子分類',
        glyph: Glyph.add,
        color: _color,
        add: true,
        onTap: () => _addChild(book),
      ),
    ]),
  ];

  /// 合併 and 封存 for a kept category, 取消 for a new one, and 儲存.
  Widget _actions(Ledger? book) {
    return Row(
      children: [
        if (book != null) ...[
          Expanded(child: PanelButton('合併', onTap: () => _merge(book))),
          const SizedBox(width: Space.s2),
          Expanded(
            child: PanelButton(
              widget.initial.archived ? '恢復' : '封存',
              onTap: () => _archive(book),
            ),
          ),
          const SizedBox(width: Space.s2),
        ] else ...[
          Expanded(
            child: PanelButton('取消', onTap: () => Navigator.of(context).pop()),
          ),
          const SizedBox(width: Space.s2),
        ],
        Expanded(
          flex: 2,
          child: PanelButton('儲存', color: Hue.accent, onTap: _save),
        ),
      ],
    );
  }
}
