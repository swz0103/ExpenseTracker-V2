import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../backup/model/keeper.dart';
import '../../../../core/look/glyphs.dart';
import '../../../../core/look/widgets.dart';
import '../../../import/model/exchange.dart';
import '../../../../core/ledger/ledger.dart';
import '../../../../core/perf.dart';
import '../../../../core/problems.dart';
import '../../../import/ui/import_sheet.dart';
import '../../../entries/ui/trash_sheet.dart';

/// 紀錄: exporting a month or the whole book, importing, the diagnostics
/// and what was deleted lately.
class RecordsSection extends StatefulWidget {
  const RecordsSection({super.key, required this.ledger, this.keeper});

  final Ledger ledger;

  /// Saves files and reads them; without it exports are copied instead.
  final Keeper? keeper;

  @override
  State<RecordsSection> createState() => _RecordsSectionState();
}

class _RecordsSectionState extends State<RecordsSection> {
  late var _month = (widget.ledger.today.year, widget.ledger.today.month);

  Future<void> _copy(String text, String note) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showNote(context, note);
  }

  /// Saves [text] as the file [name] when the ledger can, else copies it.
  Future<void> _save(String name, String text, String what) async {
    final keeper = widget.keeper;
    if (keeper == null) return _copy(text, '已複製$what');
    try {
      final saved = await keeper.exportFile(name, text);
      if (mounted && saved) showNote(context, '已下載$what');
    } on Object catch (error) {
      if (mounted) showNote(context, '下載失敗：${describeProblem(error)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final keeper = widget.keeper;
    final (year, month) = _month;
    final entries = ledger.entriesIn(year, month);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHead('紀錄'),
        MenuPanel([
          MenuRow(
            glyph: Glyph.calendar,
            title: '匯出月份',
            trailing: MonthSwitch(
              month: _month,
              latest: (ledger.today.year, ledger.today.month),
              onChanged: (m) => setState(() => _month = m),
            ),
          ),
          MenuRow(
            glyph: Glyph.download,
            title: '匯出 $month 月',
            detail: '${entries.length} 筆 · CSV',
            onTap: () => _save(
              '記帳本-$year-${'$month'.padLeft(2, '0')}.csv',
              toCsv(ledger, entries),
              ' ${entries.length} 筆紀錄的 CSV',
            ),
          ),
          MenuRow(
            glyph: Glyph.records,
            title: '匯出全部',
            detail: '${ledger.entries.length} 筆 · CSV',
            onTap: () => _save(
              '記帳本-全部.csv',
              toCsv(ledger, ledger.entries),
              ' ${ledger.entries.length} 筆紀錄的 CSV',
            ),
          ),
          MenuRow(
            glyph: Glyph.add,
            title: '匯入 CSV',
            detail: '選檔案或貼上',
            onTap: () =>
                importInto(context, ledger, readFile: keeper?.readFile),
          ),
          MenuRow(
            glyph: Glyph.scan,
            title: '匯入電子發票',
            detail: '載具消費明細',
            onTap: () => importInto(
              context,
              ledger,
              invoices: true,
              readFile: keeper?.readFile,
            ),
          ),
          if (keeper != null)
            MenuRow(
              glyph: Glyph.note,
              title: '匯出診斷紀錄',
              detail: '回報問題用',
              onTap: () => _save('記帳本-診斷紀錄.txt', Perf.instance.text, '診斷紀錄'),
            ),
          MenuRow(
            glyph: Glyph.reset,
            title: '最近刪除',
            detail: ledger.trash.isEmpty ? '沒有' : '${ledger.trash.length} 筆可放回',
            onTap: () => showTrash(context, ledger),
          ),
        ]),
      ],
    );
  }
}
