import 'topic.dart';

/// Answers worked out once and thrown away when what they were worked out
/// from changes: such as a card's statement on a given day.
///
/// Each answer remembers the topics read while it was worked out: those
/// its readers told of through [noteReads], those of the answers it asked
/// for in turn, and any named in `reads` for what came in another way,
/// such as a record passed in by the caller.
final class QueryCache {
  final _answers = <Object, Object?>{};
  final _readsOf = <Object, Set<Topic>>{};

  /// The topics read by each answer being worked out, innermost last.
  final _open = <Set<Topic>>[];

  /// What [make] works out, once for each [key] until a topic it read
  /// changes. A key holds every argument the answer depends on, the day
  /// included; [reads] adds topics read other than through a tracked
  /// reader. An answer that read nothing known rests on every topic.
  T remember<T>(Object key, T Function() make, {Set<Topic> reads = const {}}) {
    if (_answers.containsKey(key)) {
      if (_open.isNotEmpty) _open.last.addAll(_readsOf[key]!);
      return _answers[key] as T;
    }
    final read = <Topic>{...reads};
    _open.add(read);
    final T made;
    try {
      made = make();
    } finally {
      _open.removeLast();
    }
    if (read.isEmpty) read.addAll(Topic.all);
    _answers[key] = made;
    _readsOf[key] = read;
    if (_open.isNotEmpty) _open.last.addAll(read);
    return made;
  }

  /// Notes that the answer being worked out, if any, read [topics].
  void noteReads(Set<Topic> topics) {
    if (_open.isNotEmpty) _open.last.addAll(topics);
  }

  /// The topics the answer kept under [key] rests on; null when none is.
  Set<Topic>? readsOf(Object key) => _readsOf[key];

  /// Throws away the answers that rest on any of [changed], and only
  /// those: a budget changed leaves every statement and balance worked out.
  void forget(Set<Topic> changed) {
    _readsOf.removeWhere((key, reads) {
      final stale = reads.any(changed.contains);
      if (stale) _answers.remove(key);
      return stale;
    });
  }

  /// How many answers are kept.
  int get length => _answers.length;
}
