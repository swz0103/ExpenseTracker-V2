import 'package:flutter/material.dart';

import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import '../preferences.dart';
import 'nav.dart';

/// 開始使用: the three things that make the app useful from day one, each
/// ticked off as it is done; put away with 不再顯示 or once all are done.
class GettingStarted extends StatelessWidget {
  const GettingStarted({
    super.key,
    required this.ledger,
    required this.preferences,
    required this.nav,
  });

  final Ledger ledger;
  final Preferences preferences;
  final Nav nav;

  Future<void> _showWidget(BuildContext context) async {
    preferences.update(widgetShown: true);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Hue.panel,
        title: const Text('放上桌面小工具'),
        content: const Text(
          '1. 長按手機桌面的空白處\n'
          '2. 點「小工具」\n'
          '3. 找到「記帳本」，把「記一筆」拖到桌面\n\n'
          '之後點小工具上的「記支出」或「記收入」，就會直接打開記一筆。'
          '長按 App 圖示也有同樣的捷徑。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) {
        final steps = [
          (
            '記下第一筆',
            '點下方的「＋」，或在這裡開始',
            ledger.entries.isNotEmpty,
            () => nav.compose(),
          ),
          (
            '打開到期提醒',
            '扣款、卡費當天會通知你',
            preferences.dueAlerts,
            () => nav.open(Pages.settings),
          ),
          (
            '放上桌面小工具',
            '不用打開 App 就能記帳',
            preferences.widgetShown,
            () => _showWidget(context),
          ),
        ];
        final left = steps.where((s) => !s.$3).length;
        if (preferences.started || left == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SoftPanel(
            color: Hue.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          '開始使用 · 還有 $left 步',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => preferences.update(started: true),
                      style: TextButton.styleFrom(foregroundColor: Hue.muted),
                      child: const Text('不再顯示'),
                    ),
                  ],
                ),
                for (final (title, detail, done, onTap) in steps)
                  MergeSemantics(
                    child: InkWell(
                      onTap: done ? null : onTap,
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 52),
                        child: Row(
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: done ? Hue.positive : null,
                                border: done
                                    ? null
                                    : Border.all(color: Hue.muted, width: 1.5),
                              ),
                              alignment: Alignment.center,
                              child: done
                                  ? const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: Hue.onAccent,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                      color: done ? Hue.muted : Hue.ink,
                                      decoration: done
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  Text(
                                    done ? '完成' : detail,
                                    style: mutedSmall,
                                  ),
                                ],
                              ),
                            ),
                            if (!done)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: GlyphIcon(
                                  Glyph.next,
                                  size: 16,
                                  color: Hue.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
