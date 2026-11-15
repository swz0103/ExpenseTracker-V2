import 'topic.dart';

/// Answers worked out once and thrown away when what they were worked out
/// from changes: such as a card's statement on a given day.
final class QueryCache {
  final _answers = <Object, Object?>{};
  final _readsOf = <Object, Set<Topic>>{};

  /// What [make] works out, once for each [key] until one of the [reads]
  /// topics changes. A key holds every argument the answer depends on, the
  /// day included; [reads] is every topic the answer reads.
  T remember<T>(Object key, T Function() make, {Set<Topic> reads = Topic.all}) {
    if (_answers.containsKey(key)) return _answers[key] as T;
    final made = make();
    _answers[key] = made;
    _readsOf[key] = reads;
    return made;
  }

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
