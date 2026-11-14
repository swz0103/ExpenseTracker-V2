part of 'account_editor.dart';

// The loan's form: what it costs on top, worked out as it is typed, then
// its amounts, how it is paid back, and when and from where.

extension on _AccountEditorState {
  List<Widget> _loanFields(Account? old) {
    final ledger = widget.ledger;
    final color = nameColor(_f.name.trim().isEmpty ? '貸款' : _f.name.trim());
    final payFrom = _f.payFrom;
    final fund = _f.fundInto;
    return [
      Text(
        old == null ? '新增貸款' : '編輯貸款',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      _Estimate(ledger: ledger, plan: _f.plan, repay: _f.repay, color: color),
      FormBlock(
        title: '基本',
        child: Column(
          children: [
            _Field(controller: _name, hint: '貸款名稱，例如房貸'),
            const SizedBox(height: 8),
            _Field(
              controller: _principal,
              label: '本金',
              hint: '0',
              number: true,
              calculator: true,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    controller: _rate,
                    label: '年利率',
                    hint: '0',
                    number: true,
                    suffix: '%',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Field(
                    controller: _months,
                    label: '期數',
                    hint: '0',
                    number: true,
                    suffix: '期',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Field(
              controller: _balance,
              label: '目前尚欠',
              hint: old == null ? '空白就是本金' : '0',
              number: true,
              calculator: true,
            ),
          ],
        ),
      ),
      FormBlock(
        title: '還款方式',
        child: Row(
          children: [
            for (final (i, repay) in LoanRepay.values.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: ChoicePill(
                  label: repayName(repay),
                  selected: repay == _f.repay,
                  background: Hue.white,
                  onTap: () => _set(() => _f.repay = repay),
                ),
              ),
            ],
          ],
        ),
      ),
      FormBlock(
        title: '日期與帳戶',
        child: Column(
          children: [
            _PickRow(
              label: '扣款日',
              value: '每月 ${_f.due} 日',
              onTap: () => _pickDay(false),
            ),
            const SizedBox(height: 8),
            _PickRow(
              label: '扣款帳戶',
              value: payFrom == null || !ledger.hasAccount(payFrom)
                  ? '不指定'
                  : ledger.account(payFrom).name,
              onTap: _pickPayFrom,
            ),
            if (old == null) ...[
              const SizedBox(height: 8),
              _PickRow(
                label: '撥款到',
                value: fund == null ? '不入帳（只記欠款）' : ledger.account(fund).name,
                onTap: _pickFund,
              ),
            ],
          ],
        ),
      ),
      _counted,
      _buttons(old),
    ];
  }

  Future<void> _pickPayFrom() async {
    final ledger = widget.ledger;
    final picked = await pickOption<String>(
      context,
      title: '扣款帳戶',
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

/// What the loan costs, worked out as the form is filled: the month's
/// payment large, the interest over the whole term beside it.
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: softOf(color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: plan == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '填本金、利率和期數，這裡會算出月付與總利息',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Hue.muted),
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        switch (repay) {
                          LoanRepay.even => '每月繳',
                          LoanRepay.principal => '第一個月繳',
                          LoanRepay.interest => '每月利息',
                        },
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: deepOf(color),
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          money(plan.first),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(switch (repay) {
                        LoanRepay.even => '每期一樣',
                        LoanRepay.principal => '逐月減少，最後 ${money(plan.last)}',
                        LoanRepay.interest => '最後一期連本金 ${money(plan.last)}',
                      }, style: mutedSmall),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('總利息', style: mutedSmall),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          money(plan.interest),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// A white row naming what is chosen, opening the choices.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      label: '$label，$value',
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Hue.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 14, color: Hue.muted)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const GlyphIcon(Glyph.next, size: 14, color: Hue.faint),
          ],
        ),
      ),
    );
  }
}
