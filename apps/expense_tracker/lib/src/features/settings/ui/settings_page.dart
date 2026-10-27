import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/look/dialogs.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import '../../../core/perf.dart';
import '../../../core/problems.dart';
import '../../entries/ui/trash_sheet.dart';
import '../model/services.dart';
import 'sections/backup_section.dart';
import 'sections/exchange_section.dart';
import 'sections/links_section.dart';
import 'sections/preferences_section.dart';
import 'sections/security_section.dart';

/// 設定與資料: a list of its pages, each saying how it stands, and
/// 最近刪除; or, with [part], one of those pages.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.ledger,
    required this.nav,
    this.services = const Services(),
    this.part,
  });

  final Ledger ledger;
  final Nav nav;

  /// Keys, backups, the calendar and screen hiding; none in the preview.
  final Services services;

  /// The page shown; null for the list of them.
  final SettingsPart? part;

  /// The pages there is something on: the preview has no backups, no
  /// notifications and no security.
  List<SettingsPart> get _parts => [
    if (services.keeper != null) SettingsPart.backup,
    SettingsPart.exchange,
    if (services.notifier != null || services.calendar != null)
      SettingsPart.reminders,
    if (services.keeper != null || services.privacy != null)
      SettingsPart.security,
    if (services.preferences != null) SettingsPart.appearance,
    SettingsPart.about,
  ];

  @override
  Widget build(BuildContext context) {
    final preferences = services.preferences;
    return ListenableBuilder(
      listenable: Listenable.merge([
        ledger,
        ?preferences,
        ?services.drive,
        ?services.phone,
      ]),
      builder: (context, _) {
        final part = this.part;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: part == null
              ? [PageHeader('設定與資料', onBack: nav.back), _index(context)]
              : [PageHeader(part.label, onBack: nav.back), ..._page(part)],
        );
      },
    );
  }

  Widget _index(BuildContext context) {
    return MenuPanel([
      for (final part in _parts)
        MenuRow(
          glyph: _glyph(part),
          title: part.label,
          detail: _detail(part),
          onTap: () => nav.open(Pages.settingsPart(part)),
        ),
      MenuRow(
        glyph: Glyph.reset,
        title: '最近刪除',
        detail: ledger.trash.isEmpty ? '沒有' : '${ledger.trash.length} 筆可放回',
        onTap: () => showTrash(context, ledger),
      ),
    ]);
  }

  static Glyph _glyph(SettingsPart part) => switch (part) {
    SettingsPart.backup => Glyph.safe,
    SettingsPart.exchange => Glyph.download,
    SettingsPart.reminders => Glyph.bell,
    SettingsPart.security => Glyph.shield,
    SettingsPart.appearance => Glyph.moon,
    SettingsPart.about => Glyph.note,
  };

  /// How the page stands, so the list says it without opening it.
  String _detail(SettingsPart part) {
    switch (part) {
      case SettingsPart.backup:
        final phone = services.phone;
        if (phone != null && phone.on) {
          final at = phone.backedUp?.toLocal();
          return at == null ? '手機 · 還沒有備份' : '手機 · 上次 ${at.month}/${at.day}';
        }
        final drive = services.drive;
        if (drive != null && drive.linked) {
          final at = drive.backedUp?.toLocal();
          return at == null
              ? '雲端硬碟 · 還沒有備份'
              : '雲端硬碟 · 上次 ${at.month}/${at.day}';
        }
        return '備份檔、雲端硬碟、還原';
      case SettingsPart.exchange:
        return 'CSV、電子發票';
      case SettingsPart.reminders:
        final preferences = services.notifier?.preferences;
        if (preferences == null) return '日曆';
        final on = [
          if (preferences.dueAlerts) '到期',
          if (preferences.dailyNudge) '每日',
        ];
        return on.isEmpty ? '都沒開' : '${on.join('、')}提醒';
      case SettingsPart.security:
        final keeper = services.keeper;
        if (keeper == null) return '截圖';
        return keeper.hasPassword ? '已設定密碼' : '目前不用密碼';
      case SettingsPart.appearance:
        return services.preferences?.appearance.label ?? '';
      case SettingsPart.about:
        return '版本、效能與診斷';
    }
  }

  List<Widget> _page(SettingsPart part) {
    final keeper = services.keeper;
    final notifier = services.notifier;
    final calendar = services.calendar;
    final preferences = services.preferences;
    return switch (part) {
      SettingsPart.backup => [
        if (keeper != null)
          BackupSection(
            keeper: keeper,
            drive: services.drive,
            phone: services.phone,
          ),
      ],
      SettingsPart.exchange => [
        ExchangeSection(ledger: ledger, keeper: keeper),
      ],
      SettingsPart.reminders => [
        if (notifier != null) NotificationsSection(notifier: notifier),
        if (calendar != null) LinksSection(ledger: ledger, calendar: calendar),
      ],
      SettingsPart.security => [
        SecuritySection(keeper: keeper, privacy: services.privacy),
      ],
      SettingsPart.appearance => [
        if (preferences != null) AppearanceSection(preferences: preferences),
      ],
      SettingsPart.about => [_About(ledger: ledger, services: services)],
    };
  }
}

/// Which build this is, set by the APK build (android.yml); empty in a
/// build made by hand and in the preview.
const _version = String.fromEnvironment('APP_VERSION');
const _build = String.fromEnvironment('APP_BUILD');
const _commit = String.fromEnvironment('APP_COMMIT');

/// This build as 關於 says it.
String get buildLabel => _version.isEmpty
    ? '開發版'
    : [
        _version,
        if (_build.isNotEmpty) '第 $_build 版',
        if (_commit.isNotEmpty) _commit,
      ].join(' · ');

/// 關於: which build this is, the load and frame timings with the background faults, sent on
/// when reporting a problem; and, in the preview, starting the made-up
/// book over.
class _About extends StatelessWidget {
  const _About({required this.ledger, required this.services});

  final Ledger ledger;
  final Services services;

  Future<void> _export(BuildContext context) async {
    final text = Perf.instance.text;
    final keeper = services.keeper;
    try {
      if (keeper == null) {
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) showNote(context, '已複製診斷紀錄');
        return;
      }
      final saved = await keeper.exportFile('記帳本-診斷紀錄.txt', text);
      if (context.mounted && saved) showNote(context, '已下載診斷紀錄');
    } on Object catch (error) {
      if (context.mounted) {
        showNote(context, '下載失敗：${describeProblem(error)}');
      }
    }
  }

  Future<void> _reset(BuildContext context, Ledger Function() sample) async {
    final ok = await confirm(context, '重設範例資料？目前的變更會清除。', '重設', danger: true);
    if (!ok) return;
    ledger.resetTo(sample());
    if (context.mounted) showNote(context, '已重設範例資料');
  }

  @override
  Widget build(BuildContext context) {
    final report = Perf.instance.report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuPanel([
          MenuRow(glyph: Glyph.note, title: '版本', detail: buildLabel),
        ]),
        const SectionHead('效能與診斷'),
        FormBlock(
          child: Column(
            children: [
              if (report.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('還沒有紀錄', style: mutedSmall),
                ),
              for (final (name, figure) in report)
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
        const SizedBox(height: 8),
        MenuPanel([
          MenuRow(
            glyph: Glyph.download,
            title: '匯出診斷紀錄',
            detail: '回報問題用',
            onTap: () => _export(context),
          ),
          // Only the preview's made-up book can be reset.
          if (services.sample case final sample?)
            MenuRow(
              glyph: Glyph.reset,
              title: '重設範例資料',
              color: Hue.danger,
              onTap: () => _reset(context, sample),
            ),
        ]),
      ],
    );
  }
}
