part of 'main.dart';

extension _ReversalEntry on _PreviewHomeState {
  Future<void> _startReversal(PublicId original) => _perform(() async {
    await _refresh();
    if (_entryDraft != null || _draftUnreadable) throw DraftNeedsResolution();
    final source = await _engine!.reversalSource(original);
    if (!mounted || !_engine!.isUnlocked) return;
    _edit(_Page.posting);
    _changeSplit(() {
      _reversal = source;
      _income = false;
      _accountId = null;
    });
    _queueDraft();
  });
  Future<void> _resumeReversal(EntryDraft saved) async {
    final source = saved.submission == null
        ? await _engine!.reversalSource(saved.fields.reversalOf!)
        : EntrySubmission(
            saved.submission!.posting.reversedPosting!,
            tags: saved.submission!.tags,
            merchant: saved.submission!.merchant,
          );
    if (!mounted || !_engine!.isUnlocked) return;
    _edit(_Page.posting);
    _changeSplit(() {
      _reversal = source;
      _entryDraft = saved;
      _income = false;
      _accountId = null;
      _date.text = saved.fields.date;
      _reversalReason.text = saved.fields.reversalReason;
    });
  }

  List<Widget> _reversalInputs() {
    final p = _reversal!.posting;
    return [
      Text('撤銷交易', style: Theme.of(context).textTheme.headlineSmall),
      Text('原交易：${p.date} · ${_kindLabel(p.kind)}'),
      const Text('保留原交易，新增完整反向紀錄。以下為各帳戶的變動，包含原手續費。'),
      for (var i = 0; i < p.legs.length; i++)
        FinancialSummary(
          title:
              '${_accountName(p.legs[i].account.id)}${p.legs[i].role == LegRole.fee ? ' · 退回手續費' : ''}',
          subtitle: '',
          money: -p.legs[i].amount,
          privacy: _privacy,
          kind: MoneyKind.transaction,
          moneyKey: ValueKey('reversal-impact-$i'),
        ),
      _dateField(),
      _field('撤銷原因（選填）', _reversalReason, length: 256),
    ];
  }

  Future<bool> _confirmReversal() async {
    final epoch = _viewEpoch;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認撤銷這筆交易？'),
        content: const Text('將依畫面所列金額新增反向紀錄，原交易與撤銷原因都會保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回檢查'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認撤銷'),
          ),
        ],
      ),
    );
    return yes == true && mounted && epoch == _viewEpoch && _engine!.isUnlocked;
  }
}

Widget _reversalSummary(
  LedgerEntry e,
  String Function(PublicId?) account,
  PrivacyMode privacy,
) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    FinancialSummary(
      title: '撤銷 · ${account(e.accountId)}',
      subtitle: '交易日期：${e.date}',
      money: e.fee == null ? e.amount : e.amount - e.fee!,
      privacy: privacy,
      kind: MoneyKind.transaction,
      moneyKey: ValueKey('reversal-money-${e.id}'),
    ),
    if (e.received != null)
      FinancialSummary(
        title: '撤銷 · ${account(e.destinationId)}',
        subtitle: '',
        money: e.received!,
        privacy: privacy,
        kind: MoneyKind.transaction,
        moneyKey: ValueKey('reversal-destination-${e.id}'),
      ),
    if (e.fee != null && e.fee!.minorUnits != BigInt.zero)
      FinancialSummary(
        title: '其中：退回原手續費',
        subtitle: '',
        money: -e.fee!,
        privacy: privacy,
        kind: MoneyKind.transaction,
        moneyKey: ValueKey('reversal-fee-${e.id}'),
      ),
    if (e.reversalReason?.isNotEmpty ?? false) Text('原因：${e.reversalReason}'),
  ],
);
