import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/diagnostics/error_log.dart';
import '../core/diagnostics/performance_monitor.dart';
import '../core/look/dialogs.dart';
import '../core/look/glyphs.dart';
import '../core/look/theme.dart';
import '../core/look/widgets.dart';
import '../core/ledger/ledger.dart';
import '../core/platform/problems.dart';
import '../features/settings/model/app_update.dart';
import '../features/settings/ui/update_panel.dart';
import '../features/settings/model/platform_services.dart';
import '../core/look/settings_hue.dart';
import '../core/look/app_mark.dart';

/// 關於: the main card says the version and how it stands against the
/// newest (已是最新, 有新版 with 更新, or the download with its bar); two
/// cards: 自動更新 and 診斷, whose panel has the load, frame and fault
/// figures, the build's details, and 複製 or 下載. In the preview, starting
/// the made-up book over.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key, required this.ledger, required this.services});

  final Ledger ledger;
  final PlatformServices services;

  /// The figures, then each problem kept, as text to copy or download.
  static String get _report => [
    for (final (name, figure) in PerformanceMonitor.instance.report)
      '$name：$figure',
    '',
    ErrorLog.instance.text,
  ].join('\n');

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _report));
    if (context.mounted) showNote(context, '已複製診斷紀錄');
  }

  Future<void> _export(BuildContext context) async {
    final backupManager = services.backupManager;
    if (backupManager == null) return _copy(context);
    try {
      final saved = await backupManager.exportFile('記帳本-診斷紀錄.txt', _report);
      if (context.mounted && saved) showNote(context, '已下載診斷紀錄');
    } on Object catch (error) {
      ErrorLog.instance.record('下載診斷紀錄', error);
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
    final figures = PerformanceMonitor.instance.figures;
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
              fontSize: TextSize.caption,
              fontWeight: FontWeight.w700,
              color: deepOf(color),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: TextSize.heading,
              fontWeight: FontWeight.w800,
            ),
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
              figure('錯誤', '${ErrorLog.instance.count}'),
            ]),
            const SizedBox(height: 10),
            Text(buildLabel, style: mutedSmall),
            for (final (at, what) in ErrorLog.instance.entries.take(3))
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
              fontSize: TextSize.title,
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
      return '有新版 ${newer.name}';
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
    await showUpdatePanel(context, update);
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
                  appVersion.isEmpty ? '開發版' : appVersion,
                  style: const TextStyle(
                    fontSize: TextSize.figure,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _state(update),
                  style: TextStyle(
                    fontSize: TextSize.body,
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
              style: solidButton(
                Hue.positive,
                minimumSize: Size(0, 48),
                radius: 14,
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

/// Which build this is, set by the APK build (android.yml); empty in a
/// build made by hand and in the preview.
const appVersion = String.fromEnvironment('APP_VERSION');
const appBuild = String.fromEnvironment('APP_BUILD');
const appCommit = String.fromEnvironment('APP_COMMIT');

/// This build as 關於 says it.
String get buildLabel => appVersion.isEmpty
    ? '開發版'
    : [
        appVersion,
        if (appBuild.isNotEmpty) '第 $appBuild 版',
        if (appCommit.isNotEmpty) appCommit,
      ].join(' · ');
