import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../backup/model/keeper.dart';
import '../../../../core/look/figures.dart';
import '../../../../core/look/glyphs.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/ui/pickers.dart';
import '../../../import/model/exchange.dart';
import '../../../../core/ledger/ledger.dart';
import '../../../../core/problems.dart';
import '../../../import/ui/import_page.dart';
import '../settings_hue.dart';

/// 匯入與匯出: 匯出 CSV across the page, which asks how much (this month,
/// this year, everything, or from one day to another); under 匯入, a CSV
/// file and the e-invoices of a carrier. CSV carries entries only, not a
/// whole book: backups are restored in 備份與還原.
class ExchangeSection extends StatelessWidget {
  const ExchangeSection({super.key, required this.ledger, this.keeper});

  final Ledger ledger;

  /// Saves files and reads them; without it exports are copied instead.
  final Keeper? keeper;

  @override
  Widget build(BuildContext context) {
    final keeper = this.keeper;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RuleHead('匯出'),
        ColorCard(
          color: SettingsHue.csv,
          label: '匯出 CSV',
          onTap: () => showSheet<void>(
            context,
            (_) => _ExportSheet(ledger: ledger, keeper: keeper),
          ),
          child: Row(
            children: [
              const SquareIcon(Glyph.upload, SettingsHue.csv, size: 50),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '匯出 CSV',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: deepOf(SettingsHue.csv),
                      ),
                    ),
                    OneLine(
                      '一個月或全部，選好再匯出',
                      style: TextStyle(
                        fontSize: 13,
                        color: deepOf(SettingsHue.csv),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const RuleHead('匯入'),
        CardGrid([
          SettingCard(
            glyph: Glyph.records,
            color: SettingsHue.exchange,
            title: 'CSV 檔案',
            detail: '別的 App 匯出的',
            onTap: () =>
                importInto(context, ledger, readFile: keeper?.readFile),
          ),
          SettingCard(
            glyph: Glyph.scan,
            color: SettingsHue.invoice,
            title: '電子發票',
            detail: '掃載具或 QR',
            onTap: () => importInto(
              context,
              ledger,
              invoices: true,
              readFile: keeper?.readFile,
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
  const _ExportSheet({required this.ledger, this.keeper});

  final Ledger ledger;
  final Keeper? keeper;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  var _span = _Span.month;
  late DateTime _from = DateTime(_today.year, _today.month);
  late DateTime _to = _today;

  Ledger get _ledger => widget.ledger;
  DateTime get _today => _ledger.today;

  /// The entries [span] covers, oldest first as the ledger keeps them.
  List<Entry> _entries(_Span span) {
    final t = _today;
    bool within(DateTime d, DateTime from, DateTime to) {
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(from) && !day.isAfter(to);
    }

    return switch (span) {
      _Span.month => _ledger.entriesIn(t.year, t.month),
      _Span.year => [
        for (final e in _ledger.entries)
          if (e.date.year == t.year) e,
      ],
      _Span.all => _ledger.entries.toList(),
      _Span.custom => [
        for (final e in _ledger.entries)
          if (within(e.date, _from, _to)) e,
      ],
    };
  }

  String _name(_Span span) {
    String day(DateTime d) =>
        '${d.year}${'${d.month}'.padLeft(2, '0')}${'${d.day}'.padLeft(2, '0')}';
    final t = _today;
    return switch (span) {
      _Span.month => '記帳本-${t.year}-${'${t.month}'.padLeft(2, '0')}.csv',
      _Span.year => '記帳本-${t.year}.csv',
      _Span.all => '記帳本-全部.csv',
      _Span.custom => '記帳本-${day(_from)}-${day(_to)}.csv',
    };
  }

  Future<void> _export() async {
    final entries = _entries(_span);
    final text = toCsv(_ledger, entries);
    final what = ' ${entries.length} 筆紀錄的 CSV';
    final keeper = widget.keeper;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    void note(String words) =>
        messenger?.showSnackBar(SnackBar(content: Text(words)));
    if (keeper == null) {
      await Clipboard.setData(ClipboardData(text: text));
      note('已複製$what');
      return;
    }
    try {
      final saved = await keeper.exportFile(_name(_span), text);
      if (saved) note('已下載$what');
    } on Object catch (error) {
      note('下載失敗：${describeProblem(error)}');
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

  @override
  Widget build(BuildContext context) {
    const color = SettingsHue.csv;
    final t = _today;
    final count = _entries(_span).length;
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              '匯出多少',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, span) in _Span.values.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _SpanChoice(
                      label: names[span]!,
                      sub: sub(span),
                      chosen: span == _span,
                      color: color,
                      onTap: () => setState(() => _span = span),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_span == _Span.custom) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: tintOf(color, 0.16),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _DayEnd(
                      label: '從',
                      day: _from,
                      color: color,
                      onTap: () => _pick(first: true),
                    ),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const GlyphIcon(
                      Glyph.arrow,
                      size: 18,
                      color: Color(0xFFFFFFFF),
                      tinted: false,
                    ),
                  ),
                  Expanded(
                    child: _DayEnd(
                      label: '到',
                      day: _to,
                      color: color,
                      onTap: () => _pick(first: false),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          PanelButton(
            '匯出 ${groupDigits(count)} 筆',
            color: color,
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
          borderRadius: BorderRadius.circular(16),
          side: chosen ? chosenEdge(color) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  Text(
                    sub,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: ink),
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
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: ink)),
            Text(
              '${day.year}/${day.month}/${day.day}',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            Text(
              '週${weekdayNames[day.weekday - 1]}',
              style: TextStyle(fontSize: 12, color: ink),
            ),
          ],
        ),
      ),
    );
  }
}
