part of 'account_editor.dart';

// The loan's form as cards: the loan itself on top, typed onto, with its
// rate, months and day as blocks; what it costs a month and in all; how
// it is paid back; and the accounts it is paid from and went into.

extension on _AccountEditorState {
  List<Widget> _loanFields(Account? old) {
    final ledger = widget.ledger;
    final color = nameColor(_f.name.trim().isEmpty ? '貸款' : _f.name.trim());
    final payFrom = _f.payFrom;
    final fund = _f.fundInto;
    String money(int? v) => v == null ? '0' : groupDigits(v);
    final principal = _f.typedPrincipal;
    final owed = minorOf(_f.balance, homeCode);
    final payer = payFrom != null && ledger.accounts.contains(payFrom)
        ? ledger.account(payFrom)
        : null;
    final into = fund != null && ledger.accounts.contains(fund)
        ? ledger.account(fund)
        : null;
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
      _LoanCard(
        color: color,
        name: _name,
        principal: money(principal),
        owed: owed == null ? (old == null ? '同本金' : '0') : groupDigits(owed),
        rate: _f.rate.trim().isEmpty ? '—' : '${_f.rate.trim()}%',
        months: _f.typedMonths == null ? '—' : '${_f.typedMonths} 期',
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
      ),
      const SizedBox(height: Space.s2),
      _Estimate(ledger: ledger, plan: _f.plan, repay: _f.repay, color: color),
      const SizedBox(height: Space.s2),
      BigSegments(
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
      ),
      const SizedBox(height: Space.s2),
      Row(
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
      ),
      _counted,
      _buttons(old),
    ];
  }

  /// Opens the calculator on [controller]'s amount.
  Future<void> _amount(TextEditingController controller, String title) async {
    final value = await showCalculator(
      context,
      title: title,
      initial: int.tryParse(controller.text.replaceAll(',', '')) ?? 0,
      color: Hue.accent,
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
    final typed = TextEditingController(text: controller.text);
    final picked = await showPanel<String>(
      context,
      (context) => StatefulBuilder(
        builder: (context, setState) => CenterPanel(
          glyph: glyph,
          color: color,
          title: title,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in picks)
                    ChoicePill(
                      label: label?.call(v) ?? '$v$suffix',
                      selected: typed.text.trim() == v,
                      onTap: () => Navigator.of(context).pop(v),
                    ),
                ],
              ),
              const SizedBox(height: Space.s4),
              TextField(
                controller: typed,
                autofocus: false,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) => Navigator.of(context).pop(v),
                style: const TextStyle(
                  fontSize: TextSize.large,
                  fontWeight: FontWeight.w800,
                ),
                decoration: InputDecoration(
                  hintText: '其他',
                  suffixText: suffix,
                  filled: true,
                  fillColor: Hue.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.large),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            PanelButton('取消', onTap: () => Navigator.of(context).pop()),
            PanelButton(
              '完成',
              color: Hue.accent,
              onTap: () => Navigator.of(context).pop(typed.text),
            ),
          ],
        ),
      ),
    );
    typed.dispose();
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
        const Option('', '不指定', Glyph.other, Hue.faint),
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

/// The loan as a card in its colour: the name typed straight onto it, the
/// amount borrowed large and what is still owed, each opening the
/// calculator, and three blocks along the bottom for the rate, the months
/// and the day it is paid.
class _LoanCard extends StatelessWidget {
  const _LoanCard({
    required this.color,
    required this.name,
    required this.principal,
    required this.owed,
    required this.rate,
    required this.months,
    required this.day,
    required this.onPrincipal,
    required this.onOwed,
    required this.onRate,
    required this.onMonths,
    required this.onDay,
  });

  final Color color;
  final TextEditingController name;
  final String principal;
  final String owed;
  final String rate;
  final String months;
  final String day;
  final VoidCallback onPrincipal;
  final VoidCallback onOwed;
  final VoidCallback onRate;
  final VoidCallback onMonths;
  final VoidCallback onDay;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s2,
        Space.s4,
        Space.s4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.largeIncreased),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tintOf(color, 0.4), tintOf(color, 0.2)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SquareIcon(Glyph.loan, color, size: 36),
              const SizedBox(width: Space.s2),
              Expanded(
                child: TextField(
                  controller: name,
                  style: const TextStyle(
                    fontSize: TextSize.heading,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    hintText: '貸款名稱，例如房貸',
                    hintStyle: TextStyle(color: Hue.faint),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: Space.s2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: _Figure(
                  label: '借了多少',
                  value: principal,
                  size: 30,
                  ink: ink,
                  onTap: onPrincipal,
                ),
              ),
              const SizedBox(width: Space.s2),
              Expanded(
                flex: 2,
                child: _Figure(
                  label: '目前尚欠',
                  value: owed,
                  size: 18,
                  ink: ink,
                  end: true,
                  onTap: onOwed,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s2),
          Row(
            children: [
              for (final (i, (label, value, onTap)) in [
                ('年利率', rate, onRate),
                ('期數', months, onMonths),
                ('每月扣款', day, onDay),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: Space.s2),
                Expanded(
                  child: _Block(
                    label: label,
                    value: value,
                    ink: ink,
                    onTap: onTap,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A figure on the loan's card, its label over it, tapped to change.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.size,
    required this.ink,
    required this.onTap,
    this.end = false,
  });

  final String label;
  final String value;
  final double size;
  final Color ink;
  final VoidCallback onTap;
  final bool end;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      label: '$label $value',
      onTap: onTap,
      child: Container(
        width: double.infinity,
        alignment: end ? Alignment.centerRight : Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(vertical: Space.s1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: end
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: TextSize.small,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: end ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(fontSize: size, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the three blocks along the bottom of the loan's card.
class _Block extends StatelessWidget {
  const _Block({
    required this.label,
    required this.value,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Hue.glass,
      borderRadius: BorderRadius.circular(Radii.large),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.large),
        onTap: onTap,
        child: Semantics(
          button: true,
          label: '$label $value',
          excludeSemantics: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s2,
                vertical: Space.s2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(fontSize: TextSize.caption, color: ink),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: TextSize.title,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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

/// What the loan costs as two blocks: a month's payment, and the
/// interest over the whole term.
class _Estimate extends StatelessWidget {
  const _Estimate({
    required this.ledger,
    required this.plan,
    required this.repay,
    required this.color,
  });

  final Ledger ledger;
  final LoanPlan? plan;
  final LoanRepay repay;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final plan = this.plan;
    String money(int v) => ledger.orDots(groupDigits(v));
    if (plan == null) {
      return ColorCard(
        color: Hue.faint,
        amount: 0.22,
        radius: 20,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s4,
        ),
        child: const Row(
          children: [
            GlyphIcon(Glyph.calculator, size: 22, color: Hue.muted),
            SizedBox(width: Space.s2),
            Expanded(
              child: Text(
                '填好本金、利率、期數就會試算',
                style: TextStyle(fontSize: TextSize.body, color: Hue.muted),
              ),
            ),
          ],
        ),
      );
    }
    Widget block(
      Glyph glyph,
      Color tone,
      String label,
      String value,
      String sub,
    ) => Expanded(
      child: ColorCard(
        color: tone,
        amount: 0.2,
        radius: 20,
        padding: const EdgeInsets.fromLTRB(
          Space.s3,
          Space.s3,
          Space.s3,
          Space.s3,
        ),
        child: Row(
          children: [
            GlyphIcon(glyph, size: 22, color: tone),
            const SizedBox(width: Space.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: TextSize.caption,
                      fontWeight: FontWeight.w700,
                      color: deepOf(tone),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: TextSize.large,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mutedSmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Row(
      children: [
        block(
          Glyph.cash,
          Hue.accent,
          switch (repay) {
            LoanRepay.even => '每月繳',
            LoanRepay.principal => '第一個月',
            LoanRepay.interest => '每月利息',
          },
          money(plan.first),
          switch (repay) {
            LoanRepay.even => '',
            LoanRepay.principal => '最後 ${money(plan.last)}',
            LoanRepay.interest => '到期還本金',
          },
        ),
        const SizedBox(width: Space.s2),
        block(Glyph.coins, color, '總利息', money(plan.interest), ''),
      ],
    );
  }
}
