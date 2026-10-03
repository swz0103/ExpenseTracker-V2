import 'package:accounts/accounts.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../problems.dart';
import '../session.dart';

/// Records one income or expense. The amount is checked exactly as typed;
/// nothing is rounded.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.session, required this.onSaved});

  final AppSession session;
  final VoidCallback onSaved;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final _amount = TextEditingController();
  var _flow = CashFlow.expense;
  Account? _account;
  var _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = widget.session.activeAccounts;
    final selected = accounts.where((a) => a.id == _account?.id);
    final account = selected.isEmpty
        ? (accounts.isEmpty ? null : accounts.first)
        : selected.first;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<CashFlow>(
          segments: const [
            ButtonSegment(value: CashFlow.expense, label: Text('支出')),
            ButtonSegment(value: CashFlow.income, label: Text('收入')),
          ],
          selected: {_flow},
          onSelectionChanged: (value) => setState(() => _flow = value.single),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('record-amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: Theme.of(context).textTheme.headlineSmall,
          decoration: const InputDecoration(
            labelText: '金額',
            prefixText: 'NT\$ ',
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<Account>(
          key: ValueKey(account?.id),
          initialValue: account,
          decoration: const InputDecoration(labelText: '帳戶'),
          items: [
            for (final item in accounts)
              DropdownMenuItem(value: item, child: Text(item.name)),
          ],
          onChanged: (value) => setState(() => _account = value),
        ),
        const SizedBox(height: 8),
        Text('日期：${formatDate(widget.session.today)}'),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('record-save'),
          onPressed: _saving || account == null ? null : () => _save(account),
          child: const Text('儲存'),
        ),
      ],
    );
  }

  Future<void> _save(Account account) async {
    setState(() => _saving = true);
    try {
      final session = widget.session;
      final amount = parseAmount(session.twd, _amount.text);
      await session.record(_flow, account, amount, session.today);
      _amount.clear();
      widget.onSaved();
    } on Object catch (error) {
      if (mounted) showProblem(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
