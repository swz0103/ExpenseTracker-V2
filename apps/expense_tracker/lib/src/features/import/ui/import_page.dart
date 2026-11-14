import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../accounts/compose/account_editor.dart';
import '../../../core/ui/entry_tile.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../model/exchange.dart';
import '../../../core/ledger/ledger.dart';

/// The colours of the two imports, as on 匯入與匯出.
const _csvHue = Palette.periwinkle;
const _invoiceHue = Palette.gold;

/// Opens the import page: CSV lines, or the e-invoice export when
/// [invoices] is set, pasted in or read from a file, and added to
/// [ledger]. [readFile] lets the person choose a file; without it only
/// pasting is offered.
Future<void> importInto(
  BuildContext context,
  Ledger ledger, {
  bool invoices = false,
  Future<String?> Function()? readFile,
}) async {
  if (!await ensureAccount(context, ledger) || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          _ImportPage(ledger: ledger, invoices: invoices, readFile: readFile),
    ),
  );
}

/// 匯入: first two big squares, 貼上 and 選檔案, with an example and one
/// line on what is read. Once something is read: the main card (how many,
/// their total, 略過 N 行 ⓘ listing why), one strip for the account, the
/// accounts and categories that will be added in gold, each entry under
/// its day with a tick, and 匯入 N 筆 fixed at the bottom.
class _ImportPage extends StatefulWidget {
  const _ImportPage({
    required this.ledger,
    required this.invoices,
    required this.readFile,
  });

  final Ledger ledger;
  final bool invoices;
  final Future<String?> Function()? readFile;

  @override
  State<_ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<_ImportPage> {
  var _text = '';
  late var _account = _first();
  Import? _found;

  /// The places in what was read of the lines unticked, left out of the
  /// import.
  final _left = <int>{};

  Color get _color => widget.invoices ? _invoiceHue : _csvHue;

  String _first() {
    final open = widget.ledger.openAccounts;
    if (!widget.invoices) return open.first.id;
    final home = [
      for (final a in open)
        if (a.currency == homeCode) a,
    ];
    for (final a in home) {
      if (a.kind == AccountKind.card) return a.id;
    }
    return (home.isEmpty ? open : home).first.id;
  }

  void _read() {
    final ledger = widget.ledger;
    setState(() {
      _left.clear();
      _found = widget.invoices
          ? importInvoices(ledger, _text, account: _account)
          : importCsv(ledger, _text, fallback: _account);
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      showNote(context, '剪貼簿是空的');
      return;
    }
    _text = text;
    _read();
  }

  /// Reads a file the person chooses.
  Future<void> _pickFile(Future<String?> Function() readFile) async {
    final String? text;
    try {
      text = await readFile();
    } on Object {
      if (mounted) showNote(context, '讀不到這個檔案，請確認是 UTF-8 的文字檔');
      return;
    }
    if (text == null || !mounted) return;
    _text = text;
    _read();
  }

  Future<void> _pickAccount() async {
    final ledger = widget.ledger;
    final picked = await pickOption<String>(
      context,
      title: widget.invoices ? '用哪個帳戶付款' : '沒填帳戶時記到',
      selected: _account,
      columns: 3,
      // Invoices are in NT$: only accounts in it can pay them.
      options: accountOptions(
        ledger,
        currency: widget.invoices ? homeCode : null,
      ),
    );
    if (picked == null || !mounted) return;
    _account = picked;
    _read();
  }

  /// What is ticked of what was read.
  Import? get _chosen {
    final found = _found;
    if (found == null) return null;
    return found.only({
      for (var i = 0; i < found.entries.length; i++)
        if (!_left.contains(i)) i,
    });
  }

  void _add() {
    final chosen = _chosen;
    if (chosen == null || chosen.entries.isEmpty) return;
    addImport(widget.ledger, chosen);
    showNote(context, '已匯入 ${chosen.entries.length} 筆紀錄');
    Navigator.of(context).pop();
  }

  void _toggle(int index) => setState(() {
    if (!_left.remove(index)) _left.add(index);
  });

  void _skipped(Import found) {
    showPanel<void>(
      context,
      (context) => CenterPanel(
        glyph: Glyph.info,
        color: _color,
        title: '略過 ${found.skipped} 行',
        detail: '這些不會匯入',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final why in found.problems)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(why, style: const TextStyle(fontSize: 14)),
              ),
            if (found.problems.length < found.skipped)
              const Text('其他的看不懂或是空白行', style: mutedSmall),
            const SizedBox(height: 10),
            const Text(duplicateRules, style: mutedSmall),
          ],
        ),
        actions: [PanelButton('知道了', onTap: () => Navigator.of(context).pop())],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    final title = widget.invoices ? '匯入電子發票' : '匯入 CSV';
    return Scaffold(
      backgroundColor: Hue.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CenterHeader(
                title,
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(child: found == null ? _start() : _read2(found)),
            if (found != null) _bottom(),
          ],
        ),
      ),
    );
  }

  /// Before anything is read: 貼上 and 選檔案, an example and a line.
  Widget _start() {
    final readFile = widget.readFile;
    final color = _color;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        CardGrid([
          _BigChoice(
            glyph: Glyph.clipboard,
            label: '貼上',
            color: color,
            onTap: _paste,
          ),
          if (readFile != null)
            _BigChoice(
              glyph: Glyph.records,
              label: '選檔案',
              color: color,
              onTap: () => _pickFile(readFile),
            ),
        ]),
        const RuleHead('範例'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Hue.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            widget.invoices
                ? 'M|手機條碼|…|2026/11/03|…|全聯|AB12345678|268|開立\n'
                      'D|AB12345678|1|鮮奶 2 瓶'
                : '日期,類型,金額,帳戶,分類,商家\n'
                      '2026-11-03,支出,268,現金,飲食,全聯',
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.invoices
              ? '財政部「消費明細」的 CSV 或載具的 M／D 行都可以，記過的發票不會重複。'
              : '本 App 匯出的 CSV 可以完整匯回；沒有的帳戶與分類會自動新增。',
          style: mutedSmall,
        ),
      ],
    );
  }

  /// What was read: the main card, the account, what will be added, and
  /// each entry under its day.
  Widget _read2(Import found) {
    final ledger = widget.ledger;
    final chosen = _chosen!;
    final color = _color;
    final total = chosen.entries.fold(0, (sum, e) => sum + e.amount);
    final days = <DateTime, List<int>>{};
    for (final (i, e) in found.entries.indexed) {
      final d = e.date;
      days.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(i);
    }
    final keys = days.keys.toList()..sort((a, b) => b.compareTo(a));
    final added = [
      for (final a in chosen.accounts) a.name,
      for (final c in chosen.categories) c.name,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        ColorCard(
          color: color,
          amount: 0.22,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '讀到',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: deepOf(color),
                      ),
                    ),
                    Text(
                      '${found.entries.length} 筆',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '合計 ${ledger.money(total)}',
                      style: TextStyle(fontSize: 14, color: deepOf(color)),
                    ),
                  ],
                ),
              ),
              if (found.skipped > 0)
                TextButton(
                  onPressed: () => _skipped(found),
                  style: TextButton.styleFrom(
                    foregroundColor: deepOf(color),
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(
                    '略過 ${found.skipped} 行 ⓘ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ColorCard(
          color: Hue.accent,
          amount: 0.1,
          radius: 16,
          onTap: _pickAccount,
          label: widget.invoices ? '付款帳戶' : '沒填帳戶時',
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const GlyphIcon(Glyph.wallet, size: 20, color: Hue.accent),
              const SizedBox(width: 10),
              Text(
                widget.invoices ? '付款帳戶' : '沒填帳戶時記到',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${ledger.account(_account).name} ›',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Hue.accent,
                ),
              ),
            ],
          ),
        ),
        if (added.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in added)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tintOf(_invoiceHue, 0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '＋ $name',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Hue.goldText,
                    ),
                  ),
                ),
            ],
          ),
        ],
        for (final day in keys) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 16, 6, 8),
            child: Text(
              '${day.month}/${day.day} 週${weekdayNames[day.weekday - 1]}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Hue.muted,
              ),
            ),
          ),
          QuoteBoard([for (final i in days[day]!) _row(found.entries[i], i)]),
        ],
      ],
    );
  }

  Widget _row(Entry e, int i) {
    final ledger = widget.ledger;
    final ticked = !_left.contains(i);
    return QuoteRow(
      onTap: () => _toggle(i),
      lead: TickSwitch(
        value: ticked,
        color: _color,
        label: e.title,
        onChanged: (_) => _toggle(i),
      ),
      title: [
        if (e.holding != null) e.holding!,
        if (e.to != null)
          '轉到 ${ledger.account(e.to!).name}'
        else if (e.merchant.isNotEmpty)
          e.merchant
        else
          e.title,
      ].join(' · '),
      detail: e.category.isEmpty ? null : e.category,
      trailing: RowFigure(
        entryAmount(e, currency: ledger.account(e.account).currency),
        color: ticked ? entryTone(e) : Hue.faint,
      ),
    );
  }

  Widget _bottom() {
    final count = _chosen?.entries.length ?? 0;
    return Container(
      color: Hue.paper,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: PanelButton(
        count == 0 ? '沒有勾選的紀錄' : '匯入 $count 筆',
        color: count == 0 ? null : _color,
        onTap: count == 0 ? null : _add,
      ),
    );
  }
}

/// 貼上 or 選檔案: a big square in the import's colour.
class _BigChoice extends StatelessWidget {
  const _BigChoice({
    required this.glyph,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final Glyph glyph;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ColorCard(
    color: color,
    onTap: onTap,
    label: label,
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        SquareIcon(glyph, color, size: 60),
        const SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: deepOf(color),
          ),
        ),
      ],
    ),
  );
}
