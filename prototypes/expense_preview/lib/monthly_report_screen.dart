part of 'main.dart';

class _MonthlyReportScreen extends StatefulWidget {
  const _MonthlyReportScreen({
    required this.engine,
    required this.initial,
    required this.privacy,
    required this.onActivity,
  });

  final PreviewEngine engine;
  final MonthlyReport initial;
  final PrivacyMode privacy;
  final void Function(PublicId) onActivity;

  @override
  State<_MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<_MonthlyReportScreen> {
  late MonthlyReport _report = widget.initial;
  bool _busy = false;
  String? _errorText;
  int _visible = 30, _request = 0;

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  ReportMonth? _adjacent(int offset) {
    final index =
        (_report.month.year - 1) * 12 + _report.month.month - 1 + offset;
    if (index < 0 || index >= 9999 * 12) return null;
    return ReportMonth(index ~/ 12 + 1, index % 12 + 1);
  }

  Future<void> _change(int offset) async {
    if (_busy || !widget.engine.isUnlocked) return;
    final month = _adjacent(offset);
    if (month == null) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final next = await widget.engine.monthlyReport(month);
      if (!mounted || request != _request || !widget.engine.isUnlocked) return;
      setState(() {
        _report = next;
        _visible = 30;
      });
    } on MoneyException {
      if (mounted && request == _request && widget.engine.isUnlocked) {
        setState(() => _errorText = '該月份合計超過可表示範圍，已保留目前報表。');
      }
    } catch (_) {
      if (mounted && request == _request && widget.engine.isUnlocked) {
        setState(() => _errorText = '讀取月份失敗；帳本沒有被修改。');
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final facts = [for (final summary in _report.currencies) ...summary.facts]
      ..sort((a, b) {
        final date = b.date.compareTo(a.date);
        return date != 0 ? date : b.id.value.compareTo(a.id.value);
      });
    final enabled = !_busy && widget.engine.isUnlocked;
    return Column(
      key: const Key('monthly-report-screen'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('月收支', style: Theme.of(context).textTheme.headlineSmall),
        const Text('逐幣別呈現已入帳的收入與淨支出；轉帳本金、期初不列入，手續費列支出。'),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: enabled && _adjacent(-1) != null
                  ? () => _change(-1)
                  : null,
              child: const Text('上個月'),
            ),
            Text(_report.month.toString()),
            TextButton(
              onPressed: enabled && _adjacent(1) != null
                  ? () => _change(1)
                  : null,
              child: const Text('下個月'),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_errorText != null)
          Semantics(liveRegion: true, child: Text(_errorText!)),
        if (_report.currencies.isEmpty) const Text('這個月沒有影響收入或支出的交易。'),
        for (final summary in _report.currencies)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  summary.currency.code,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                FinancialSummary(
                  title: '收入',
                  subtitle: '含收入撤銷',
                  money: summary.income,
                  privacy: widget.privacy,
                  kind: MoneyKind.transaction,
                  moneyKey: ValueKey('report-income-${summary.currency.code}'),
                ),
                FinancialSummary(
                  title: '淨支出',
                  subtitle: '退款與撤銷在當月沖減',
                  money: summary.expense,
                  privacy: widget.privacy,
                  kind: MoneyKind.transaction,
                  moneyKey: ValueKey('report-expense-${summary.currency.code}'),
                ),
                FinancialSummary(
                  title: '收支差額',
                  subtitle: '僅此幣別，不含估值',
                  money: summary.net,
                  privacy: widget.privacy,
                  kind: MoneyKind.transaction,
                  moneyKey: ValueKey('report-net-${summary.currency.code}'),
                ),
              ],
            ),
          ),
        const Divider(),
        Text('明細', style: Theme.of(context).textTheme.titleLarge),
        for (final fact in facts.take(_visible))
          Padding(
            key: ValueKey('report-fact-${fact.id.value}'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${_kindLabel(fact.kind)} · ${fact.date}'),
                if (fact.income.minorUnits != BigInt.zero)
                  FinancialSummary(
                    title: '收入影響',
                    subtitle: fact.currency.code,
                    money: fact.income,
                    privacy: widget.privacy,
                    kind: MoneyKind.transaction,
                    moneyKey: ValueKey('report-fact-income-${fact.id.value}'),
                  ),
                if (fact.expense.minorUnits != BigInt.zero)
                  FinancialSummary(
                    title: '支出影響',
                    subtitle: fact.currency.code,
                    money: fact.expense,
                    privacy: widget.privacy,
                    kind: MoneyKind.transaction,
                    moneyKey: ValueKey('report-fact-expense-${fact.id.value}'),
                  ),
                TextButton(
                  onPressed: enabled ? () => widget.onActivity(fact.id) : null,
                  child: const Text('查看活動'),
                ),
              ],
            ),
          ),
        if (facts.length > _visible)
          TextButton(
            onPressed: enabled ? () => setState(() => _visible += 30) : null,
            child: const Text('載入更多報表明細'),
          ),
      ],
    );
  }
}
