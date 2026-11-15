import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;

import 'topic.dart';

/// Counts and announces the changes of each [Topic], so a screen that keeps
/// sums of its own knows when to work them out again, and one that rests on
/// some topics only is not built again for the others.
final class TopicNotifier {
  /// Moves on with every change of what the sums are worked out from;
  /// hiding the amounts leaves it.
  int get revision => _revision;
  var _revision = 0;

  /// How many times [topic] has changed.
  int revisionOf(Topic topic) => _counts[topic.index];

  final _counts = List.filled(Topic.values.length, 0);
  final _watchers = <Topic, _Watcher>{};

  /// Counts one more change of each of [topics].
  void count(Set<Topic> topics) {
    _revision++;
    for (final topic in topics) {
      _counts[topic.index]++;
    }
  }

  /// Tells those watching any of [topics].
  void announce(Set<Topic> topics) {
    for (final topic in topics) {
      _watchers[topic]?.notify();
    }
  }

  /// Changes of [topics] only, and of how amounts are shown: for a screen
  /// that need not be built again when, say, a budget changes.
  Listenable watch(Set<Topic> topics) => Listenable.merge([
    for (final topic in {...topics, Topic.display})
      _watchers[topic] ??= _Watcher(),
  ]);
}

/// One topic's listeners.
final class _Watcher extends ChangeNotifier {
  void notify() => notifyListeners();
}
