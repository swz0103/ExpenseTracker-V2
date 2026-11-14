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
import '../model/app_update.dart';
import '../model/services.dart';
import 'sections/backup_section.dart';
import 'sections/exchange_section.dart';
import 'sections/preferences_section.dart';
import 'sections/reminders_section.dart';
import 'sections/trash_section.dart';
import 'settings_hue.dart';
import '../../../core/look/app_mark.dart';
import 'sections/security_section.dart';

/// 設定與資料: the main card says when the ledger was last backed up and
/// which ways are on (gold after three days without one), then six cards
/// two to a row, each saying how its page stands. With [part], one of
/// those pages.
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: part == null
              ? [CenterHeader('設定與資料', onBack: nav.back), ..._index(context)]
              : [
                  CenterHeader(part.label, onBack: nav.back),
                  ..._page(context, part),
                ],
        );
      },
    );
  }

  void _open(SettingsPart part) => nav.open(Pages.settingsPart(part));

  List<Widget> _index(BuildContext context) {
    final keeper = services.keeper;
    final google = services.preferences?.googleBackup ?? true;
    final folder = services.phone?.on ?? false;
    final drive = services.drive;
    DateTime? latest;
    for (final at in [
      if (google) keeper?.googleTakenAt,
      if (google && (drive?.linked ?? false)) drive?.backedUp,
      if (folder) services.phone?.backedUp,
    ]) {
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    final on = google || folder;
    final stale =
        latest != null && DateTime.now().difference(latest).inDays > 3;
    Widget way(String name, bool on) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Hue.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${on ? '✓' : '!'} $name',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: on ? deepOf(SettingsHue.backup) : Hue.goldText,
        ),
      ),
    );
    final update = services.update;
    return [
      if (keeper != null) ...[
        BackupHero(
          at: latest,
          on: on,
          stale: stale,
          label: on ? null : '沒有自動備份',
          onTap: () => _open(SettingsPart.backup),
          trailing: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [way('Google 備份', google), way('檔案備份', folder)],
          ),
        ),
        const SizedBox(height: 12),
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
        if (keeper != null || services.privacy != null)
          _Row(
            glyph: Glyph.shield,
            color: SettingsHue.security,
            title: '安全',
            detail: keeper == null
                ? '截圖'
                : keeper.hasPassword
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
          color: SettingsHue.exchange,
          title: '匯入與匯出',
          detail: 'CSV、發票',
          onTap: () => _open(SettingsPart.exchange),
        ),
        _Row(
          glyph: Glyph.reset,
          color: SettingsHue.trash,
          title: '最近刪除',
          detail: ledger.trash.isEmpty ? '沒有' : '${ledger.trash.length} 筆可放回',
          onTap: () => _open(SettingsPart.trash),
        ),
        _Row(
          glyph: Glyph.info,
          color: SettingsHue.about,
          title: '關於',
          detail: [
            if (_version.isNotEmpty) _version else '開發版',
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
    final keeper = services.keeper;
    final preferences = services.preferences;
    return switch (part) {
      SettingsPart.backup => [
        if (keeper != null)
          BackupSection(
            keeper: keeper,
            drive: services.drive,
            phone: services.phone,
            preferences: preferences,
          ),
      ],
      SettingsPart.exchange => [
        ExchangeSection(ledger: ledger, keeper: keeper),
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
        SecuritySection(keeper: keeper, privacy: services.privacy),
      ],
      SettingsPart.appearance => [
        if (preferences != null) AppearanceSection(preferences: preferences),
      ],
      SettingsPart.about => [_About(ledger: ledger, services: services)],
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
      color: color,
      onTap: onTap,
      label: '$title，$detail',
      padding: const EdgeInsets.fromLTRB(12, 14, 10, 14),
      radius: 20,
      child: Row(
        children: [
          SquareIcon(glyph, color, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: deepOf(color),
                  ),
                ),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: deepOf(color)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

/// 關於: the main card says the version and how it stands against the
/// newest (已是最新, 有新版 with 更新, or the download with its bar); two
/// cards: 自動更新 and 診斷, whose panel has the load, frame and fault
/// figures, the build's details, and 複製 or 下載. In the preview, starting
/// the made-up book over.
class _About extends StatelessWidget {
  const _About({required this.ledger, required this.services});

  final Ledger ledger;
  final Services services;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: Perf.instance.text));
    if (context.mounted) showNote(context, '已複製診斷紀錄');
  }

  Future<void> _export(BuildContext context) async {
    final text = Perf.instance.text;
    final keeper = services.keeper;
    if (keeper == null) return _copy(context);
    try {
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

  void _diagnostics(BuildContext context) {
    const color = SettingsHue.about;
    final figures = Perf.instance.figures;
    Widget figure(String label, String value) => Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
      decoration: BoxDecoration(
        color: tintOf(color, 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: deepOf(color),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
    showPanel<void>(
      context,
      (context) => CenterPanel(
        glyph: Glyph.bolt,
        color: color,
        title: '診斷',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardGrid(columns: 3, gap: 8, [
              figure('載入', figures.load),
              figure('影格', figures.frame),
              figure('錯誤', '${figures.errors}'),
            ]),
            const SizedBox(height: 10),
            Text(buildLabel, style: mutedSmall),
            for (final (at, what) in Perf.instance.problems.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${at.month}/${at.day} $what', style: mutedSmall),
              ),
          ],
        ),
        actions: [
          PanelButton('複製', onTap: () => _copy(context)),
          PanelButton('下載', color: color, onTap: () => _export(context)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final update = services.update;
    final preferences = services.preferences;
    return ListenableBuilder(
      listenable: Listenable.merge([?update, ?preferences]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VersionCard(update: update),
          const SizedBox(height: 12),
          CardGrid([
            if (preferences != null && (update?.possible ?? false))
              _Row2(
                glyph: Glyph.reset,
                color: SettingsHue.main,
                title: '自動更新',
                trailing: TickSwitch(
                  value: preferences.updateChecks,
                  color: SettingsHue.main,
                  label: '自動更新',
                  onChanged: (on) => preferences.update(updateChecks: on),
                ),
                onTap: () =>
                    preferences.update(updateChecks: !preferences.updateChecks),
              ),
            _Row2(
              glyph: Glyph.bolt,
              color: SettingsHue.about,
              title: '診斷',
              onTap: () => _diagnostics(context),
            ),
          ], gap: 10),
          // Only the preview's made-up book can be reset.
          if (services.sample case final sample?) ...[
            const SizedBox(height: 12),
            PanelButton('重設範例資料', onTap: () => _reset(context, sample)),
          ],
        ],
      ),
    );
  }
}

/// A short card with its icon, name and a control on the right.
class _Row2 extends StatelessWidget {
  const _Row2({
    required this.glyph,
    required this.color,
    required this.title,
    required this.onTap,
    this.trailing,
  });

  final Glyph glyph;
  final Color color;
  final String title;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ColorCard(
    color: color,
    onTap: onTap,
    radius: 20,
    padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
    child: Row(
      children: [
        SquareIcon(glyph, color, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: deepOf(color),
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// The version and how it stands: 已是最新; 有新版 0.9.1 with 更新 in
/// green; or 下載中 62% with a bar.
class _VersionCard extends StatefulWidget {
  const _VersionCard({this.update});

  final AppUpdate? update;

  @override
  State<_VersionCard> createState() => _VersionCardState();
}

class _VersionCardState extends State<_VersionCard> {
  @override
  void initState() {
    super.initState();
    // Opening 關於 shows the version there is now.
    final update = widget.update;
    if (update == null || !update.possible) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !update.busy) {
        update.checkIfOlder(const Duration(minutes: 10)).ignore();
      }
    });
  }

  String _state(AppUpdate? update) {
    if (update == null || !update.possible) return '自行建置的版本';
    final progress = update.progress;
    if (progress != null) return '下載中 ${(progress * 100).round()}%';
    if (update.checking) return '檢查中…';
    final newer = update.newer;
    if (newer != null) {
      return '有新版 ${newer.version.isEmpty ? newer.label : newer.version}';
    }
    final problem = update.problem;
    if (problem != null) return problem;
    if (update.upToDate) return '已是最新';
    return '點這裡檢查更新';
  }

  Future<void> _tap(BuildContext context, AppUpdate update) async {
    if (!update.possible || update.busy) return;
    final newer = update.newer;
    if (newer == null) {
      await update.check();
      return;
    }
    final mb = (newer.size / 1024 / 1024).toStringAsFixed(1);
    final ok = await confirm(
      context,
      '下載${newer.label}（$mb MB）並安裝？下載後 Android 會請你確認，帳本資料會保留。',
      '下載並安裝',
    );
    if (!ok) return;
    final outcome = await update.install();
    if (!context.mounted) return;
    switch (outcome) {
      case UpdateInstall.needsPermission:
        showNote(context, '請允許「記帳本」安裝應用程式，回來後再按一次');
      case UpdateInstall.damaged:
      case null:
        final problem = update.problem;
        if (problem != null) showNote(context, problem);
      case UpdateInstall.started:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.update;
    final newer = update?.newer != null;
    final progress = update?.progress;
    final color = newer ? Hue.positive : SettingsHue.main;
    return ColorCard(
      color: color,
      amount: 0.2,
      onTap: update == null || !update.possible
          ? null
          : () => _tap(context, update),
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      child: Row(
        children: [
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            child: AppMark(size: 60),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _version.isEmpty ? '開發版' : _version,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _state(update),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: deepOf(color),
                  ),
                ),
                if (progress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        color: SettingsHue.main,
                        backgroundColor: Hue.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (newer && progress == null)
            FilledButton(
              onPressed: () => _tap(context, update!),
              style: FilledButton.styleFrom(
                backgroundColor: Hue.positive,
                foregroundColor: Hue.onAccent,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '更新',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}
