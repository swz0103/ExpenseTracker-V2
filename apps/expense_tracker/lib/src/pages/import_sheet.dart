import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../compose/pickers.dart';
import '../demo/exchange.dart';
import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/icons.dart';
import '../look/theme.dart';
import '../look/widgets.dart';

/// Opens the import form: CSV lines, or the e-invoice export when
/// [invoices] is set, pasted in, read and added to [ledger].
Future<void> importInto(
  BuildContext context,
  Ledger ledger, {
  bool invoices = false,
}) {
  return showSheet<void>(
    context,
    (_) => _ImportSheet(ledger: ledger, invoices: invoices),
  );
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({required this.ledger, required this.invoices});

  final Ledger ledger;
  final bool invoices;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  final _text = TextEditingController();
  late var _account = _first();
  Import? _found;

  String _first() {
    final open = widget.ledger.openAccounts;
    for (final a in open) {
      if (widget.invoices && a.kind == AccountKind.card) return a.id;
    }
    return open.first.id;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _read() {
    final ledger = widget.ledger;
    final text = _text.text;
    setState(() {
      _found = widget.invoices
          ? importInvoices(ledger, text, account: _account)
          : importCsv(ledger, text, fallback: _account);
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || !mounted) return;
    _text.text = text;
    _read();
  }

  Future<void> _pickAccount() async {
    final ledger = widget.ledger;
    final picked = await pickOption<String>(
      context,
      title: widget.invoices ? '用哪個帳戶付款' : '找不到帳戶時記到',
      selected: _account,
      columns: 3,
      options: [
        for (final a in ledger.openAccounts)
          Option(a.id, a.name, accountIcon(a), accountColor(a.kind)),
      ],
    );
    if (picked == null || !mounted) return;
    _account = picked;
    _read();
  }

  void _add() {
    final found = _found;
    if (found == null || found.entries.isEmpty) return;
    widget.ledger.addAll(found.entries);
    showNote(context, '已匯入 ${found.entries.length} 筆紀錄');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final found = _found;
    final total = found == null
        ? 0
        : found.entries.fold(0, (sum, e) => sum + e.amount);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.invoices ? '匯入電子發票' : '匯入 CSV',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 5,
            maxLines: 8,
            onChanged: (_) => _read(),
            style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: widget.invoices
                  ? 'M|手機條碼|/ABC123|20260312|…|全聯|AB12345678|268|開立'
                  : '日期,類型,金額,帳戶,分類,商家,標籤,備註',
              filled: true,
              fillColor: Hue.tile,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TileRow([
            Tile(
              icon: Glyph.note,
              label: '剪貼簿',
              value: '貼上',
              size: 15,
              onTap: _paste,
            ),
            Tile(
              icon: Glyph.wallet,
              label: widget.invoices ? '付款帳戶' : '預設帳戶',
              value: ledger.account(_account).name,
              size: 15,
              onTap: _pickAccount,
            ),
          ]),
          if (found != null)
            Tile(
              icon: Glyph.download,
              label: '讀到',
              value: '${found.entries.length} 筆',
              sub: found.skipped == 0
                  ? '合計 ${money(total)}'
                  : '合計 ${money(total)} · 略過 ${found.skipped} 行',
            ),
          if (found != null)
            for (final e in found.entries.take(5))
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
                child: Row(
                  children: [
                    Text(
                      '${e.date.month}/${e.date.day}',
                      style: const TextStyle(fontSize: 12, color: Hue.muted),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        [
                          if (e.merchant.isNotEmpty) e.merchant,
                          e.category,
                        ].join(' · '),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      groupDigits(e.amount),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: e.type == EntryType.income
                            ? Hue.positive
                            : Hue.ink,
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: found == null || found.entries.isEmpty ? null : _add,
            style: FilledButton.styleFrom(
              backgroundColor: Hue.accent,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              found == null || found.entries.isEmpty
                  ? '匯入'
                  : '匯入 ${found.entries.length} 筆',
            ),
          ),
        ],
      ),
    );
  }
}
