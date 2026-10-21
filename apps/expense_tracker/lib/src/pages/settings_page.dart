import 'package:flutter/material.dart';

import '../look/dialogs.dart';
import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import '../perf.dart';
import '../services.dart';
import 'nav.dart';
import 'settings/links_section.dart';
import 'settings/preferences_section.dart';
import 'settings/records_section.dart';
import 'settings/security_section.dart';

/// 設定與資料: preferences, exporting a month or the whole book, the
/// encrypted ledger's backups and keys, and resetting the demo. Each
/// section is a widget of its own in settings/.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.ledger,
    required this.nav,
    this.services = const Services(),
  });

  final Ledger ledger;
  final Nav nav;

  /// Keys, backups, the calendar and screen hiding; none in the preview.
  final Services services;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _reset(Ledger Function() sample) async {
    final ok = await confirm(context, '重設範例資料？目前的變更會清除。', '重設', danger: true);
    if (!ok) return;
    widget.ledger.resetTo(sample());
    if (mounted) showNote(context, '已重設範例資料');
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final services = widget.services;
    final preferences = services.preferences;
    final notifier = services.notifier;
    final keeper = services.keeper;
    final privacy = services.privacy;
    final calendar = services.calendar;
    return ListenableBuilder(
      listenable: Listenable.merge([ledger, ?preferences]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        children: [
          // A long press on the title shows the timings and background
          // faults, for looking into a problem.
          GestureDetector(
            onLongPress: _showPerformance,
            child: PageHeader('設定與資料', onBack: widget.nav.back),
          ),
          RecordsSection(ledger: ledger, keeper: keeper),
          if (preferences != null) AppearanceSection(preferences: preferences),
          if (notifier != null) NotificationsSection(notifier: notifier),
          if (keeper != null || privacy != null)
            SecuritySection(
              keeper: keeper,
              privacy: privacy,
              drive: services.drive,
            ),
          if (calendar != null)
            LinksSection(ledger: ledger, calendar: calendar),
          // Only the preview's made-up book can be reset.
          if (services.sample case final sample?) ...[
            const SizedBox(height: 16),
            MenuPanel([
              MenuRow(
                glyph: Glyph.reset,
                title: '重設範例資料',
                color: Hue.danger,
                onTap: () => _reset(sample),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  /// Load and frame timings with the background faults, in a sheet.
  void _showPerformance() {
    showSheet<void>(
      context,
      (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '效能與診斷',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final (name, figure) in Perf.instance.report)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Text(name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        figure,
                        textAlign: TextAlign.end,
                        style: mutedSmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
