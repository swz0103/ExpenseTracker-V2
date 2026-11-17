import 'package:flutter/material.dart';

import '../core/look/glyphs.dart';
import '../core/look/theme.dart';
import '../core/look/widgets.dart';
import '../core/ledger/ledger.dart';
import '../core/nav.dart';
import '../features/settings/model/platform_services.dart';
import '../features/backup/ui/backup_section.dart';
import '../features/import_export/ui/import_export_section.dart';
import '../features/settings/ui/preferences_section.dart';
import '../features/reminders/ui/reminders_section.dart';
import '../features/entries/ui/trash_section.dart';
import '../core/look/settings_hue.dart';
import '../features/lock/ui/security_section.dart';
import 'about_section.dart';
import '../core/look/shape.dart';
import '../core/look/spacing.dart';

/// 設定與資料: the main card says when the ledger was last backed up and
/// which ways are on (gold after three days without one), then six cards
/// two to a row, each saying how its page stands. With [part], one of
/// those pages.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.ledger,
    required this.nav,
    this.services = const PlatformServices(),
    this.part,
  });

  final Ledger ledger;
  final Nav nav;

  /// Keys, backups, the calendar and screen hiding; none in the preview.
  final PlatformServices services;

  /// The page shown; null for the list of them.
  final SettingsPart? part;

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
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s6),
          header: CenterHeader(part?.label ?? '設定與資料', onBack: nav.back),
          children: part == null ? _index(context) : _page(context, part),
        );
      },
    );
  }

  void _open(SettingsPart part) => nav.open(Pages.settingsPart(part));

  List<Widget> _index(BuildContext context) {
    final backupManager = services.backupManager;
    final folder = services.phone?.on ?? false;
    final drive = services.drive;
    final linked = drive?.linked ?? false;
    DateTime? latest;
    for (final at in [
      if (linked) drive?.backedUp,
      if (folder) services.phone?.backedUp,
    ]) {
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    final on = linked || folder;
    final stale =
        latest != null && DateTime.now().difference(latest).inDays > 3;
    Widget way(String name, bool on) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s2,
        vertical: Space.s2,
      ),
      decoration: BoxDecoration(
        color: Hue.white,
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Text(
        '${on ? '✓' : '!'} $name',
        style: TextStyle(
          fontSize: TextSize.small,
          fontWeight: FontWeight.w700,
          color: on ? deepOf(SettingsHue.backup) : Hue.goldText,
        ),
      ),
    );
    final update = services.update;
    return [
      if (backupManager != null) ...[
        BackupHero(
          at: latest,
          on: on,
          stale: stale,
          label: on ? null : '沒有自動備份',
          onTap: () => _open(SettingsPart.backup),
          trailing: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (drive != null) way('雲端硬碟', linked),
              way('資料夾', folder),
            ],
          ),
        ),
        const SizedBox(height: Space.s3),
      ],
      CardGrid([
        if (services.notifier != null || services.calendar != null)
          _Row(
            glyph: Glyph.bell,
            color: SettingsHue.reminders,
            title: '通知與提醒',
            detail: _reminders(),
            onTap: () => _open(SettingsPart.reminders),
          ),
        if (backupManager != null || services.privacy != null)
          _Row(
            glyph: Glyph.shield,
            color: SettingsHue.security,
            title: '安全',
            detail: backupManager == null
                ? '截圖'
                : backupManager.hasPassword
                ? '已設密碼'
                : '目前不用密碼',
            onTap: () => _open(SettingsPart.security),
          ),
        if (services.preferences case final preferences?)
          _Row(
            glyph: Glyph.moon,
            color: SettingsHue.appearance,
            title: '外觀與操作',
            detail: preferences.appearance.label,
            onTap: () => _open(SettingsPart.appearance),
          ),
        _Row(
          glyph: Glyph.swap,
          color: SettingsHue.importExport,
          title: '匯入與匯出',
          detail: 'CSV、發票',
          onTap: () => _open(SettingsPart.importExport),
        ),
        _Row(
          glyph: Glyph.reset,
          color: SettingsHue.trash,
          title: '最近刪除',
          detail: ledger.trash.all.isEmpty
              ? '沒有'
              : '${ledger.trash.all.length} 筆可放回',
          onTap: () => _open(SettingsPart.trash),
        ),
        _Row(
          glyph: Glyph.info,
          color: SettingsHue.about,
          title: '關於',
          detail: [
            if (appVersion.isNotEmpty) appVersion else '開發版',
            if (update?.newer != null)
              '有新版'
            else if (update?.upToDate ?? false)
              '最新',
          ].join(' · '),
          onTap: () => _open(SettingsPart.about),
        ),
      ], gap: 10),
    ];
  }

  /// How many kinds of reminder are on.
  String _reminders() {
    final preferences = services.notifier?.preferences;
    final calendar = services.calendar?.chosen != null;
    final on = [
      if (preferences?.dueAlerts ?? false) 1,
      if (preferences?.budgetAlerts ?? false) 1,
      if (preferences?.dailyNudge ?? false) 1,
      if (calendar) 1,
    ].length;
    return on == 0 ? '都沒開' : '$on 種開著';
  }

  List<Widget> _page(BuildContext context, SettingsPart part) {
    final backupManager = services.backupManager;
    final preferences = services.preferences;
    return switch (part) {
      SettingsPart.backup => [
        if (backupManager != null)
          BackupSection(
            backupManager: backupManager,
            drive: services.drive,
            phone: services.phone,
            preferences: preferences,
          ),
      ],
      SettingsPart.importExport => [
        ImportExportSection(ledger: ledger, backupManager: backupManager),
      ],
      SettingsPart.reminders => [
        RemindersSection(
          ledger: ledger,
          notifier: services.notifier,
          calendar: services.calendar,
          onBudgets: () => nav.open(Pages.budgets),
        ),
      ],
      SettingsPart.security => [
        SecuritySection(
          backupManager: backupManager,
          privacy: services.privacy,
        ),
      ],
      SettingsPart.appearance => [
        if (preferences != null) AppearanceSection(preferences: preferences),
      ],
      SettingsPart.about => [AboutSection(ledger: ledger, services: services)],
      SettingsPart.trash => [TrashSection(ledger: ledger)],
    };
  }
}

/// A card on the settings' first page: icon on the left, its name and
/// one line of how it stands.
class _Row extends StatelessWidget {
  const _Row({
    required this.glyph,
    required this.color,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final Glyph glyph;
  final Color color;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ColorCard(
      key: Keys.tool(title),
      color: color,
      onTap: onTap,
      label: '$title，$detail',
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s2,
        Space.s4,
      ),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SquareIcon(glyph, color, size: 40),
          const SizedBox(height: Space.s2),
          OneLine(
            title,
            style: TextStyle(
              fontSize: TextSize.title,
              fontWeight: FontWeight.w800,
              color: deepOf(color),
            ),
          ),
          OneLine(
            detail,
            style: TextStyle(fontSize: TextSize.small, color: deepOf(color)),
          ),
        ],
      ),
    );
  }
}
