import 'package:flutter/material.dart';

import '../book.dart';
import '../theme.dart';
import '../ui/kit.dart';

/// Every account with its balance, and net worth on top.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cash = book.accounts.fold(0, (sum, a) => sum + a.balance);
    final worth = cash + book.investValue;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const ScreenHeader(title: '帳戶'),
        Panel(
          color: Palette.wash,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '淨資產（含投資市值）',
                style: text.bodySmall?.copyWith(color: Palette.muted),
              ),
              const SizedBox(height: 6),
              Text(
                dollars(worth),
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final account in book.accounts) ...[
          Panel(
            onTap: () => comingSoon(context, account.name),
            child: Row(
              children: [
                IconTile(accountIcon(account.kind), size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(account.name, style: text.bodyLarge),
                      Text(
                        account.kind,
                        style: text.bodySmall?.copyWith(color: Palette.muted),
                      ),
                    ],
                  ),
                ),
                Text(
                  dollars(account.balance),
                  style: text.titleMedium?.copyWith(
                    color: account.balance < 0 ? Palette.clay : Palette.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        Panel(
          color: Palette.wash,
          onTap: () => comingSoon(context, '新增帳戶'),
          child: Center(
            child: Text(
              '＋ 新增帳戶',
              style: text.titleSmall?.copyWith(color: Palette.clay),
            ),
          ),
        ),
      ],
    );
  }
}
