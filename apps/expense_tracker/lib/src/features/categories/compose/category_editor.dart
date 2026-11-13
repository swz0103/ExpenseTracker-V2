import 'package:flutter/material.dart';

import '../../../core/look/glyphs.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/pickers.dart';

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
  late final _name = TextEditingController(text: widget.initial.name);
  late var _icon = widget.initial.icon;
  late var _color = widget.initial.color;
  late var _parent = widget.initial.parent;
  String? _problem;

  /// The icons are open to choose from.
  var _icons = false;

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
      place: widget.initial.place,
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
      onTap: () => setState(() {
        _icon = key;
        _icons = false;
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: picked ? _color : Hue.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: GlyphIcon(
          iconFor(key),
          color: picked ? const Color(0xFFFFFFFF) : Hue.muted,
          tinted: !picked,
        ),
      ),
    );
  }

  /// A category under this one, or ＋子分類.
  Widget _child(
    String label,
    Glyph glyph,
    VoidCallback onTap, {
    bool add = false,
  }) {
    return ColorCard(
      color: add ? Hue.faint : _color,
      amount: add ? 0.25 : 0.2,
      radius: 16,
      onTap: onTap,
      label: label,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      child: Column(
        children: [
          add
              ? Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Hue.white,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: const GlyphIcon(Glyph.add, size: 18, color: Hue.ink),
                )
              : SquareIcon(glyph, _color, size: 36),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: add ? Hue.ink : deepOf(_color),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addChild(Ledger ledger) async {
    final c = widget.initial;
    final made = await showCategoryEditor(
      context,
      title: '新增子分類',
      initial: Category('', c.icon, _color, income: c.income, parent: c.name),
      colors: widget.colors,
      ledger: ledger,
    );
    if (made != null) ledger.addCategory(made);
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
    if (next != null) ledger.updateCategory(child.name, next);
    if (mounted) setState(() {});
  }

  Future<void> _pickParent(Ledger ledger, List<String> parents) async {
    final picked = await pickOption<String>(
      context,
      title: '放在哪個分類下',
      selected: _parent ?? '',
      options: [
        const Option('', '不放', Glyph.close, Hue.muted),
        for (final name in parents)
          Option(
            name,
            name,
            iconFor(ledger.category(name).icon),
            ledger.category(name).color,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _parent = picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final book = widget.initial.name.isEmpty ? null : ledger;
    final children = [
      if (ledger != null && widget.initial.name.isNotEmpty)
        for (final c in ledger.categoriesFor(income: widget.initial.income))
          if (c.parent == widget.initial.name) c,
    ];
    final parents = [
      if (ledger != null)
        for (final c in ledger.categoriesFor(income: widget.initial.income))
          if (c.parent == null && c.name != widget.initial.name) c.name,
    ];
    final ink = deepOf(_color);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              widget.title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 14),
          // The card is the form: the icon and the name on the tint.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tintOf(_color, 0.22),
              borderRadius: BorderRadius.circular(22),
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
                        SquareIcon(iconFor(_icon), _color, size: 64),
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
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '名稱',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      TextField(
                        controller: _name,
                        autofocus: widget.initial.name.isEmpty,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                        decoration: InputDecoration.collapsed(
                          hintText: '點這裡取個名字',
                          hintStyle: TextStyle(
                            fontSize: 20,
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
          ),
          if (_problem case final problem?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(problem, style: const TextStyle(color: Hue.danger)),
            ),
          if (_icons)
            for (final (group, keys) in categoryIconGroups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Text(group, style: mutedSmall),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final key in keys) _iconChoice(key)],
              ),
            ],
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final color in widget.colors)
                  Semantics(
                    button: true,
                    selected: color == _color,
                    label: '顏色',
                    child: InkResponse(
                      onTap: () => setState(() => _color = color),
                      radius: 24,
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        child: Container(
                          width: color == _color ? 34 : 28,
                          height: color == _color ? 34 : 28,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: color == _color
                                ? Border.all(color: Hue.white, width: 3)
                                : null,
                            boxShadow: color == _color
                                ? [BoxShadow(color: color, spreadRadius: 2)]
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (book != null && widget.initial.parent == null) ...[
            const SizedBox(height: 10),
            const Text(
              '子分類',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Hue.muted,
              ),
            ),
            const SizedBox(height: 8),
            CardGrid(columns: 4, gap: 8, [
              for (final c in children)
                _child(c.name, iconFor(c.icon), () => _editChild(book, c)),
              _child('子分類', Glyph.add, () => _addChild(book), add: true),
            ]),
          ],
          // One level only: a category with its own subcategories stays on
          // top.
          if (ledger != null && parents.isNotEmpty && children.isEmpty) ...[
            const SizedBox(height: 10),
            ColorCard(
              color: Hue.faint,
              amount: 0.18,
              radius: 16,
              onTap: () => _pickParent(ledger, parents),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Text(
                    '放在哪個分類下',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    '${_parent ?? '不放'} ›',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Hue.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              if (book != null) ...[
                Expanded(child: PanelButton('合併', onTap: () => _merge(book))),
                const SizedBox(width: 8),
                Expanded(
                  child: PanelButton(
                    widget.initial.archived ? '恢復' : '封存',
                    onTap: () => _archive(book),
                  ),
                ),
                const SizedBox(width: 8),
              ] else ...[
                Expanded(
                  child: PanelButton(
                    '取消',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 2,
                child: PanelButton('儲存', color: Hue.accent, onTap: _save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
