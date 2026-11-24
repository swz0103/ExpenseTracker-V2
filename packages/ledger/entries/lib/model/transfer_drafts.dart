import 'entry.dart';

/// The transfers the screens open the composer on, and the ones the app
/// writes by itself, built one way: a [EntryType.transfer] under
/// [transferCategory] from one account to another. The words of a note
/// are the caller's.
final class TransferDrafts {
  const TransferDrafts({required this.main, required this.today});

  /// The main account: where money paid back lands and payments leave.
  final String main;

  /// The day a draft is dated.
  final DateTime today;

  /// A transfer of [amount] from [from] to [to] on [date].
  static Entry between({
    String id = '',
    required DateTime date,
    required String from,
    required String to,
    int amount = 0,
    String note = '',
    int fee = 0,
    int? received,
  }) => Entry(
    id: id,
    date: date,
    type: EntryType.transfer,
    amount: amount,
    account: from,
    category: transferCategory,
    note: note,
    to: to,
    fee: fee,
    received: received,
  );

  /// Money moved out of [account] into the main account, to fill in.
  Entry move(String account) => between(date: today, from: account, to: main);

  /// Money paid for [person] from the main account, to fill in.
  Entry lend(String person) => between(date: today, from: main, to: person);

  /// Money [person] pays back into the main account: all they [owed] by
  /// default, nothing when it is the other way round.
  Entry payBack(String person, {required int owed}) =>
      between(date: today, from: person, to: main, amount: owed < 0 ? 0 : owed);

  /// A payment from the main account into [account], such as a loan or a
  /// card's statement.
  Entry payInto(String account, {int amount = 0, String note = ''}) =>
      between(date: today, from: main, to: account, amount: amount, note: note);
}
