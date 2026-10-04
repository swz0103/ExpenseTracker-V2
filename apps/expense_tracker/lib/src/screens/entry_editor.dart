import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../book.dart';
import '../theme.dart';
import '../ui/kit.dart';

/// Records one expense, income or transfer into [book].
class EntryEditor extends StatefulWidget {
  const EntryEditor({super.key, required this.book, required this.kind});

  final Book book;
  final EntryKind kind;

  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  late var _kind = widget.kind;
  late var _date = widget.book.today;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _category;
  late String _account = _accounts.first;
  late String _toAccount = _accounts[1];
  String? _problem;

  static const _expenseCategories = [
    '餐飲',
    '交通',
    '購物',
    '居家',
    '娛樂',
    '醫療',
    '教育',
    '其他',
  ];
  static const _incomeCategories = ['薪資', '投資', '獎金', '其他'];

  List<String> get _accounts => [
    for (final account in widget.book.accounts) account.name,
  ];

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.utc(_date.year - 1),
      lastDate: widget.book.today,
    );
    if (picked != null) {
      setState(() {
        _date = DateTime.utc(picked.year, picked.month, picked.day);
      });
    }
  }

  void _save() {
    final amount = int.tryParse(_amount.text) ?? 0;
    final transfer = _kind == EntryKind.transfer;
    final problem = amount <= 0
        ? '請輸入金額'
        : !transfer && _category == null
        ? '請選擇分類'
        : transfer && _account == _toAccount
        ? '轉出和轉入不能是同一個帳戶'
        : null;
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    final category = transfer ? '轉帳' : _category!;
    final note = _note.text.trim();
    widget.book.add(
      _date,
      Entry(
        note.isEmpty ? (transfer ? '轉帳' : category) : note,
        amount,
        kind: _kind,
        category: category,
        account: _account,
        toAccount: transfer ? _toAccount : '',
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final categories = _kind == EntryKind.income
        ? _incomeCategories
        : _expenseCategories;
    final today = _date == widget.book.today ? '（今天）' : '';
    final problem = _problem;
    final amountStyle = text.headlineMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '關閉',
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          PillTabs(
            labels: const ['支出', '收入', '轉帳'],
            selected: _kind.index,
            onChanged: (index) => setState(() {
              _kind = EntryKind.values[index];
              _category = null;
              _problem = null;
            }),
          ),
          const SizedBox(height: 20),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(r'$ ', style: amountStyle),
                IntrinsicWidth(
                  child: TextField(
                    controller: _amount,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9),
                    ],
                    style: amountStyle,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '0',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_kind == EntryKind.transfer)
            _TransferAccounts(
              accounts: _accounts,
              from: _account,
              to: _toAccount,
              onChanged: (from, to) => setState(() {
                _account = from;
                _toAccount = to;
              }),
            )
          else
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              children: [
                for (final category in categories)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() {
                      _category = category;
                      _problem = null;
                    }),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconTile(
                          categoryIcon(category),
                          size: 46,
                          selected: category == _category,
                        ),
                        const SizedBox(height: 6),
                        Text(category, style: text.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          Panel(
            onTap: _pickDate,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 18),
                const SizedBox(width: 12),
                Text('${_date.year}/${_date.month}/${_date.day}$today'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_kind != EntryKind.transfer) ...[
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      value: _account,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final name in _accounts)
                          DropdownMenuItem(value: name, child: Text(name)),
                      ],
                      onChanged: (name) => setState(() => _account = name!),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.notes, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _note,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '備註…',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (problem != null) ...[
            Text(
              problem,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: Palette.clay),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: Palette.clay,
              foregroundColor: Palette.card,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }
}

class _TransferAccounts extends StatelessWidget {
  const _TransferAccounts({
    required this.accounts,
    required this.from,
    required this.to,
    required this.onChanged,
  });

  final List<String> accounts;
  final String from;
  final String to;
  final void Function(String from, String to) onChanged;

  @override
  Widget build(BuildContext context) {
    Widget picker(String label, String value, ValueChanged<String> pick) {
      return Panel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 28, child: Text(label)),
            Expanded(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final name in accounts)
                    DropdownMenuItem(value: name, child: Text(name)),
                ],
                onChanged: (name) => pick(name!),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        picker('從', from, (name) => onChanged(name, to)),
        IconButton(
          tooltip: '對調',
          onPressed: () => onChanged(to, from),
          icon: const Icon(Icons.swap_vert, color: Palette.clay),
        ),
        picker('到', to, (name) => onChanged(from, name)),
      ],
    );
  }
}
