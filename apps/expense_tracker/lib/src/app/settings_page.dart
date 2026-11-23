import 'package:flutter/material.dart';

import '../../design_system/display/amount.dart';
import '../core/design_system/glyphs.dart';
import '../core/design_system/theme.dart';
import '../core/design_system/design_system.dart';
import '../core/ledger/ledger.dart';
import '../core/navigation/nav.dart';
import '../features/settings/model/platform_services.dart';
import '../features/backup/ui/backup_section.dart';
import '../features/import_export/ui/import_export_section.dart';
import '../features/settings/ui/preferences_section.dart';
import '../features/reminders/ui/reminders_section.dart';
import '../features/entries/ui/trash_section.dart';
import '../core/design_system/settings_colors.dart';
import '../features/lock/ui/security_section.dart';
import 'about_section.dart';
import 'settings_search.dart';
import '../core/design_system/shape.dart';
import '../core/design_system/spacing.dart';
import '../core/time/app_clock.dart';

/// 設定與資料: a search box for any setting by name, the main card saying
/// when the ledger was last backed up and which ways are on (gold after
/// three days without one), then six cards two to a row, each saying how
/// its page stands. With [part], one of
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
  final SettingsDestination? part;

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
          children: part == null
              ? [SettingsSearch(onOpen: _open, child: _index(context))]
              : _page(context, part),
        );
      },
    );
  }

  void _open(SettingsDestination part) =>
      nav.open(AppRoutes.settingsPart(part));

  List<Widget> _index(BuildContext context) {
    return [
      if (services.backupManager != null) ...[
        _backup(),
        const SizedBox(height: Space.s3),
      ],
      _cards(),
    ];
  }

  /// The main card: when the ledger was last backed up and which ways
  /// are on, gold after three days without one.
  Widget _backup() {
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
        latest != null && AppClock.now().difference(latest).inDays > 3;
    return BackupHero(
      at: latest,
      on: on,
      stale: stale,
      label: on ? null : '沒有自動備份',
      onTap: () => _open(SettingsDestination.backup),
      trailing: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (drive != null) _way('雲端硬碟', linked),
          _way('資料夾', folder),
        ],
      ),
    );
  }

  /// One way of backing up, ticked when [on], marked with ! when not.
  Widget _way(String name, bool on) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: Space.s2,
      vertical: Space.s2,
    ),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(Radii.small),
    ),
    child: Text(
      '${on ? '✓' : '!'} $name',
      style: TextStyle(
        fontSize: TextSize.small,
        fontWeight: FontWeight.w700,
        color: on ? deepOf(SettingsColors.backup) : AppColors.goldText,
      ),
    ),
  );

  /// The cards two to a row, each saying how its page stands.
  Widget _cards() {
    final backupManager = services.backupManager;
    final update = services.update;
    return CardGrid([
      if (services.notifier != null || services.calendar != null)
        _Row(
          glyph: Glyph.bell,
          color: SettingsColors.reminders,
          title: '通知與提醒',
          detail: _reminders(),
          onTap: () => _open(SettingsDestination.reminders),
        ),
      if (backupManager != null || services.privacy != null)
        _Row(
          glyph: Glyph.shield,
          color: SettingsColors.security,
          title: '安全',
          detail: backupManager == null
              ? '截圖'
              : backupManager.hasPassword
              ? '已設密碼'
              : '目前不用密碼',
          onTap: () => _open(SettingsDestination.security),
        ),
      if (services.preferences case final preferences?)
        _Row(
          glyph: Glyph.moon,
          color: SettingsColors.appearance,
          title: '外觀與操作',
          detail: preferences.appearance.label,
          onTap: () => _open(SettingsDestination.appearance),
        ),
      _Row(
        glyph: Glyph.swap,
        color: SettingsColors.importExport,
        title: '匯入與匯出',
        detail: 'CSV、發票',
        onTap: () => _open(SettingsDestination.importExport),
      ),
      _Row(
        glyph: Glyph.reset,
        color: SettingsColors.trash,
        title: '最近刪除',
        detail: ledger.trash.all.isEmpty
            ? '沒有'
            : '${countOf(ledger.trash.all.length, CountUnit.entries)}可放回',
        onTap: () => _open(SettingsDestination.trash),
      ),
      _Row(
        glyph: Glyph.info,
        color: SettingsColors.about,
        title: '關於',
        detail: [
          if (appVersion.isNotEmpty) appVersion else '開發版',
          if (update?.newer != null)
            '有新版'
          else if (update?.upToDate ?? false)
            '最新',
        ].join(' · '),
        onTap: () => _open(SettingsDestination.about),
      ),
    ], gap: 10);
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

  List<Widget> _page(BuildContext context, SettingsDestination part) {
    final backupManager = services.backupManager;
    final preferences = services.preferences;
    return switch (part) {
      SettingsDestination.backup => [
        if (backupManager != null)
          BackupSection(
            backupManager: backupManager,
            drive: services.drive,
            phone: services.phone,
            preferences: preferences,
          ),
      ],
      SettingsDestination.importExport => [
        ImportExportSection(ledger: ledger, backupManager: backupManager),
      ],
      SettingsDestination.reminders => [
        RemindersSection(
          ledger: ledger,
          notifier: services.notifier,
          calendar: services.calendar,
          onBudgets: () => nav.open(AppRoutes.budgets),
        ),
      ],
      SettingsDestination.security => [
        SecuritySection(
          backupManager: backupManager,
          privacy: services.privacy,
        ),
      ],
      SettingsDestination.appearance => [
        if (preferences != null) AppearanceSection(preferences: preferences),
      ],
      SettingsDestination.about => [
        AboutSection(ledger: ledger, services: services),
      ],
      SettingsDestination.trash => [TrashSection(ledger: ledger)],
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
      radius: Radii.largeIncreased,
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
