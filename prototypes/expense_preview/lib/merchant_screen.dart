part of 'main.dart';

String _merchantLabel(MerchantCatalog catalog, Merchant merchant) {
  final name = merchant.name;
  if (merchant.replacementId != null) {
    return '$name（已合併至 ${catalog.resolve(merchant.id).name}）';
  }
  return '$name${merchant.archived ? '（已封存）' : ''}';
}

class _MerchantScreen extends StatefulWidget {
  const _MerchantScreen({
    required this.engine,
    required this.catalog,
    required this.onDone,
  });
  final PreviewEngine engine;
  final MerchantCatalog catalog;
  final Future<void> Function() onDone;
  @override
  State<_MerchantScreen> createState() => _MerchantScreenState();
}

class _MerchantScreenState extends State<_MerchantScreen> {
  late MerchantCatalog _catalog = widget.catalog;
  final _name = TextEditingController();
  String _editAction = 'rename', _target = '';
  Merchant? _editing;
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
      final catalog = await widget.engine.merchants();
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
        throw const MerchantException(MerchantError.invalidInput);
      }
      await widget.engine.mergeMerchant(op, editing, target);
    } else if (editing != null && _editAction == 'alias-add') {
      await widget.engine.changeMerchantAlias(
        op,
        editing,
        _name.text,
        remove: false,
      );
    } else if (editing != null) {
      await widget.engine.renameMerchant(op, editing, _name.text);
    } else {
      await widget.engine.createMerchant(op, _newId!, _name.text);
    }
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('管理商家', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      const Text('商家不會改變帳戶金額。封存後保留舊交易，新交易不再列出。'),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_message!, key: const Key('merchant-message')),
        ),
      const SizedBox(height: 16),
      if (_editing == null || _editAction != 'merge')
        TextField(
          controller: _name,
          enabled: !_busy,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: _editing == null
                ? '商家名稱'
                : _editAction == 'alias-add'
                ? '新增別名'
                : '新的商家名稱',
          ),
        ),
      if (_editing != null && _editAction == 'alias-add') ...[
        const Text('別名只用來找候選商家；同名不會自動合併。每個商家最多 16 個。'),
        Wrap(
          spacing: 8,
          children: [
            for (final alias in _editing!.aliases)
              InputChip(
                label: Text(alias),
                onDeleted: _busy
                    ? null
                    : () => _perform(
                        () => widget.engine.changeMerchantAlias(
                          _operationFor(
                            'remove|${_editing!.id}|${_editing!.version}|$alias',
                          ),
                          _editing!,
                          alias,
                          remove: true,
                        ),
                      ),
              ),
          ],
        ),
      ],
      if (_editing != null && _editAction == 'merge') ...[
        Text('將「${_editing!.name}」合併至另一商家'),
        const SizedBox(height: 12),
        const Text('合併後，來源商家不再提供新交易選用。舊交易保留原始引用並顯示合併去向；此操作沒有直接還原合併的按鈕，請確認目標。'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('merge-${_editing!.id}'),
          initialValue: _target,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '合併目標'),
          items: [
            const DropdownMenuItem(value: '', child: Text('請選擇目標商家')),
            for (final c in _catalog.merchants.where(
              (c) => c.id != _editing!.id && !c.archived,
            ))
              DropdownMenuItem(
                value: c.id.value,
                child: Text(
                  _merchantLabel(_catalog, c),
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
              ? '新增商家'
              : switch (_editAction) {
                  'merge' => '確認合併並保留歷史',
                  'alias-add' => '儲存別名',
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
      if (_catalog.merchants.isEmpty) const Text('尚無商家；也可以不選商家記帳。'),
      for (final c in _catalog.merchants)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_merchantLabel(_catalog, c)),
          subtitle: c.aliases.isEmpty
              ? null
              : Text('別名：${c.aliases.join('、')}'),

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
                        _name.text = action == 'alias-add' ? '' : c.name;
                        _signature = null;
                      });
                    } else {
                      _perform(
                        () => widget.engine.archiveMerchant(
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
                    const PopupMenuItem(
                      value: 'alias-add',
                      child: Text('管理別名'),
                    ),
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

class _MerchantPicker extends StatefulWidget {
  const _MerchantPicker({
    super.key,
    required this.catalog,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });
  final MerchantCatalog catalog;
  final String selected;
  final bool enabled;
  final ValueChanged<String> onChanged;
  @override
  State<_MerchantPicker> createState() => _MerchantPickerState();
}

class _MerchantPickerState extends State<_MerchantPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    List<Merchant> candidates;
    try {
      candidates = query.trim().isEmpty
          ? widget.catalog.merchants.where((m) => !m.archived).toList()
          : widget.catalog.candidates(query);
    } on MerchantException {
      candidates = [];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          enabled: widget.enabled,
          maxLength: 100,
          decoration: const InputDecoration(labelText: '商家名稱或別名（選填）'),
          onChanged: (value) {
            widget.onChanged('');
            setState(() => query = value);
          },
        ),
        if (query.trim().isNotEmpty)
          Text(
            candidates.isEmpty
                ? '沒有符合的商家；可返回帳本新增。'
                : '找到 ${candidates.length} 個候選，請確認選擇。',
          ),
        DropdownButtonFormField<String>(
          key: ValueKey('merchant-choice-$query'),
          initialValue: widget.selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '商家'),
          items: [
            const DropdownMenuItem(value: '', child: Text('未指定商家')),
            for (final m in candidates)
              DropdownMenuItem(
                value: m.id.value,
                child: Text(m.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: widget.enabled
              ? (value) => widget.onChanged(value ?? '')
              : null,
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
