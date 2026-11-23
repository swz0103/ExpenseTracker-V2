import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/display/amount.dart';
import '../../accounts/forms/account_editor.dart';
import '../../../core/widgets/entry_tile.dart';
import '../../../core/widgets/pickers.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../model/import_export.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';

/// The colours of the two imports, as on 匯入與匯出.
const _csvColor = Palette.periwinkle;
const _invoiceColor = Palette.gold;

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
  await openFullScreen<void>(
    context,
    (_) => _ImportPage(ledger: ledger, invoices: invoices, readFile: readFile),
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

  Color get _color => widget.invoices ? _invoiceColor : _csvColor;

  String _first() {
    final open = widget.ledger.accounts.open;
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
          ? importInvoices(importBookOf(ledger), _text, account: _account)
          : importCsv(importBookOf(ledger), _text, fallback: _account);
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
    } on Object catch (error) {
      ErrorLog.instance.record('讀取匯入檔', error);
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
    addImport(widget.ledger.entryCommands, chosen);
    showNote(
      context,
      '已匯入 ${countOf(chosen.entries.length, CountUnit.entries)}紀錄',
    );
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
                padding: const EdgeInsets.only(bottom: Space.s2),
                child: Text(
                  why,
                  style: const TextStyle(fontSize: TextSize.body),
                ),
              ),
            if (found.problems.length < found.skipped)
              const Text('其他的看不懂或是空白行', style: mutedSmall),
            const SizedBox(height: Space.s2),
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
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s5),
              child: CenterHeader(
                title,
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(child: found == null ? _start() : _preview(found)),
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
      padding: const EdgeInsets.fromLTRB(
        Space.s5,
        Space.s1,
        Space.s5,
        Space.s6,
      ),
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
          padding: const EdgeInsets.all(Space.s4),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(Radii.large),
          ),
          child: Text(
            widget.invoices
                ? 'M|手機條碼|…|2026/11/03|…|全聯|AB12345678|268|開立\n'
                      'D|AB12345678|1|鮮奶 2 瓶'
                : '日期,類型,金額,帳戶,分類,商家\n'
                      '2026-11-03,支出,268,現金,飲食,全聯',
            style: const TextStyle(fontSize: TextSize.small, height: 1.5),
          ),
        ),
        const SizedBox(height: Space.s3),
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
  /// each entry under its day, the latest first.
  Widget _preview(Import found) {
    final chosen = _chosen!;
    final days = groupByDay(
      found.entries.indexed,
      (indexed) => indexed.$2.date,
    ).entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    final added = [
      for (final a in chosen.accounts) a.name,
      for (final c in chosen.categories) c.name,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.s5,
        Space.s1,
        Space.s5,
        Space.s6,
      ),
      children: [
        _summary(found, chosen.entries.fold(0, (sum, e) => sum + e.amount)),
        const SizedBox(height: Space.s2),
        _accountChoice(),
        if (added.isNotEmpty) ...[
          const SizedBox(height: Space.s2),
          _added(added),
        ],
        for (final MapEntry(key: day, value: group) in days) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s2,
              Space.s4,
              Space.s2,
              Space.s2,
            ),
            child: Text(
              formatMEd(day),
              style: const TextStyle(
                fontSize: TextSize.body,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
          ),
          QuoteBoard([for (final (i, e) in group) _row(e, i)]),
        ],
      ],
    );
  }

  /// 讀到: how many entries, their [total], and the lines skipped.
  Widget _summary(Import found, int total) {
    final color = _color;
    return ColorCard(
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
                    fontSize: TextSize.small,
                    fontWeight: FontWeight.w700,
                    color: deepOf(color),
                  ),
                ),
                Text(
                  countOf(found.entries.length, CountUnit.entries),
                  style: const TextStyle(
                    fontSize: TextSize.figure,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '合計 ${widget.ledger.money(total)}',
                  style: TextStyle(
                    fontSize: TextSize.body,
                    color: deepOf(color),
                  ),
                ),
              ],
            ),
          ),
          if (found.skipped > 0)
            TextButton(
              onPressed: () => _skipped(found),
              style: wordButton(deepOf(color), minimumSize: Size(0, 48)),
              child: Text(
                '略過 ${found.skipped} 行 ⓘ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  /// The account entries without one are booked to, or invoices paid
  /// from.
  Widget _accountChoice() {
    return ColorCard(
      color: AppColors.accent,
      amount: 0.1,
      radius: Radii.large,
      onTap: _pickAccount,
      label: widget.invoices ? '付款帳戶' : '沒填帳戶時',
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s4,
      ),
      child: Row(
        children: [
          const GlyphIcon(Glyph.wallet, size: 20, color: AppColors.accent),
          const SizedBox(width: Space.s2),
          Text(
            widget.invoices ? '付款帳戶' : '沒填帳戶時記到',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            '${widget.ledger.account(_account).name} ›',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  /// The accounts and categories the import adds, each on a chip.
  Widget _added(List<String> names) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final name in names)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s3,
              vertical: Space.s2,
            ),
            decoration: BoxDecoration(
              color: tintOf(_invoiceColor, 0.3),
              borderRadius: BorderRadius.circular(Radii.largeIncreased),
            ),
            child: Text(
              '＋ $name',
              style: const TextStyle(
                fontSize: TextSize.small,
                fontWeight: FontWeight.w700,
                color: AppColors.goldText,
              ),
            ),
          ),
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
        spoken: entrySpoken(e, currency: ledger.account(e.account).currency),
        color: ticked ? entryTone(e) : AppColors.faint,
      ),
    );
  }

  Widget _bottom() {
    final count = _chosen?.entries.length ?? 0;
    return Container(
      color: AppColors.paper,
      padding: const EdgeInsets.fromLTRB(
        Space.s5,
        Space.s2,
        Space.s5,
        Space.s4,
      ),
      child: PanelButton(
        count == 0 ? '沒有勾選的紀錄' : '匯入 ${countOf(count, CountUnit.entries)}',
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
    padding: const EdgeInsets.symmetric(vertical: Space.s6),
    child: Column(
      children: [
        SquareIcon(glyph, color, size: 60),
        const SizedBox(height: Space.s3),
        Text(
          label,
          style: TextStyle(
            fontSize: TextSize.heading,
            fontWeight: FontWeight.w800,
            color: deepOf(color),
          ),
        ),
      ],
    ),
  );
}

/// What an import reads from [ledger].
ImportBook importBookOf(Ledger ledger) => ImportBook(
  accounts: ledger.accounts,
  categories: ledger.categories,
  entries: ledger.entries,
  entryQueryService: ledger.entryQueryService,
  entryValidator: ledger.entryValidator,
  marketData: ledger.marketData,
  newId: ledger.newId,
);
