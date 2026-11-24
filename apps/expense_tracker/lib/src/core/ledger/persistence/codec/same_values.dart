/// One copy of each value that repeats from record to record as a book is
/// read: the accounts, merchants, stocks and tags entries name, and their
/// days. Decoded one record at a time, each entry would carry its own copy
/// of every one; a book of 100,000 entries kept some 300,000 such copies
/// alive, each one more object for the worker to hand over as the book
/// opens and for every later collection of garbage to look at.
///
/// Made for one reading of the book and let go with it.
final class SameValues {
  final _texts = <String, String>{};
  final _days = <String, DateTime>{};

  /// [text], or the equal one met before.
  String text(String text) => _texts[text] ??= text;

  /// The day [text] stands for, made once by [parse] for each [text].
  DateTime day(String text, DateTime Function(String text) parse) =>
      _days[text] ??= parse(text);
}
