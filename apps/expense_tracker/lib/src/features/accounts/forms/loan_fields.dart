part of 'account_editor.dart';

// The loan's form as cards: the loan itself on top, typed onto, with its
// rate, months and day as blocks; what it costs a month and in all; how
// it is paid back; and the accounts it is paid from and went into.

extension on _AccountEditorState {
  List<Widget> _loanFields(Account? old) {
    final color = nameColor(_f.name.trim().isEmpty ? '貸款' : _f.name.trim());
    return [
      Text(
        old == null ? '新增貸款' : '編輯貸款',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: TextSize.heading,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: Space.s3),
      _loanCard(old, color),
      const SizedBox(height: Space.s2),
      LoanEstimate(
        ledger: widget.ledger,
        plan: _f.plan,
        repay: _f.repay,
        color: color,
      ),
      const SizedBox(height: Space.s2),
      _repayChoice(color),
      const SizedBox(height: Space.s2),
      _loanAccounts(old),
      _counted,
      _buttons(old),
    ];
  }

  /// The loan itself, typed onto: its principal, what is owed, its rate,
  /// months and day, each opening its own picker.
  Widget _loanCard(Account? old, Color color) {
    String money(int? v) => v == null ? '0' : groupDigits(v);
    final principal = _f.typedPrincipal;
    final owed = _f.typedOwed;
    return LoanCard(
      color: color,
      name: _name,
      principal: money(principal),
      owed: owed == null ? (old == null ? '同本金' : '0') : groupDigits(owed),
      rate: _f.rate.trim().isEmpty ? '—' : '${_f.rate.trim()}%',
      months: _f.typedMonths == null
          ? '—'
          : countOf(_f.typedMonths!, CountUnit.periods),
      day: '${_f.due} 日',
      onPrincipal: () => _amount(_principal, '本金'),
      onOwed: () => _amount(_balance, '目前尚欠'),
      onRate: () => _number(
        title: '年利率',
        glyph: Glyph.gauge,
        color: color,
        controller: _rate,
        suffix: '%',
        picks: const ['1.5', '2', '2.5', '3', '5', '8'],
      ),
      onMonths: () => _number(
        title: '期數',
        glyph: Glyph.hourglass,
        color: color,
        controller: _months,
        suffix: '期',
        picks: const ['12', '24', '36', '60', '84', '120', '240', '360'],
        label: (v) => int.parse(v) % 12 == 0 && int.parse(v) >= 24
            ? '${int.parse(v) ~/ 12} 年'
            : '$v 期',
      ),
      onDay: () => _pickDay(false),
    );
  }

  /// 從哪扣款, and 撥款到 for a new loan: the accounts it is paid from
  /// and went into.
  Widget _loanAccounts(Account? old) {
    final ledger = widget.ledger;
    final payFrom = _f.payFrom;
    final fund = _f.fundInto;
    final payer = payFrom != null && ledger.accounts.contains(payFrom)
        ? ledger.account(payFrom)
        : null;
    final into = fund != null && ledger.accounts.contains(fund)
        ? ledger.account(fund)
        : null;
    return Row(
      children: [
        Expanded(
          child: _AccountBlock(
            label: '從哪扣款',
            account: payer,
            empty: '不指定',
            onTap: _pickPayFrom,
          ),
        ),
        if (old == null) ...[
          const SizedBox(width: Space.s2),
          Expanded(
            child: _AccountBlock(
              label: '撥款到',
              account: into,
              empty: '只記欠款',
              onTap: _pickFund,
            ),
          ),
        ],
      ],
    );
  }

  /// How the loan is paid back: even payments, even principal, or interest
  /// only.
  Widget _repayChoice(Color color) => BigSegments(
    items: [
      for (final repay in LoanRepay.values)
        (
          switch (repay) {
            LoanRepay.even => Glyph.calendar,
            LoanRepay.principal => Glyph.pie,
            LoanRepay.interest => Glyph.coins,
          },
          repayName(repay),
          color,
        ),
    ],
    selected: _f.repay.index,
    onChanged: (i) => _set(() => _f.repay = LoanRepay.values[i]),
  );

  /// Opens the calculator on [controller]'s amount.
  Future<void> _amount(TextEditingController controller, String title) async {
    final value = await showCalculator(
      context,
      title: title,
      initial: parseAmount(controller.text, scale: 0).minorOrNull ?? 0,
      color: AppColors.accent,
    );
    if (value != null) controller.text = '$value';
  }

  /// A panel in the middle with the usual values to tap and a field for
  /// any other.
  Future<void> _number({
    required String title,
    required Glyph glyph,
    required Color color,
    required TextEditingController controller,
    required String suffix,
    required List<String> picks,
    String Function(String)? label,
  }) async {
    final picked = await showPanel<String>(
      context,
      (context) => _NumberPanel(
        glyph: glyph,
        color: color,
        title: title,
        initial: controller.text,
        suffix: suffix,
        picks: picks,
        label: label,
      ),
    );
    if (picked != null && mounted) controller.text = picked.trim();
  }

  Future<void> _pickPayFrom() async {
    final ledger = widget.ledger;
    final picked = await pickOption<String>(
      context,
      title: '從哪扣款',
      selected: _f.payFrom ?? '',
      columns: 3,
      options: [
        const Option('', '不指定', Glyph.other, AppColors.faint),
        ...accountOptions(
          ledger,
          currency: homeCode,
          where: (a) => !a.kind.isDebt && a.kind != AccountKind.receivable,
        ),
      ],
    );
    if (picked == null || !mounted) return;
    _set(() => _f.payFrom = picked.isEmpty ? null : picked);
  }
}

/// The panel for a loan's rate or months: preset pills over a field to
/// type another. It owns its text controller, so the controller lives
/// until the panel has finished closing, not only until it pops.
class _NumberPanel extends StatefulWidget {
  const _NumberPanel({
    required this.glyph,
    required this.color,
    required this.title,
    required this.initial,
    required this.suffix,
    required this.picks,
    this.label,
  });

  final Glyph glyph;
  final Color color;
  final String title;
  final String initial;
  final String suffix;
  final List<String> picks;
  final String Function(String)? label;

  @override
  State<_NumberPanel> createState() => _NumberPanelState();
}

class _NumberPanelState extends State<_NumberPanel> {
  late final _typed = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CenterPanel(
    glyph: widget.glyph,
    color: widget.color,
    title: widget.title,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in widget.picks)
              ChoicePill(
                label: widget.label?.call(v) ?? '$v${widget.suffix}',
                selected: _typed.text.trim() == v,
                onTap: () => Navigator.of(context).pop(v),
              ),
          ],
        ),
        const SizedBox(height: Space.s4),
        TextField(
          controller: _typed,
          autofocus: false,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          onSubmitted: (v) => Navigator.of(context).pop(v),
          style: const TextStyle(
            fontSize: TextSize.large,
            fontWeight: FontWeight.w800,
          ),
          decoration: InputDecoration(
            hintText: '其他',
            suffixText: widget.suffix,
            filled: true,
            fillColor: AppColors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.large),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    ),
    actions: [
      PanelButton(Words.cancel, onTap: () => Navigator.of(context).pop()),
      PanelButton(
        Words.done,
        color: AppColors.accent,
        onTap: () => Navigator.of(context).pop(_typed.text),
      ),
    ],
  );
}
