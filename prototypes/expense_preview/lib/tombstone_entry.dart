part of 'main.dart';

extension _TombstoneEntry on _PreviewHomeState {
  Future<void> _startTombstone(PublicId original) => _perform(() async {
    await _refresh();
    if (_entryDraft != null || _draftUnreadable) throw DraftNeedsResolution();
    final source = await _engine!.reversalSource(original);
    if (!mounted || !_engine!.isUnlocked) return;
    await _confirmTombstone(source.posting);
  });

  Future<void> _resumeTombstone(EntryDraft saved) async {
    final source = saved.tombstoneSubmission == null
        ? (await _engine!.reversalSource(saved.id)).posting
        : saved.tombstoneSubmission!.command.original;
    if (!mounted || !_engine!.isUnlocked) return;
    await _confirmTombstone(source, pending: saved);
  }

  Future<void> _confirmTombstone(Posting source, {EntryDraft? pending}) async {
    final epoch = _viewEpoch;
    final engine = _engine!;
    final reason = TextEditingController(text: pending?.fields.tombstoneReason);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('刪除這筆交易？'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('交易日期：${source.date}'),
                Text(
                  '受影響帳戶：${source.legs.map((l) => _accountName(l.account.id)).join('、')}',
                ),
                MoneyView(
                  money: source.kind == PostingKind.transfer
                      ? -source.legs.first.amount
                      : source.kind == PostingKind.income
                      ? source.reportIncome
                      : source.reportExpense,
                  privacy: _privacy,
                  kind: MoneyKind.transaction,
                ),
                const Text('確認後，原交易不再計入目前餘額；活動歷史仍保留。'),
                TextField(
                  key: const Key('tombstone-reason'),
                  controller: reason,
                  maxLength: 256,
                  readOnly: pending?.isPrepared == true,
                  decoration: const InputDecoration(labelText: '刪除原因（可留空）'),
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
              key: const Key('confirm-tombstone'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('確認刪除'),
            ),
          ],
        ),
      );
      if (confirmed != true ||
          !mounted ||
          epoch != _viewEpoch ||
          !engine.isUnlocked) {
        return;
      }
      if (pending == null) {
        await engine.saveEntryDraft(
          EntryFields(
            income: false,
            amount: '',
            date: '',
            tombstoneOf: source.id,
            tombstoneReason: reason.text.trim(),
          ),
        );
      }
      await engine.submitEntryDraft();
      await _refresh();
    } finally {
      reason.dispose();
    }
  }
}
