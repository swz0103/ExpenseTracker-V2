import '../cache/topic.dart';
import 'command_context.dart';
import 'command_exceptions.dart';

/// What a command tells through its [CommandContext]: at once, or, while
/// [quietly] runs, held back and told once at its end. A putting back is
/// one change: the screens, and whatever else listens, hear of it once it
/// is done or undone, never of a state between (one entry of a pair back,
/// an account opened for it).
final class HeldNotices {
  HeldNotices(this._context);

  final CommandContext _context;

  /// The topics changed while [quietly] runs; null when it does not.
  Set<Topic>? _topics;

  /// The first refusal met while [quietly] runs.
  LedgerProblem? _problem;

  /// Whether [signal] was asked for while [quietly] runs.
  var _signal = false;

  /// Runs [change] telling no one, what rests on the topics it changes
  /// thrown away as it goes; then tells its refusal, if any, and every
  /// topic it changed, at once. Within another, it is part of that one.
  T quietly<T>(T Function() change) {
    if (_topics != null) return change();
    _topics = {};
    try {
      return change();
    } finally {
      final topics = _topics!;
      final problem = _problem;
      final signal = _signal;
      _topics = null;
      _problem = null;
      _signal = false;
      if (problem != null) _context.report(problem);
      if (topics.isNotEmpty) {
        _context.changed(topics);
      } else if (signal) {
        _context.signal();
      }
    }
  }

  /// [CommandContext.changed], held back while [quietly] runs.
  void changed(Set<Topic> topics) {
    final held = _topics;
    if (held == null) return _context.changed(topics);
    _context.forget(topics);
    held.addAll(topics);
  }

  /// [CommandContext.report], held back while [quietly] runs.
  void report(LedgerProblem problem) {
    if (_topics == null) return _context.report(problem);
    _problem ??= problem;
  }

  /// [CommandContext.signal], held back while [quietly] runs.
  void signal() {
    if (_topics == null) return _context.signal();
    _signal = true;
  }
}
