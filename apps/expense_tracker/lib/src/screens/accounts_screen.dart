import 'package:accounts/accounts.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../problems.dart';
import '../session.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accounts = session.accounts;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('淨資產', style: text.labelLarge),
        Text(
          'NT\$ ${formatMoney(session.netWorth)}',
          style: text.headlineMedium,
        ),
        const SizedBox(height: 24),
        for (final account in accounts)
          Card(
            child: ListTile(
              leading: Icon(_icon(account.kind)),
              title: Text(account.name),
              subtitle: Text(_label(account)),
              trailing: Text(
                formatMoney(session.balanceOf(account)),
                style: text.titleMedium,
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _addAccount(context),
          icon: const Icon(Icons.add),
          label: const Text('新增帳戶'),
        ),
      ],
    );
  }

  Future<void> _addAccount(BuildContext context) async {
    final name = TextEditingController();
    final opening = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增帳戶'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('account-name'),
              controller: name,
              decoration: const InputDecoration(labelText: '名稱'),
            ),
            TextField(
              key: const Key('account-opening'),
              controller: opening,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '期初餘額（可空白）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('建立'),
          ),
        ],
      ),
    );
    if (saved != true || !context.mounted) return;
    try {
      final amount = opening.text.trim().isEmpty
          ? null
          : parseAmount(session.twd, opening.text);
      await session.openAccount(name.text, AccountKind.bank, amount);
    } on Object catch (error) {
      if (context.mounted) showProblem(context, error);
    }
  }
}

IconData _icon(AccountKind kind) => switch (kind) {
  AccountKind.cash => Icons.payments_outlined,
  AccountKind.bank => Icons.account_balance_outlined,
  AccountKind.creditCard => Icons.credit_card,
};

String _label(Account account) => switch (account.state) {
  AccountState.active => account.currency.code,
  AccountState.archived => '${account.currency.code} · 已封存',
  AccountState.closed => '${account.currency.code} · 已結清',
};
