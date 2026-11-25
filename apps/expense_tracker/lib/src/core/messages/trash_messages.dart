import '../ledger/ledger.dart';
import '../../../design_system/display/amount.dart';

/// Why removing an account also empties [count] entries of the trash that
/// still name it (D78); null when none do.
String? trashedNamingNote(int count) =>
    count == 0 ? null : '「最近刪除」裡還有 $count 筆用到它的紀錄，會一併永久清除，無法再放回';

/// What to ask before putting an entry back that [hold] stands in the way
/// of (D78): the title, the yes and the words under it.
(String, String, String) restoreQuestion(RestoreHold hold) => switch (hold) {
  ClosedAccounts(:final accounts) => (
    '「${accounts.map((a) => a.name).join('」「')}」已封存',
    '解除封存並放回',
    '這筆用到已封存的帳戶，要解除封存再放回嗎？',
  ),
  OriginalInTrash(:final original) => (
    '原消費也在最近刪除',
    '一起放回',
    '這筆退款的原消費「${original.entry.title}」也已刪除，要一起放回嗎？',
  ),
  OriginalGone() => ('原消費已永久刪除', '仍要放回', '這筆退款的原消費已不在帳本，放回後不會沖回任何消費'),
};

/// Why an undo left [count] deleted entries in the trash (D78): what they
/// need is asked there, one entry at a time.
String stayedInTrashNote(int count) =>
    '${countOf(count, CountUnit.entries)}沒有復原：用到已封存的帳戶，或退款的原消費不在帳本。'
    '它們留在「最近刪除」，可以在那裡逐筆放回。';
