part of 'main.dart';

class _AccountDetailsSheet extends StatefulWidget {
  const _AccountDetailsSheet({
    required this.engine,
    required this.summary,
    required this.privacy,
    required this.onActivity,
    required this.allocationLabel,
  });

  final PreviewEngine engine;
  final AccountSummary summary;
  final PrivacyMode privacy;
  final void Function(PublicId) onActivity;
  final String? Function(PublicId) allocationLabel;

  @override
  State<_AccountDetailsSheet> createState() => _AccountDetailsSheetState();
}

class _AccountDetailsSheetState extends State<_AccountDetailsSheet> {
  final _entries = <LedgerEntry>[];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  int _request = 0;

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
    if (_loading || !_hasMore) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.engine.accountEntries(
        widget.summary.account.id,
        before: _entries.lastOrNull,
      );
      if (!mounted || request != _request || !widget.engine.isUnlocked) {
        return;
      }
      if (rows.any(
        (entry) =>
            entry.accountId != widget.summary.account.id &&
            entry.destinationId != widget.summary.account.id,
      )) {
        throw StateError('Account activity query returned an unrelated row');
      }
      final known = _entries.map((entry) => entry.id).toSet();
      if (rows.any((entry) => known.contains(entry.id))) {
        throw StateError('Account activity keyset repeated a row');
      }
      setState(() {
        _entries.addAll(rows);
        _hasMore = rows.length == 30;
      });
    } catch (_) {
      if (mounted && request == _request && widget.engine.isUnlocked) {
        setState(() => _error = '無法讀取帳戶活動，請重試；帳本未變更。');
      }
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.summary;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (_, controller) => ListView(
        key: const ValueKey('account-activity-list'),
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Row(
            children: [
              Icon(switch (row.account.kind) {
                AccountKind.cash => Icons.payments_outlined,
                AccountKind.bank => Icons.account_balance_outlined,
                AccountKind.creditCard => Icons.credit_card_outlined,
              }),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  row.account.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${row.account.currency.code} · ${row.account.includeInNetWorth ? '納入資產摘要' : '不納入資產摘要'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          FinancialSummary(
            title: row.account.kind == AccountKind.creditCard
                ? '目前負債餘額'
                : '目前餘額',
            subtitle: '含期初餘額與所有有效交易',
            money: row.balance,
            privacy: widget.privacy,
            kind: MoneyKind.balance,
            moneyKey: ValueKey('account-detail-money-${row.account.id.value}'),
          ),
          const SizedBox(height: 22),
          Text('帳戶活動', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_entries.isEmpty && _loading)
            const Center(child: CircularProgressIndicator())
          else if (_entries.isEmpty && _error == null)
            const Text('這個帳戶還沒有交易。'),
          for (final entry in _entries)
            ListTile(
              key: ValueKey('account-activity-${entry.id.value}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(_timelineIcon(entry.kind), color: warmAccent),
              title: Text('${_kindLabel(entry.kind)} · ${entry.date}'),
              subtitle: switch (widget.allocationLabel(entry.id)) {
                final label? => Text(label),
                null => null,
              },
              trailing: MoneyView(
                money:
                    entry.destinationId == row.account.id &&
                        entry.received != null
                    ? entry.received!
                    : entry.amount,
                privacy: widget.privacy,
                kind: MoneyKind.transaction,
              ),
              onTap: () => widget.onActivity(entry.id),
            ),
          if (_error != null) ...[
            Text(_error!),
            TextButton(
              onPressed: _loading ? null : _load,
              child: const Text('重試讀取'),
            ),
          ] else if (_loading && _entries.isNotEmpty)
            const Center(child: CircularProgressIndicator())
          else if (_hasMore)
            TextButton(onPressed: _load, child: const Text('載入較早活動')),
        ],
      ),
    );
  }
}
