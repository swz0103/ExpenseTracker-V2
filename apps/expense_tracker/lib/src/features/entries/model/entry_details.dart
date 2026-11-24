import '../../../core/ledger/ledger.dart';
import '../../../core/messages/installment_messages.dart';
import '../../../../design_system/display/date.dart';
import '../../../../design_system/display/amount.dart';
import '../../../core/formatting/words.dart';
import '../../../../design_system/display/status_messages.dart';

/// The sign an entry's amount is written with: − for money out, + for
/// money in, none for a transfer.
String entrySign(EntryType type) => switch (type) {
  EntryType.expense || EntryType.buy => '−',
  EntryType.income || EntryType.sell || EntryType.dividend => '+',
  EntryType.transfer => '',
};

/// What an entry looked at is called: both accounts for a transfer, the
/// holding for a trade, its own title otherwise.
String entryTitle(AccountReader accounts, Entry e) => switch (e.type) {
  EntryType.transfer =>
    '${accounts.resolve(e.account).name} → ${accounts.resolve(e.to ?? '').name}',
  EntryType.buy || EntryType.sell || EntryType.dividend => e.holding ?? e.title,
  _ => e.title,
};

/// Each thing written with [e], as (what it is, what was written), in the
/// order an entry looked at shows them; what was left empty is left out,
/// and a note that only repeats [title] too. An entry dated after
/// [today] has its day marked 預定 (D25).
List<(String, String)> entryDetails(
  AccountReader accounts,
  Entry e,
  String title, {
  required DateTime today,
}) {
  final account = accounts.resolve(e.account);
  return [
    if (e.type != EntryType.transfer) (Words.account, account.name),
    (
      Words.date,
      isPlanned(e, today)
          ? '${formatMMMEd(e.date)} · ${StatusWords.planned}'
          : formatMMMEd(e.date),
    ),
    if (e.merchant.isNotEmpty) (Words.merchant, e.merchant),
    if (e.tags.isNotEmpty) (Words.tag, e.tags.map((t) => '#$t').join(' ')),
    if (e.parts.isNotEmpty)
      (
        '拆分',
        [for (final (name, v) in e.parts) '$name ${groupDigits(v)}'].join('、'),
      ),
    if (e.installments > 1) ('分期', installmentPlan(e.amount, e.installments)),
    if (e.shares != 0) ('股數', '${groupDigits(e.shares.abs())} 股'),
    if (e.fee > 0) (Words.fee, groupDigits(e.fee)),
    if (e.tax > 0)
      (e.type == EntryType.dividend ? '二代健保' : '稅', groupDigits(e.tax)),
    if (e.home case final home?) (Words.homeWorth, groupDigits(home)),
    if ((e.type, e.received) case (EntryType.transfer, final received?))
      ('轉入金額', amountIn(received, accounts.resolve(e.to ?? '').currency)),
    if (e.note.isNotEmpty && e.note != title) (Words.note, e.note),
  ];
}
