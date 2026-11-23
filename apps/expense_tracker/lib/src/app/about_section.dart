import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/messages/amount_messages.dart';
import '../../design_system/display/amount.dart';
import '../core/diagnostics/error_log.dart';
import '../core/diagnostics/performance_monitor.dart';
import '../core/design_system/dialogs.dart';
import '../core/design_system/glyphs.dart';
import '../core/design_system/theme.dart';
import '../core/design_system/design_system.dart';
import '../core/ledger/ledger.dart';
import '../core/messages/problem_messages.dart';
import '../core/messages/update_messages.dart';
import '../core/platform/update_status.dart';
import '../core/platform/distribution.dart';
import '../features/settings/model/app_update.dart';
import '../features/settings/ui/update_panel.dart';
import '../features/settings/model/platform_services.dart';
import '../core/design_system/settings_colors.dart';
import '../core/design_system/app_mark.dart';
import '../../design_system/display/date.dart';
import '../core/design_system/shape.dart';
import '../core/design_system/spacing.dart';

/// 關於: the main card says the version and how it stands against the
/// newest (已是最新, 有新版 with 更新, or the download with its bar); two
/// rows: 自動檢查新版本 and 診斷, whose panel has the load, frame and fault
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
    const color = SettingsColors.about;
    final figures = PerformanceMonitor.instance.figures;
    Widget figure(String label, String value) => Container(
      padding: const EdgeInsets.fromLTRB(
        Space.s3,
        Space.s2,
        Space.s2,
        Space.s3,
      ),
      decoration: BoxDecoration(
        color: tintOf(color, 0.14),
        borderRadius: BorderRadius.circular(Radii.large),
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
            const SizedBox(height: Space.s2),
            Text(buildLabel, style: mutedSmall),
            for (final (at, what) in ErrorLog.instance.entries.take(3))
              Padding(
                padding: const EdgeInsets.only(top: Space.s1),
                child: Text('${formatMd(at)} $what', style: mutedSmall),
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
          const SizedBox(height: Space.s3),
          CardGrid(
            [
              if (preferences != null && (update?.possible ?? false))
                _ActionRow(
                  glyph: Glyph.reset,
                  color: SettingsColors.main,
                  title: '自動檢查新版本',
                  // It looks and tells; installing is always the person's
                  // own choice (Android lets no app from outside the store
                  // update itself).
                  detail: '有新版會通知你，按了才更新',
                  trailing: TickSwitch(
                    value: preferences.updateChecks,
                    color: SettingsColors.main,
                    label: '自動檢查新版本',
                    onChanged: (on) => preferences.update(updateChecks: on),
                  ),
                  onTap: () => preferences.update(
                    updateChecks: !preferences.updateChecks,
                  ),
                ),
              _ActionRow(
                glyph: Glyph.bolt,
                color: SettingsColors.about,
                title: '診斷',
                onTap: () => _diagnostics(context),
              ),
            ],
            columns: 1,
            gap: 10,
          ),
          // Only the preview's made-up book can be reset.
          if (services.sample case final sample?) ...[
            const SizedBox(height: Space.s3),
            PanelButton('重設範例資料', onTap: () => _reset(context, sample)),
          ],
        ],
      ),
    );
  }
}

/// A short card with its icon, name and a control on the right.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.glyph,
    required this.color,
    required this.title,
    required this.onTap,
    this.detail,
    this.trailing,
  });

  final Glyph glyph;
  final Color color;
  final String title;

  /// A line under [title] saying what it does; none for a plain action.
  final String? detail;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ColorCard(
    color: color,
    onTap: onTap,
    radius: Radii.largeIncreased,
    padding: const EdgeInsets.fromLTRB(Space.s3, Space.s2, Space.s2, Space.s2),
    child: Row(
      children: [
        SquareIcon(glyph, color, size: 40),
        const SizedBox(width: Space.s3),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: TextSize.title,
                  fontWeight: FontWeight.w800,
                  color: deepOf(color),
                ),
              ),
              if (detail case final detail?)
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: TextSize.small,
                    color: deepOf(color),
                  ),
                ),
            ],
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

  /// How the build stands when there is no [AppUpdate] to ask: the play
  /// build has no update to speak of, and elsewhere (the preview, a
  /// phone that is not Android) the build was made by hand.
  static const UpdateStatus _withoutUpdate = canSelfUpdate
      ? UpdateHandBuilt()
      : UpdateNotOffered();

  /// What the card says under the version; null when it says nothing: the
  /// play build has no update to speak of.
  String? _state(AppUpdate? update) => UpdateMessages.status(
    update?.status ?? _withoutUpdate,
    version: appVersion,
  );

  /// 檢查更新 always answers. With a newer version known, its panel
  /// opens. Otherwise it looks, the card saying 檢查中… meanwhile, and
  /// what it found is said in a note as well as on the card, since a look
  /// that finds nothing new changes nothing there to see: the newest
  /// version with its number, a newer one (its panel opens), or why it
  /// could not tell.
  Future<void> _tap(BuildContext context, AppUpdate update) async {
    if (!update.possible || update.busy) return;
    if (update.newer == null) {
      await update.check();
      if (!context.mounted) return;
      if (update.newer == null) {
        final answer = _state(update);
        if (answer != null) showNote(context, answer);
        return;
      }
    }
    await showUpdatePanel(context, update);
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.update;
    final newer = update?.newer != null;
    final progress = update?.progress;
    final color = newer ? AppColors.positive : SettingsColors.main;
    return ColorCard(
      key: Keys.checkUpdate,
      color: color,
      amount: 0.2,
      onTap: update == null || !update.possible
          ? null
          : () => _tap(context, update),
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s4,
        Space.s4,
      ),
      child: Row(
        children: [
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(Radii.large)),
            child: AppMark(size: 60),
          ),
          const SizedBox(width: Space.s4),
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
                if (_state(update) case final state?)
                  Text(
                    state,
                    style: TextStyle(
                      fontSize: TextSize.body,
                      fontWeight: FontWeight.w700,
                      color: deepOf(color),
                    ),
                  ),
                if (progress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.extraSmall),
                      child: LinearProgressIndicator(
                        value: progress,
                        semanticsLabel: ProgressWords.downloading,
                        semanticsValue: ratioWholePercent(progress),
                        minHeight: 5,
                        color: markOf(SettingsColors.main),
                        backgroundColor: AppColors.white,
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
                AppColors.positive,
                minimumSize: Size(0, 48),
                radius: Radii.large,
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
