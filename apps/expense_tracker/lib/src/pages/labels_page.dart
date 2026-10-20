import 'package:flutter/material.dart';

import '../compose/pickers.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import 'dialogs.dart';
import 'nav.dart';

/// 標籤與商家: every tag and merchant with how often it is used and what
/// was spent under it. Each can be renamed, merged into another or
/// removed from every entry.
class LabelsPage extends StatefulWidget {
  const LabelsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<LabelsPage> createState() => _LabelsPageState();
}

class _LabelsPageState extends State<LabelsPage> {
  var _merchants = false;

  void _rename(String from, String to) {
    if (_merchants) {
      widget.ledger.renameMerchant(from, to);
    } else {
      widget.ledger.renameTag(from, to);
    }
  }

  Future<void> _open(String name, List<String> others) async {
    final text = TextEditingController(text: name);
    final action = await showSheet<String>(
      context,
      (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _merchants ? '商家' : '標籤',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: text,
              decoration: InputDecoration(
                filled: true,
                fillColor: Hue.tile,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop('remove'),
                  style: TextButton.styleFrom(foregroundColor: Hue.danger),
                  child: const Text('移除'),
                ),
                if (others.isNotEmpty)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop('merge'),
                    style: TextButton.styleFrom(foregroundColor: Hue.accent),
                    child: const Text('合併'),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop('save'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Hue.accent,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    child: const Text('儲存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final typed = text.text.trim();
    text.dispose();
    if (!mounted) return;
    switch (action) {
      case 'save' when typed.isNotEmpty && typed != name:
        _rename(name, typed);
      case 'remove':
        final ok = await confirm(
          context,
          '刪除標籤「$name」？紀錄本身會保留。',
          '刪除',
          danger: true,
        );
        if (ok && mounted) _rename(name, '');
      case 'merge':
        final into = await pickOption<String>(
          context,
          title: '把「$name」合併到',
          selected: null,
          columns: 3,
          options: [
            for (final o in others)
              Option(o, o, _merchants ? Glyph.store : Glyph.ticket, Hue.accent),
          ],
        );
        if (into != null) _rename(name, into);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final rows = _merchants ? ledger.merchantStats : ledger.tagStats;
        final names = [for (final (name, _, _) in rows) name];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            PageHeader('標籤與商家', onBack: widget.nav.back),
            Segments(
              labels: const ['標籤', '商家'],
              selected: _merchants ? 1 : 0,
              onChanged: (i) => setState(() => _merchants = i == 1),
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text('還沒有任何紀錄', style: TextStyle(color: Hue.muted)),
                ),
              )
            else
              SoftPanel(
                color: Hue.white,
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  children: [
                    for (final (name, count, amount) in rows)
                      InkWell(
                        onTap: () => _open(name, [
                          for (final n in names)
                            if (n != name) n,
                        ]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              IconChip(
                                _merchants ? Glyph.store : Glyph.ticket,
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _merchants ? name : '#$name',
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                    Text(
                                      '$count 筆',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Hue.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                money(amount),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
