import 'package:flutter/material.dart';

import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';
import '../../../core/messages/trade_messages.dart';
import 'account_editor_state.dart';

/// The card on top of the form, and its first fields: the mark, the name
/// typed straight onto it and a dot of its colour that opens the
/// colours, over the balance.
class AccountEditCard extends StatelessWidget {
  const AccountEditCard({
    super.key,
    required this.color,
    required this.icon,
    required this.kind,
    required this.name,
    required this.balance,
    required this.balanceLabel,
    required this.onColor,
  });

  final Color color;
  final Glyph icon;
  final String kind;
  final TextEditingController name;
  final TextEditingController balance;
  final String balanceLabel;
  final VoidCallback onColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: softOf(color),
      borderRadius: BorderRadius.circular(Radii.largeIncreased),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s2,
          Space.s2,
          Space.s2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_nameRow(), _balanceRow()],
        ),
      ),
    );
  }

  /// The mark, the name typed onto the card, its kind and the dot of its
  /// colour.
  Widget _nameRow() {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: AppColors.glass,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: GlyphIcon(icon, size: 17, color: color),
        ),
        const SizedBox(width: Space.s2),
        Expanded(
          child: TextField(
            controller: name,
            style: const TextStyle(
              fontSize: TextSize.title,
              fontWeight: FontWeight.w700,
            ),
            decoration: _plain.copyWith(hintText: '帳戶名稱', hintStyle: hintText),
          ),
        ),
        Text(kind, style: mutedSmall),
        ReadAsButton(
          label: '卡片顏色',
          onTap: onColor,
          child: InkResponse(
            onTap: onColor,
            radius: 24,
            child: SizedBox.square(
              dimension: 48,
              child: Center(
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: _ring,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// [balanceLabel] and the balance typed at the end of the line.
  Widget _balanceRow() {
    return Row(
      children: [
        Text(balanceLabel, style: mutedSmall),
        const SizedBox(width: Space.s3),
        Expanded(
          child: TextField(
            controller: balance,
            textAlign: TextAlign.end,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              fontSize: TextSize.large,
              fontWeight: FontWeight.w700,
            ),
            decoration: _plain.copyWith(hintText: '0', hintStyle: hintText),
          ),
        ),
        const SizedBox(width: Space.s2),
      ],
    );
  }
}

/// A field drawn as bare text on the card, with no line or fill.
const _plain = InputDecoration(
  isDense: true,
  border: InputBorder.none,
  contentPadding: EdgeInsets.symmetric(vertical: Space.s2),
);

class AccountField extends StatelessWidget {
  const AccountField({
    super.key,
    required this.controller,
    required this.hint,
    this.number = false,
    this.error,
  });

  final TextEditingController controller;
  final String hint;
  final bool number;

  /// What is wrong with what was typed, shown under the field.
  final String? error;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        hintText: hint,
        errorText: error,
        isDense: true,
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.medium),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// A day of the month in the closing or due day picker: a 48 dp key
/// named for a screen reader.
class AccountDayKey extends StatelessWidget {
  const AccountDayKey({
    super.key,
    required this.day,
    required this.picked,
    required this.onTap,
  });

  final int day;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      label: '$day 日',
      selected: picked,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: picked ? AppColors.accent : AppColors.tile,
          borderRadius: BorderRadius.circular(Radii.small),
        ),
        child: Text(
          '$day',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: picked ? AppColors.onAccent : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

/// The white ring round the chosen colour's dot.
const _ring = Border.fromBorderSide(
  BorderSide(color: AppColors.white, width: 3),
);

/// Parts of the account form kept apart from its state's file: the
/// account as it stands, and its own broker discount.
extension AccountBlocks on AccountEditorState {
  /// The account as the form stands, for its colour and label.
  Account get previewAccount => Account(
    oldAccount?.id ?? '',
    accountForm.name.trim(),
    accountForm.kind,
    0,
    icon: accountForm.icon,
    dueDay: accountForm.card ? accountForm.due : null,
    currency: accountForm.foreignAllowed ? accountForm.currency : homeCode,
    color: accountForm.color,
  );

  /// 券商手續費折扣 of an account that trades: its own, or empty for the
  /// phone-wide one (D7).
  Widget discountGroup() => FormGroup(
    title: BrokerDiscountText.title,
    child: AccountField(
      key: Keys.accountDiscount,
      controller: discountField,
      hint: BrokerDiscountText.accountHint,
      number: true,
      error: accountForm.discountProblem,
    ),
  );
}

/// The account form's foot, apart from its fields.
extension AccountEditorActions on AccountEditorState {
  /// 刪除, 封存 or 恢復 when changing, and 儲存; what is left under it.
  Widget buttons(Account? old) {
    final removable =
        old != null && !widget.ledger.accountCommands.usedOutsideTrash(old.id);
    final problem = shownProblem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s3),
            child: Text(
              problem,
              textAlign: TextAlign.center,
              style: dangerText,
            ),
          ),
        const SizedBox(height: Space.s4),
        Row(
          children: [
            if (old != null)
              TextButton(
                onPressed: removable ? deleteAccount : archiveAccount,
                style: wordButton(
                  removable || !old.archived
                      ? AppColors.danger
                      : AppColors.accent,
                  minimumSize: Size(64, 46),
                ),
                child: Text(
                  removable
                      ? Words.delete
                      : old.archived
                      ? Words.unarchive
                      : widget.ledger.balanceService.balance(old.id) == 0
                      ? Words.archive
                      : Words.settleArchive,
                ),
              ),
            const CancelButton(word: true),
            const SizedBox(width: Space.s2),
            Expanded(
              child: FilledButton(
                onPressed: saveAccount,
                style: solidButton(
                  AppColors.accent,
                  minimumSize: Size.fromHeight(46),
                  radius: Radii.medium,
                ),
                child: const Text(Words.save),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
