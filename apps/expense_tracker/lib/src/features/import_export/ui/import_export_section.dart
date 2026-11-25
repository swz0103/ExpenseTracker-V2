import 'package:core/foundation_values.dart' show BusinessDate, YearMonth;
import 'package:core/time/utc_days.dart' show dayOf, monthStart;

import '../../../core/messages/import_messages.dart';

import '../../../core/design_system/findable.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backup/model/backup_manager.dart';
import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/widgets/pickers.dart';
import '../model/import_export.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/messages/problem_messages.dart';
import 'import_page.dart';
import '../../../core/design_system/settings_colors.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';

/// 匯入與匯出: 匯出 CSV across the page, which asks how much (this month,
/// this year, everything, or from one day to another); under 匯入, a CSV
/// file and the e-invoices of a carrier. CSV carries entries only, not a
/// whole book: backups are restored in 備份與還原.
class ImportExportSection extends StatelessWidget {
  const ImportExportSection({
    super.key,
    required this.ledger,
    this.backupManager,
  });

  final Ledger ledger;

  /// Saves files and reads them; without it exports are copied instead.
  final BackupManager? backupManager;

  // What search finds here (N8): each topic marks its card.
  static const topics = [
    ImportExportTopics.export,
    ImportExportTopics.importCsv,
    ImportExportTopics.invoices,
  ];

  @override
  Widget build(BuildContext context) {
    final backupManager = this.backupManager;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RuleHead('匯出'),
        Findable(
          topic: ImportExportTopics.export,
          child: ColorCard(
            color: SettingsColors.csv,
            label: '匯出 CSV',
            onTap: () => showSheet<void>(
              context,
              (_) => _ExportSheet(ledger: ledger, backupManager: backupManager),
            ),
            child: Row(
              children: [
                const SquareIcon(Glyph.upload, SettingsColors.csv, size: 50),
                const SizedBox(width: Space.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '匯出 CSV',
                        style: TextStyle(
                          fontSize: TextSize.heading,
                          fontWeight: FontWeight.w800,
                          color: deepOf(SettingsColors.csv),
                        ),
                      ),
                      OneLine(
                        '一個月或全部，選好再匯出',
                        style: TextStyle(
                          fontSize: TextSize.small,
                          color: deepOf(SettingsColors.csv),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const RuleHead('匯入'),
        CardGrid([
          SettingCard(
            topic: ImportExportTopics.importCsv,
            glyph: Glyph.records,
            color: SettingsColors.importExport,
            title: 'CSV 檔案',
            detail: '別的 App 匯出的',
            onTap: () =>
                importInto(context, ledger, readFile: backupManager?.readFile),
          ),
          SettingCard(
            topic: ImportExportTopics.invoices,
            glyph: Glyph.scan,
            color: SettingsColors.invoice,
            title: '電子發票',
            detail: '掃載具或 QR',
            onTap: () => importInto(
              context,
              ledger,
              invoices: true,
              readFile: backupManager?.readFile,
            ),
          ),
        ]),
      ],
    );
  }
}

/// How much to export.
enum _Span { month, year, all, custom }

/// 匯出多少: four choices in a row; 自訂 adds a strip with the first and
/// last day, each tapped to change; then 匯出 N 筆.
class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.ledger, this.backupManager});

  final Ledger ledger;
  final BackupManager? backupManager;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  /// The colour of CSV across the sheet.
  static const _color = SettingsColors.csv;

  var _span = _Span.month;
  late DateTime _from = monthStart(_today);
  late DateTime _to = _today;

  Ledger get _ledger => widget.ledger;
  DateTime get _today => _ledger.today;

  /// The entries [span] covers, oldest first as the ledger keeps them.
  List<Entry> _entries(_Span span) {
    final t = _today;
    // Days, not instants: the entry's, [from]'s and [to]'s own fields.
    bool within(DateTime d, DateTime from, DateTime to) {
      final day = dayOf(d);
      return !day.isBefore(dayOf(from)) && !day.isAfter(dayOf(to));
    }

    // An export takes every entry written, 預定 ones too.
    return switch (span) {
      // Exception to as-of-today: an export.
      _Span.month => _ledger.entries.inMonth(t.year, t.month),
      _Span.year => [
        // Exception to as-of-today: an export.
        for (final e in _ledger.entries.all)
          if (e.date.year == t.year) e,
      ],
      // Exception to as-of-today: an export.
      _Span.all => _ledger.entries.all.toList(),
      _Span.custom => [
        // Exception to as-of-today: an export.
        for (final e in _ledger.entries.all)
          if (within(e.date, _from, _to)) e,
      ],
    };
  }

  String _name(_Span span) {
    String day(DateTime d) => BusinessDate.of(d).compact;
    final t = _today;
    return switch (span) {
      _Span.month => '記帳本-${YearMonth.of(t)}.csv',
      _Span.year => '記帳本-${t.year}.csv',
      _Span.all => '記帳本-全部.csv',
      _Span.custom => '記帳本-${day(_from)}-${day(_to)}.csv',
    };
  }

  Future<void> _export() async {
    final entries = _entries(_span);
    final text = toCsv(_ledger.accounts, entries);
    final what = ' ${countOf(entries.length, CountUnit.entries)}紀錄的 CSV';
    final backupManager = widget.backupManager;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    void note(String words) =>
        messenger?.showSnackBar(SnackBar(content: Text(words)));
    if (backupManager == null) {
      await Clipboard.setData(ClipboardData(text: text));
      note('已複製$what');
      return;
    }
    try {
      final saved = await backupManager.exportFile(_name(_span), text);
      if (saved) note('已下載$what');
    } on Object catch (error) {
      ErrorLog.instance.record('下載匯出檔', error);
      note(problemNote('下載失敗', error));
    }
  }

  Future<void> _pick({required bool first}) async {
    final picked = await pickDate(
      context,
      title: first ? '從哪天' : '到哪天',
      selected: first ? _from : _to,
      latest: _today,
      today: _today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (first) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
  }

  /// 這個月, 今年, 全部 and 自訂 side by side, each with what it covers.
  Widget _spans() {
    final t = _today;
    String sub(_Span span) => switch (span) {
      _Span.month => '${t.month} 月',
      _Span.year => t.month == 1 ? '1 月' : '1–${t.month} 月',
      _Span.all => '${groupDigits(_ledger.entries.length)} 筆',
      _Span.custom => '選日期',
    };
    const names = {
      _Span.month: '這個月',
      _Span.year: '今年',
      _Span.all: '全部',
      _Span.custom: '自訂',
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, span) in _Span.values.indexed) ...[
            if (i > 0) const SizedBox(width: Space.s2),
            Expanded(
              child: _SpanChoice(
                label: names[span]!,
                sub: sub(span),
                chosen: span == _span,
                color: _color,
                onTap: () => setState(() => _span = span),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 從 and 到 of a span of 自訂, with an arrow between them.
  Widget _customDays() {
    return Container(
      decoration: BoxDecoration(
        color: tintOf(_color, 0.16),
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DayEnd(
              label: '從',
              day: _from,
              color: _color,
              onTap: () => _pick(first: true),
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: _color,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const GlyphIcon(
              Glyph.arrow,
              size: 18,
              color: AppColors.onSolid,
              tinted: false,
            ),
          ),
          Expanded(
            child: _DayEnd(
              label: '到',
              day: _to,
              color: _color,
              onTap: () => _pick(first: false),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _entries(_span).length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              '匯出多少',
              style: TextStyle(
                fontSize: TextSize.heading,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: Space.s4),
          _spans(),
          if (_span == _Span.custom) ...[
            const SizedBox(height: Space.s3),
            _customDays(),
          ],
          const SizedBox(height: Space.s4),
          PanelButton(
            '匯出 ${groupDigits(count)} 筆',
            color: _color,
            onTap: count == 0 ? null : _export,
          ),
        ],
      ),
    );
  }
}

class _SpanChoice extends StatelessWidget {
  const _SpanChoice({
    required this.label,
    required this.sub,
    required this.chosen,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String sub;
  final bool chosen;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = chosen ? chosenInk(color) : deepOf(color);
    return Semantics(
      selected: chosen,
      child: Material(
        color: chosen ? chosenFill(color) : tintOf(color, 0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.large),
          side: chosen ? chosenEdge(color) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.large),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: Space.s2,
                horizontal: Space.s1,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: TextSize.title,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  Text(
                    sub,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: TextSize.caption, color: ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One end of the custom range: 從 over the date over the weekday.
class _DayEnd extends StatelessWidget {
  const _DayEnd({
    required this.label,
    required this.day,
    required this.color,
    required this.onTap,
  });

  final String label;
  final DateTime day;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.large),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s3),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: TextSize.caption, color: ink),
            ),
            Text(
              formatYMd(day),
              style: TextStyle(
                fontSize: TextSize.heading,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            Text(
              formatE(day),
              style: TextStyle(fontSize: TextSize.caption, color: ink),
            ),
          ],
        ),
      ),
    );
  }
}
