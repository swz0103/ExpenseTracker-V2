part of 'composer.dart';

// The amount on top: its label and the block it stands in.

extension _Amount on _ComposerState {
  /// What a screen reader calls the amount, and the keypad's title.
  String get _amountLabel => switch (_f.type) {
    _ when _f.refunded != null => '退款金額',
    _ when _f.mode == ComposeMode.lend => _f.back ? '還款金額' : '代墊金額',
    EntryType.transfer => '轉出金額',
    EntryType.dividend when _f.reducing => '退還股款',
    EntryType.dividend => '股息金額',
    _ => Words.amount,
  };

  /// The amount in the middle of the form, [under] it such as 常用.
  Widget _hero({Widget? under, String? unit}) {
    final refunded = _f.refunded;
    final most = refunded == null
        ? 0
        : _ledger.entryQueryService.refundable(refunded) +
              (widget.entry?.amount ?? 0);
    return AmountHero(
      label: _amountLabel,
      // Beside its currency the amount is figures only; beside a word
      // such as 實收 it keeps its currency.
      unit: unit ?? currencyLabel(_f.currency),
      value:
          '${_f.sign}${unit == null ? figuresIn(_f.amount, _f.currency) : amountIn(_f.amount, _f.currency)}',
      spoken: spokenAmount(
        _f.amount,
        currency: _f.currency,
        sense: _f.amount == 0
            ? AmountSense.plain
            : _f.refunded != null || (_f.editing?.isRefund ?? false)
            ? AmountSense.refund
            : switch (_f.type) {
                EntryType.expense || EntryType.buy => AmountSense.spending,
                EntryType.transfer => AmountSense.plain,
                _ => AmountSense.income,
              },
      ),
      color: _color,
      empty: _f.amount == 0,
      // Only while editing: an entry looked at shows no calculator.
      onTap: _viewing ? null : _calculate,
      sub: refunded == null
          ? null
          : '最多可退 ${_ledger.moneyIn(most, _f.currency)}',
      under: under,
    );
  }
}
