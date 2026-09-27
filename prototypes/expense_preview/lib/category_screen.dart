part of 'main.dart';

String _categoryLabel(CategoryCatalog catalog, Category category) {
  final parent = category.parentId;
  final name = parent == null
      ? category.name
      : '${catalog.get(parent).name} / ${category.name}';
  return '$name${category.archived ? '（已封存）' : ''}';
}

class _CategoryScreen extends StatefulWidget {
  const _CategoryScreen({
    required this.engine,
    required this.catalog,
    required this.onDone,
  });
  final PreviewEngine engine;
  final CategoryCatalog catalog;
  final Future<void> Function() onDone;
  @override
  State<_CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<_CategoryScreen> {
  late CategoryCatalog _catalog = widget.catalog;
  final _name = TextEditingController();
  CategoryKind _kind = CategoryKind.expense;
  String _parent = '';
  Category? _editing;
  bool _busy = false;
  String? _message, _signature;
  OperationKey? _operation;
  PublicId? _newId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  OperationKey _operationFor(String signature) {
    if (_signature != signature) {
      _signature = signature;
      _operation = OperationKey(
        widget.engine.workspace,
        OperationId(PublicId.generate()),
      );
      _newId = PublicId.generate();
    }
    return _operation!;
  }

  Future<void> _perform(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await work();
      final catalog = await widget.engine.categories();
      if (!mounted || !widget.engine.isUnlocked) return;
      setState(() {
        _catalog = catalog;
        _editing = null;
        _parent = '';
        _name.clear();
        _signature = null;
      });
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _perform(() async {
    final editing = _editing;
    final op = _operationFor(
      'save|${editing?.id}|${editing?.version}|${_name.text}|$_kind|$_parent',
    );
    if (editing != null) {
      await widget.engine.renameCategory(op, editing, _name.text);
    } else {
      await widget.engine.createCategory(
        op,
        _newId!,
        _name.text,
        _kind,
        parentId: _parent.isEmpty ? null : PublicId.parse(_parent),
      );
    }
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('管理分類', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      const Text('分類不會改變帳戶金額。封存後保留舊交易，新交易不再列出。'),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_message!, key: const Key('category-message')),
        ),
      const SizedBox(height: 16),
      TextField(
        controller: _name,
        enabled: !_busy,
        maxLength: 100,
        decoration: InputDecoration(
          labelText: _editing == null ? '分類名稱' : '新的分類名稱',
        ),
      ),
      if (_editing == null) ...[
        const SizedBox(height: 12),
        SegmentedButton<CategoryKind>(
          segments: const [
            ButtonSegment(value: CategoryKind.expense, label: Text('支出分類')),
            ButtonSegment(value: CategoryKind.income, label: Text('收入分類')),
          ],
          selected: {_kind},
          onSelectionChanged: _busy
              ? null
              : (value) => setState(() {
                  _kind = value.single;
                  _parent = '';
                }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('parent-$_kind-$_parent'),
          initialValue: _parent,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '上層分類'),
          items: [
            const DropdownMenuItem(value: '', child: Text('無（第一層）')),
            for (final c in _catalog.categories.where(
              (c) => c.parentId == null && !c.archived && c.kind == _kind,
            ))
              DropdownMenuItem(
                value: c.id.value,
                child: Text(c.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() => _parent = value ?? ''),
        ),
      ],
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_editing == null ? '新增分類' : '儲存名稱'),
      ),
      if (_editing != null)
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _editing = null;
                  _name.clear();
                  _signature = null;
                }),
          child: const Text('取消改名'),
        ),
      const Divider(),
      if (_catalog.categories.isEmpty) const Text('尚無分類；也可以先用「未分類」記帳。'),
      for (final c in _catalog.categories)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_categoryLabel(_catalog, c)),
          subtitle: Text(c.kind == CategoryKind.income ? '收入' : '支出'),
          trailing: c.replacementId != null
              ? null
              : PopupMenuButton<String>(
                  tooltip: '操作 ${c.name}',
                  enabled: !_busy,
                  onSelected: (action) {
                    if (action == 'rename') {
                      setState(() {
                        _editing = c;
                        _name.text = c.name;
                        _signature = null;
                      });
                    } else {
                      _perform(
                        () => widget.engine.archiveCategory(
                          _operationFor(
                            'archive|${c.id}|${c.version}|${!c.archived}',
                          ),
                          c,
                          archived: !c.archived,
                        ),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('改名')),
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(c.archived ? '重新啟用' : '封存'),
                    ),
                  ],
                ),
        ),
      TextButton(
        onPressed: _busy ? null : widget.onDone,
        child: const Text('返回帳本'),
      ),
    ],
  );
}
