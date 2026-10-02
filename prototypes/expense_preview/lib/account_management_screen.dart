part of 'main.dart';

class _AccountManagementScreen extends StatefulWidget {
  const _AccountManagementScreen({required this.engine, required this.privacy});

  final PreviewEngine engine;
  final PrivacyMode privacy;

  @override
  State<_AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<_AccountManagementScreen> {
  List<AccountSummary> _rows = const [];
  bool _busy = true;
  String? _message;
  int _request = 0;

  OperationKey _operation() =>
      OperationKey(widget.engine.workspace, OperationId(PublicId.generate()));

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    if (mounted) setState(() => _busy = true);
    try {
      final rows = await widget.engine.accounts();
      if (!mounted || request != _request || !widget.engine.isUnlocked) return;
      setState(() {
        _rows = rows;
        _message = null;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _message = '無法讀取帳戶；帳本未變更。');
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() command, String success) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await command();
      final rows = await widget.engine.accounts();
      if (!mounted || !widget.engine.isUnlocked) return;
      setState(() {
        _rows = rows;
        _message = success;
      });
    } on AccountException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        AccountError.versionConflict => '帳戶已在其他操作中變更，已重新載入；請再確認。',
        AccountError.nonZeroBalance => '餘額必須為零才能關閉帳戶。',
        AccountError.unsettledItems => '仍有待入帳或未結項目，不能關閉帳戶。',
        AccountError.invalidDate => '關閉日不可早於開戶日或接手帳戶的開戶日。',
        AccountError.unavailable => '目前帳戶狀態不允許這個操作。',
        _ => '帳戶資料無效，操作未套用。',
      };
      var rows = _rows;
      try {
        rows = await widget.engine.accounts();
      } catch (_) {
        // Keep the last complete list while reporting the command failure.
      }
      if (mounted) {
        setState(() {
          _rows = rows;
          _message = message;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = '帳戶可能已變更；操作未套用，請重新整理。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(Account account) async {
    var proposed = account.name;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('帳戶改名'),
        content: TextFormField(
          initialValue: proposed,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: '新名稱'),
          onChanged: (value) => proposed = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, proposed),
            child: const Text('儲存名稱'),
          ),
        ],
      ),
    );
    if (name == null) return;
    await _run(
      () => widget.engine.renameAccount(_operation(), account, name),
      '帳戶名稱已更新。',
    );
  }

  Future<void> _archive(Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('封存帳戶？'),
        content: const Text('封存後不能新增交易，但不會刪除歷史，也不會釋放 32 個帳戶上限。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認封存'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => widget.engine.archiveAccount(_operation(), account),
      '帳戶已封存；歷史完整保留。',
    );
  }

  Future<void> _close(Account account) async {
    final now = DateTime.now();
    var dateText = BusinessDate(now.year, now.month, now.day).toString();
    var reasonText = '';
    PublicId? successorId;
    final successors = _rows
        .map((row) => row.account)
        .where(
          (candidate) =>
              candidate.id != account.id &&
              candidate.state == AccountState.active,
        )
        .toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('關閉帳戶'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('只有餘額為零且沒有待入帳項目時才會成功。歷史與關閉原因都會保留。'),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: dateText,
                  decoration: const InputDecoration(
                    labelText: '關閉日 YYYY-MM-DD',
                  ),
                  onChanged: (value) => dateText = value,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: reasonText,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: '關閉原因'),
                  onChanged: (value) => reasonText = value,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PublicId?>(
                  initialValue: successorId,
                  decoration: const InputDecoration(labelText: '接手帳戶（選填）'),
                  items: [
                    const DropdownMenuItem<PublicId?>(
                      value: null,
                      child: Text('不指定'),
                    ),
                    for (final candidate in successors)
                      DropdownMenuItem<PublicId?>(
                        value: candidate.id,
                        child: Text(
                          '${candidate.name} · ${candidate.currency.code}',
                        ),
                      ),
                  ],
                  onChanged: (value) => update(() => successorId = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('確認關閉'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => widget.engine.closeAccount(
        _operation(),
        account,
        date: BusinessDate.parse(dateText.trim()),
        reason: reasonText,
        successorId: successorId,
      ),
      '帳戶已關閉；歷史與關閉資訊完整保留。',
    );
  }

  Future<void> _action(Account account, String action) async {
    switch (action) {
      case 'rename':
        return _rename(account);
      case 'summary':
        return _run(
          () => widget.engine.setAccountNetWorthInclusion(
            _operation(),
            account,
            !account.includeInNetWorth,
          ),
          account.includeInNetWorth ? '已從資產摘要排除。' : '已納入資產摘要。',
        );
      case 'archive':
        return _archive(account);
      case 'reactivate':
        return _run(
          () => widget.engine.reactivateAccount(_operation(), account),
          '帳戶已重新啟用。',
        );
      case 'close':
        return _close(account);
    }
  }

  String _state(Account account) => switch (account.state) {
    AccountState.active => '使用中',
    AccountState.archived => '已封存',
    AccountState.closed => '已關閉',
  };

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('account-management-screen'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('帳戶管理', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('改名、摘要設定與狀態變更都會保留版本；不提供幣別或開戶日改寫。'),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null) ...[
        const SizedBox(height: 8),
        Text(_message!, key: const ValueKey('account-management-message')),
      ],
      const SizedBox(height: 12),
      for (final row in _rows)
        Card(
          key: ValueKey('managed-account-${row.account.id.value}'),
          child: ListTile(
            title: Text(row.account.name),
            subtitle: Text(
              '${row.account.currency.code} · ${_state(row.account)} · '
              '${row.account.includeInNetWorth ? '納入摘要' : '不納入摘要'}'
              '${row.account.closedOn == null ? '' : '\n關閉 ${row.account.closedOn}：${row.account.closingReason}'}',
            ),
            isThreeLine: row.account.closedOn != null,
            trailing: PopupMenuButton<String>(
              enabled: !_busy,
              tooltip: '管理 ${row.account.name}',
              onSelected: (action) => _action(row.account, action),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('改名')),
                PopupMenuItem(
                  value: 'summary',
                  child: Text(
                    row.account.includeInNetWorth ? '從資產摘要排除' : '納入資產摘要',
                  ),
                ),
                if (row.account.state == AccountState.active)
                  const PopupMenuItem(value: 'archive', child: Text('封存')),
                if (row.account.state != AccountState.active)
                  const PopupMenuItem(value: 'reactivate', child: Text('重新啟用')),
                if (row.account.state != AccountState.closed)
                  const PopupMenuItem(value: 'close', child: Text('關閉帳戶')),
              ],
            ),
            leading: Icon(switch (row.account.kind) {
              AccountKind.cash => Icons.payments_outlined,
              AccountKind.bank => Icons.account_balance_outlined,
              AccountKind.creditCard => Icons.credit_card_outlined,
            }),
          ),
        ),
      if (!_busy && _rows.isEmpty) const Text('目前沒有帳戶。'),
    ],
  );
}
