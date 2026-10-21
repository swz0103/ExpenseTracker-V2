import 'package:flutter/material.dart';

import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import '../problems.dart';
import 'entry_tile.dart';

/// Shows the entries deleted in the last 30 days, newest first; tapping
/// one puts it back.
Future<void> showTrash(BuildContext context, Ledger ledger) =>
    showSheet<void>(context, (_) => _TrashSheet(ledger: ledger));

class _TrashSheet extends StatelessWidget {
  const _TrashSheet({required this.ledger});

  final Ledger ledger;

  void _restore(BuildContext context, Trashed trashed) {
    try {
      ledger.restoreTrashed(trashed);
      showNote(context, '已復原「${trashed.entry.title}」');
    } on Object catch (error) {
      showNote(context, describeProblem(error));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ledger,
    builder: (context, _) {
      final trash = ledger.trash;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '最近刪除',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              trash.isEmpty ? '30 天內沒有刪除的紀錄' : '點一筆就放回帳本；刪除後保留 30 天',
              textAlign: TextAlign.center,
              style: mutedSmall,
            ),
            const SizedBox(height: 8),
            for (final t in trash) ...[
              Padding(
                padding: const EdgeInsets.only(left: 14, top: 6),
                child: Text(
                  '${t.on.month}/${t.on.day} 刪除',
                  style: const TextStyle(fontSize: 12.5, color: Hue.muted),
                ),
              ),
              EntryTile(
                ledger: ledger,
                entry: t.entry,
                onTap: () => _restore(context, t),
              ),
            ],
          ],
        ),
      );
    },
  );
}
