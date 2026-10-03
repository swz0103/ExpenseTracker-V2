import 'package:flutter/material.dart';
import 'package:ledger/ledger.dart';

import '../format.dart';
import '../problems.dart';
import '../session.dart';

/// This month's income and expense, then the latest entries. Transfers and
/// opening balances move money but are not income or spending.
class MonthScreen extends StatelessWidget {
  const MonthScreen({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final today = session.today;
    final total = session.monthTotal(today.year, today.month);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${today.year} 年 ${today.month} 月', style: text.titleLarge),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _Figure('收入', formatMoney(total.income))),
            Expanded(child: _Figure('支出', formatMoney(total.expense))),
          ],
        ),
        const SizedBox(height: 24),
        Text('最近紀錄', style: text.titleMedium),
        for (final posting in session.recent)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_describe(posting)),
            subtitle: Text(formatDate(posting.date)),
            trailing: Text(formatMoney(posting.legs.first.amount)),
            onLongPress: posting.kind == PostingKind.reversal
                ? null
                : () => _reverse(context, posting),
          ),
      ],
    );
  }

  String _describe(Posting posting) {
    final account = session.accountOf(posting.legs.first.account.id);
    final name = account?.name ?? '';
    return switch (posting.kind) {
      PostingKind.income => '收入 · $name',
      PostingKind.expense => '支出 · $name',
      PostingKind.transfer => '轉帳 · $name',
      PostingKind.opening => '期初餘額 · $name',
      PostingKind.reversal => '沖銷 · $name',
      _ => name,
    };
  }

  Future<void> _reverse(BuildContext context, Posting posting) async {
    try {
      await session.reverse(posting);
    } on Object catch (error) {
      if (context.mounted) showProblem(context, error);
    }
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelLarge),
        Text(value, style: text.headlineSmall),
      ],
    );
  }
}
