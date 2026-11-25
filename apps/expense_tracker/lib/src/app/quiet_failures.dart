import 'dart:async';

import '../core/messages/problem_messages.dart';

/// Tells the person, once a run of the app for each kind (once a book,
/// for a step about the book: [QuietStep.perBook]), that a step
/// running by itself did not work ([QuietStep]); the step has recorded its
/// error in the ErrorLog, where the note says the details are (D84). Held
/// above each opening of the ledger, so a lock and an unlock do not tell
/// a standing fault again (review 31).
final class QuietFailures {
  QuietFailures(this._say);

  /// Shows a note, waiting its turn behind any other: true once it was on
  /// screen to be read (`queueNote`).
  final Future<bool> Function(String note) _say;

  /// The steps whose note was read this run.
  final _told = <QuietStep>{};

  /// The steps whose note is on screen or waiting for its turn, each
  /// with a mark of that note.
  final _saying = <QuietStep, Object>{};

  /// [step] failed: said unless it already was this run, or is being said
  /// now. It counts as told only once its note was on screen to be read:
  /// one another note took the place of is said again at the step's next
  /// failure.
  void failed(QuietStep step) {
    if (_told.contains(step) || _saying.containsKey(step)) return;
    final note = _saying[step] = Object();
    final book = _book;
    unawaited(
      _say(step.note).catchError((Object _) => false).then((shown) {
        // A note dropped meanwhile ([dropWaiting]) is not this one.
        if (_saying[step] == note) _saying.remove(step);
        // Read about the book before, it tells nothing of this one.
        if (shown && (!step.perBook || book == _book)) _told.add(step);
      }),
    );
  }

  /// Which book the notes are about; counts the books put in place.
  var _book = 0;

  /// A restore or a key reset put another book in place of the one open
  /// (review 33): what was told of the book before ([QuietStep.perBook])
  /// is told again of this one. What is told of the run stays told; a
  /// plain unlock opens the same book and does not come here.
  void newBook() {
    _book++;
    _told.removeWhere((step) => step.perBook);
    _saying.removeWhere((step, _) => step.perBook);
  }

  /// The notes waiting were dropped unseen (the messenger cleared as an
  /// opening of the ledger ends): their steps are said again at their
  /// next failure.
  void dropWaiting() => _saying.clear();
}
