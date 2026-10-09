import 'package:flutter/material.dart';

import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import 'dialogs.dart';
import 'entry_tile.dart';

/// An entry's details, with 刪除 on the left and 編輯 on the right.
/// Returns `edit` or `deleted` when one was chosen.
Future<String?> showEntrySheet(
  BuildContext context,
  Ledger ledger,
  Entry entry,
) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Hue.panel,
    showDragHandle: true,
    builder: (context) {
      final (icon, color) = entryMark(ledger, entry);
      final rows = <(String, String)>[
        ('日期', fullDay(entry.date)),
        if (entry.type == EntryType.transfer) ...[
          ('轉出', ledger.account(entry.account).name),
          ('轉入', ledger.account(entry.to ?? '').name),
        ] else ...[
          ('帳戶', ledger.account(entry.account).name),
          if (entry.isInvestment)
            ('標的', '${entry.holding}　${entry.shares} 股')
          else
            ('分類', entry.category),
        ],
        if (entry.note.isNotEmpty) ('備註', entry.note),
      ];
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    'TWD  ',
                    style: TextStyle(fontSize: 12, color: Hue.muted),
                  ),
                  Text(
                    entryAmount(entry),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w500,
                      color: entryColor(entry.type),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(
                          label,
                          style: const TextStyle(color: Hue.muted),
                        ),
                      ),
                      Expanded(child: Text(value)),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final ok = await confirm(
                          context,
                          '刪除這一筆？',
                          '刪除',
                          danger: true,
                        );
                        if (ok && context.mounted) {
                          Navigator.of(context).pop('deleted');
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Hue.ink,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text('刪除'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop('edit'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Hue.positive,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text('編輯'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
