part of 'main.dart';

String _tagLabel(TagCatalog catalog, Tag tag) {
  final name = tag.name;
  if (tag.replacementId != null) {
    return '$name（已合併至 ${catalog.resolve(tag.id).name}）';
  }
  return '$name${tag.archived ? '（已封存）' : ''}';
}

class _TagScreen extends StatefulWidget {
  const _TagScreen({
    required this.engine,
    required this.catalog,
    required this.onDone,
  });
  final PreviewEngine engine;
  final TagCatalog catalog;
  final Future<void> Function() onDone;
  @override
  State<_TagScreen> createState() => _TagScreenState();
}

class _TagScreenState extends State<_TagScreen> {
  late TagCatalog _catalog = widget.catalog;
  final _name = TextEditingController();
  String _editAction = 'rename', _target = '';
  Tag? _editing;
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
      final catalog = await widget.engine.tags();
      if (!mounted || !widget.engine.isUnlocked) return;
      setState(() {
        _catalog = catalog;
        _editing = null;
        _editAction = 'rename';
        _target = '';
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
    final target = _target.isEmpty
        ? null
        : _catalog.get(PublicId.parse(_target));
    final op = _operationFor(
      'save|$_editAction|${editing?.id}|${editing?.version}|${_name.text}|${target?.id}|${target?.version}',
    );
    if (editing != null && _editAction == 'merge') {
      if (target == null) {
        throw const TagException(TagError.invalidInput);
      }
      await widget.engine.mergeTag(op, editing, target);
    } else if (editing != null) {
      await widget.engine.renameTag(op, editing, _name.text);
    } else {
      await widget.engine.createTag(op, _newId!, _name.text);
    }
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('管理標籤', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      const Text('標籤不會改變帳戶金額。封存後保留舊交易，新交易不再列出。'),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_message!, key: const Key('tag-message')),
        ),
      const SizedBox(height: 16),
      if (_editing == null || _editAction == 'rename')
        TextField(
          controller: _name,
          enabled: !_busy,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: _editing == null ? '標籤名稱' : '新的標籤名稱',
          ),
        ),
      if (_editing != null && _editAction == 'merge') ...[
        Text('將「${_editing!.name}」合併至另一標籤'),
        const SizedBox(height: 12),
        const Text('合併後，來源標籤不再提供新交易選用。舊交易保留原始引用並顯示合併去向；此操作沒有直接還原合併的按鈕，請確認目標。'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('merge-${_editing!.id}'),
          initialValue: _target,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '合併目標'),
          items: [
            const DropdownMenuItem(value: '', child: Text('請選擇目標標籤')),
            for (final c in _catalog.tags.where(
              (c) => c.id != _editing!.id && !c.archived,
            ))
              DropdownMenuItem(
                value: c.id.value,
                child: Text(
                  _tagLabel(_catalog, c),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() => _target = value ?? ''),
        ),
      ],
      const SizedBox(height: 12),
      FilledButton(
        onPressed:
            _busy ||
                (_editing != null && _editAction == 'merge' && _target.isEmpty)
            ? null
            : _save,
        child: Text(
          _editing == null
              ? '新增標籤'
              : switch (_editAction) {
                  'merge' => '確認合併並保留歷史',
                  _ => '儲存名稱',
                },
        ),
      ),
      if (_editing != null)
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _editing = null;
                  _editAction = 'rename';
                  _target = '';
                  _name.clear();
                  _signature = null;
                }),
          child: const Text('取消編輯'),
        ),
      const Divider(),
      if (_catalog.tags.isEmpty) const Text('尚無標籤；也可以不選標籤記帳。'),
      for (final c in _catalog.tags)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_tagLabel(_catalog, c)),

          trailing: c.replacementId != null
              ? null
              : PopupMenuButton<String>(
                  tooltip: '操作 ${c.name}',
                  enabled: !_busy,
                  onSelected: (action) {
                    if (action != 'archive') {
                      setState(() {
                        _editing = c;
                        _editAction = action;
                        _target = '';
                        _name.text = c.name;
                        _signature = null;
                      });
                    } else {
                      _perform(
                        () => widget.engine.archiveTag(
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
                    const PopupMenuItem(value: 'merge', child: Text('合併至…')),
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
