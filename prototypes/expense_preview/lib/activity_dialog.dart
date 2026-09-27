part of 'main.dart';

extension _EntryActivity on _PreviewHomeState {
  Future<void> _showActivity(PublicId selected) => _perform(() async {
    final engine = _engine!;
    if (!engine.isUnlocked) throw PreviewLocked();
    await showDialog<void>(
      context: context,
      builder: (_) => _ActivityDialog(
        engine: engine,
        selected: selected,
        privacy: _privacy,
        accounts: {for (final a in _accounts) a.account.id: a.account.name},
      ),
    );
  });
}

class _ActivityDialog extends StatefulWidget {
  const _ActivityDialog({
    required this.engine,
    required this.selected,
    required this.privacy,
    required this.accounts,
  });
  final PreviewEngine engine;
  final PublicId selected;
  final PrivacyMode privacy;
  final Map<PublicId, String> accounts;
  @override
  State<_ActivityDialog> createState() => _ActivityDialogState();
}

class _ActivityDialogState extends State<_ActivityDialog> {
  final _rows = <LedgerActivity>[];
  bool _loading = false, _more = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading || !_more) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.engine.activity(
        widget.selected,
        before: _rows.lastOrNull?.cursor,
      );
      if (!mounted || !widget.engine.isUnlocked) return;
      setState(() {
        _rows.addAll(rows);
        _more = rows.length == 30;
      });
    } catch (_) {
      if (mounted && widget.engine.isUnlocked) {
        setState(() => _error = '無法讀取活動，請重試；帳本未變更。');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _account(PublicId? id) => widget.accounts[id] ?? '帳戶';
  String _recorded(UtcInstant instant) {
    final t = instant.value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Widget _item(LedgerActivity row) {
    final e = row.entry;
    return Padding(
      key: ValueKey('activity-row-${e.id}'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('記錄時間：${_recorded(row.recordedAt)}（本機時區）'),
          if (e.id == widget.selected) const Text('目前選取的交易'),
          if (e.kind == PostingKind.transfer)
            TransferSummary(
              entry: e,
              source: _account(e.accountId),
              destination: _account(e.destinationId),
              privacy: widget.privacy,
            )
          else
            FinancialSummary(
              title: '${_kindLabel(e.kind)} · ${_account(e.accountId)}',
              subtitle: '交易日期：${e.date}',
              money: e.amount,
              privacy: widget.privacy,
              kind: MoneyKind.transaction,
              moneyKey: ValueKey('activity-money-${e.id}'),
            ),
          if (e.refunded != null &&
              e.refunded!.currency != e.amount.currency) ...[
            const Text('原幣沖回'),
            MoneyView(
              money: e.refunded!,
              privacy: widget.privacy,
              kind: MoneyKind.transaction,
            ),
          ],
          const Divider(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 600,
      height: MediaQuery.sizeOf(context).height * .8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '交易活動',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '關閉活動',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Text('由新到舊，包含原交易及相關退款。'),
            Expanded(
              child: ListView(
                key: const Key('activity-list'),
                children: [
                  for (final row in _rows) _item(row),
                  if (_error != null) Text(_error!),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_more)
                    TextButton(
                      onPressed: _load,
                      child: Text(_error == null ? '載入較早活動' : '重試讀取活動'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
