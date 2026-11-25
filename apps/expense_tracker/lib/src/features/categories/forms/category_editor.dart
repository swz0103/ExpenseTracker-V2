import 'package:flutter/material.dart';

import '../../../core/design_system/glyphs.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/formatting/words.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/messages/done_messages.dart';
import '../../../core/widgets/pickers.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
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
    EditGuard.close(context, made);
  }

  /// Archives the category or brings it back, told with 復原 (D82).
  void _archive(Ledger ledger) {
    final c = widget.initial;
    final undo = ledger.categoryCommands.setArchived(
      c.name,
      archived: !c.archived,
    );
    if (undo != null) {
      showUndo(
        context,
        c.archived ? DoneWords.unarchived(c.name) : DoneWords.archived(c.name),
        undo,
      );
    }
    EditGuard.close(context);
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
        // Not itself, nor one under it (the command refuses those too).
        where: (o) =>
            !isUnder(o.name, c.name, (name) => ledger.category(name).parent),
      ),
    );
    if (into == null || !mounted) return;
    // Told with 復原, not asked first (D82).
    if (ledger.categoryCommands.mergeCategory(c.name, into) case Merged(
      :final undo,
    )) {
      showUndo(context, DoneWords.merged(c.name, into), undo);
    }
    EditGuard.close(context);
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
        const Option('', '不放', Glyph.close, AppColors.muted),
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
    return ListenableBuilder(
      listenable: _name,
      builder: (context, form) =>
          EditGuard(changed: _f.changedFrom(_name.text), child: form!),
      child: _form(ledger, book),
    );
  }

  Widget _form(Ledger? ledger, Ledger? book) {
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
              child: Text(problem, style: dangerText),
            ),
          if (_icons)
            for (final (group, marks) in categoryIconGroups) ...[
              Padding(
                padding: const EdgeInsets.only(top: Space.s3, bottom: Space.s2),
                child: Text(group, style: mutedSmall),
              ),
              // 48 dp to tap each, 50 apart as the 44 dp squares were.
              Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  for (final (key, name) in marks)
                    IconChoiceButton(
                      icon: iconFor(key),
                      label: '圖示：$name',
                      color: _color,
                      selected: key == _f.icon,
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
                        color: AppColors.white,
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
                  // 48 dp to tap, its words where they were.
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    constraints: const BoxConstraints(minHeight: 48),
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
        color: AppColors.muted,
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

  /// 合併 and 封存 for a kept category, over 取消 and 儲存 (D83).
  Widget _actions(Ledger? book) {
    final save = Row(
      children: [
        const Expanded(child: CancelButton()),
        const SizedBox(width: Space.s2),
        Expanded(
          flex: 2,
          child: PanelButton(Words.save, color: AppColors.accent, onTap: _save),
        ),
      ],
    );
    if (book == null) return save;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: PanelButton('合併', onTap: () => _merge(book))),
            const SizedBox(width: Space.s2),
            Expanded(
              child: PanelButton(
                widget.initial.archived ? Words.unarchive : Words.archive,
                onTap: () => _archive(book),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s2),
        save,
      ],
    );
  }
}
