import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show debugPrint, kReleaseMode, visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;

import 'package:core/foundation_values.dart' show FxException, MoneyException;
import 'package:domain/credit_cards.dart' show CreditCardException;
import 'package:domain/data_exchange.dart' show CsvFormatException;
import 'package:ledger_trade_costs/model/trade_values.dart'
    show InvestmentException;
import 'package:storage/storage_problem.dart' show StorageUnavailable;
import 'package:vault/backup_security.dart' show KeyringException;
import 'package:vault/vault_problems.dart' show BackupException, VaultException;

import 'app_fault.dart';
import 'error_steps.dart';
import '../time/app_clock.dart';

/// One fault kept: when it first happened, what did not work with the
/// cleaned error, where in the code (cleaned stack frames), and how many
/// times in a row it happened.
final class _Problem {
  _Problem(this.at, this.words, this.frames);

  final DateTime at;
  final String words;
  final List<String> frames;

  /// How many times in a row this same fault was recorded.
  var times = 1;

  /// The words shown: the fault, and how often when more than once.
  String get shown => times > 1 ? '$words ×$times' : words;

  bool same(String otherWords, List<String> otherFrames) {
    if (words != otherWords || frames.length != otherFrames.length) {
      return false;
    }
    for (var i = 0; i < frames.length; i++) {
      if (frames[i] != otherFrames[i]) return false;
    }
    return true;
  }
}

/// What did not work, kept for 設定 › 關於 › 診斷 so a fault can be seen and
/// exported instead of passing unseen. Of an error only its type, a short
/// message cleaned of anything the person wrote (names, notes, amounts,
/// paths) and the top of its stack (function names and source lines of
/// the app's own code, nothing else) are kept, and nothing is printed in a
/// release build.
///
/// Recording costs the caller no file work: a fault is kept in memory at
/// once and written a little later ([flushDelay]) with the others of that
/// moment, appended to the file by the I/O threads. A crash loses at most
/// what was recorded in the last [flushDelay] before it; [flush] is asked
/// for when the app is left and after a fault nobody caught, which
/// narrows that further. The file is bounded: past [maxFileBytes] it is
/// put aside as `<name>.1` (replacing the one before) and started again,
/// so at most two files of that size exist.
final class ErrorLog {
  ErrorLog._();

  /// A log of its own, apart from the app's: for tests.
  @visibleForTesting
  ErrorLog.detached();

  static final instance = ErrorLog._();

  /// The most problems kept in memory, shown and exported.
  static const kept = 50;

  /// The longest message kept of an error, in characters.
  static const longestMessage = 120;

  /// The most stack frames kept of one error.
  static const maxFrames = 8;

  /// The most characters kept of one error's stack, all frames together.
  static const maxStackChars = 1000;

  /// How long a problem may wait in memory before it is written: what a
  /// crash can lose.
  static const flushDelay = Duration(seconds: 2);

  /// The size past which the file is put aside and started again.
  static const maxFileBytes = 128 * 1024;

  /// Background work that did not finish, oldest first.
  final _problems = <_Problem>[];

  /// Where problems are kept across launches; none keeps them in memory.
  File? _log;

  /// The lines not yet in the file, oldest first.
  final _pending = <String>[];

  /// The last problem's count changed since it was last written.
  var _repeated = false;

  /// The size of the file as last written; null until it is asked.
  int? _size;

  /// The wait before the next write; null when nothing waits.
  Timer? _timer;

  /// The writes asked for so far, one after another.
  Future<void> _writing = Future.value();

  /// A failed write is being noted: nothing new is scheduled for it.
  var _noting = false;

  /// The file ends part way through a line, as a crash while writing
  /// leaves it: the next write starts on a line of its own.
  var _cutShort = false;

  /// The file the one before [log] is put aside as.
  static File _aside(File log) => File('${log.path}.1');

  // The file is one JSON object a line: a problem is `at`, `what` and
  // `frames`; a line with `at` and `times` says how often the problem
  // before it has happened by then.
  static const _at = 'at';
  static const _what = 'what';
  static const _frames = 'frames';
  static const _times = 'times';

  /// A problem as a line of the file.
  static String _line(_Problem problem) => jsonEncode({
    _at: problem.at.toIso8601String(),
    _what: problem.words,
    _frames: problem.frames,
  });

  /// Brings the problem of [line] back into [into], or the count of the
  /// one before it. A line that says neither is left out.
  static void _readLine(String line, List<_Problem> into) {
    if (!line.startsWith('{')) {
      // As versions before the stack was kept wrote it: when, a tab, what.
      final tab = line.indexOf('\t');
      final at = tab < 0 ? null : DateTime.tryParse(line.substring(0, tab));
      if (at != null) {
        into.add(_Problem(at, _cleanKept(line.substring(tab + 1)), const []));
      }
      return;
    }
    switch (jsonDecode(line)) {
      case {
        _at: final String time,
        _what: final String what,
        _frames: final List<Object?> frames,
      }:
        final at = DateTime.tryParse(time);
        if (at == null) return;
        into.add(
          _Problem(at, _cleanKept(what), [
            for (final frame in frames.whereType<String>().take(maxFrames))
              ?_frame(frame),
          ]),
        );
      case {_at: String _, _times: final int times}:
        if (into.isNotEmpty) into.last.times = times;
    }
  }

  /// Keeps problems in [file] from now on, and brings back those kept
  /// there before, so a fault before a crash can still be exported.
  void keepIn(File file) {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _repeated = false;
    _size = null;
    _cutShort = false;
    _log = file;
    final before = <_Problem>[];
    try {
      for (final part in [_aside(file), file]) {
        if (!part.existsSync()) continue;
        final text = part.readAsStringSync();
        if (identical(part, file)) {
          _cutShort = text.isNotEmpty && !text.endsWith('\n');
        }
        for (final line in const LineSplitter().convert(text)) {
          try {
            _readLine(line, before);
          } on FormatException catch (error) {
            // A line cut short by a crash costs only itself.
            record(ErrorSteps.logFile, error);
          }
        }
      }
    } on Object catch (error) {
      // An unreadable log starts again, and says so.
      record(ErrorSteps.logFile, error);
    }
    // Those of earlier runs are older than any of this one.
    _problems.insertAll(0, before);
    _trim();
  }

  void _trim() {
    if (_problems.length > kept) {
      _problems.removeRange(0, _problems.length - kept);
    }
    // Lines that left memory before they were written are not worth
    // writing: the file never waits on more than memory holds.
    if (_pending.length > kept) {
      _pending.removeRange(0, _pending.length - kept);
    }
  }

  /// What is kept of [error], since the log can be exported: an
  /// allow-list. Of an exception, its type, with an errno (any with an
  /// [OSError]: a file, a socket, a TLS fault) or a channel's code; its
  /// words only when the app wrote them ([AppFault], or [_ownPackages]'s)
  /// or the SDK did for a file fault. Of an [Error], a fault of the code, its words;
  /// of words the app passed itself, those. What is kept is cleaned of
  /// what could still be the person's (names, notes, amounts, addresses,
  /// tokens, paths).
  static String describe(Object error) {
    if (error is CarriedFault) {
      return '${error.runtimeType}(${describe(error.cause)})';
    }
    final said = switch (error) {
      AppFault() || Error() || String() => '$error',
      _ when _ownPackages(error) => '$error',
      // Words of the CSV reader's own: what is wrong, and the line.
      CsvFormatException(:final message) => message,
      FileSystemException(:final message) => message,
      PlatformException(:final code) => code,
      // An exception of a library or a server: its words may carry an
      // address, a file's name or a server's answer.
      _ => '',
    };
    final code = switch (error) {
      FileSystemException(:final osError) ||
      SocketException(:final osError) ||
      TlsException(:final osError) => osError?.errorCode,
      _ => null,
    };
    final errno = code == null ? '' : ' (errno $code)';
    final words = _clean(said);
    return words.isEmpty
        ? '${error.runtimeType}$errno'
        : '${error.runtimeType}: $words$errno';
  }

  /// The exceptions of the app's own packages (packages/, vault,
  /// storage), which cannot mark themselves [AppFault]: their words are
  /// a kind's name and fixed details, as an app fault's are.
  static bool _ownPackages(Object error) => switch (error) {
    BackupException() ||
    KeyringException() ||
    VaultException() ||
    StorageUnavailable() ||
    MoneyException() ||
    FxException() ||
    CreditCardException() ||
    InvestmentException() => true,
    _ => false,
  };

  static final _quoted = RegExp(r"""'[^']*'|"[^"]*"|「[^」]*」|“[^”]*”""");
  static final _path = RegExp(r'\S*[/\\]\S*');
  static final _foreign = RegExp(r'[^\x20-\x7e]+');
  // An address (`alice@example.com`) or a query (`?token=…`).
  static final _contact = RegExp(r'\S*[@?]\S*');
  // A token, a key or an id: a long run of what base64 and hex are
  // written with, a digit or a sign among it; a word of letters alone,
  // such as Drive's reason code, stays.
  static final _token = RegExp(r'(?=[\w+=\-]*[\d_+=\-])[\w+=\-]{20,}');
  // An errno and an HTTP status are kept; they say what failed, not what
  // was written.
  static final _digits = RegExp(r'(?<!errno |HTTP |\d)\d+');

  /// A problem as an older version kept it, with the whole error: what
  /// did not work, then the error, cleaned now.
  static String _cleanKept(String words) {
    final colon = words.indexOf('：');
    if (colon < 0) return _clean(words);
    return '${words.substring(0, colon)}：${_clean(words.substring(colon + 1))}';
  }

  /// One line of [text], without quoted words, paths, addresses, tokens,
  /// numbers or anything outside plain ASCII, at most [longestMessage]
  /// characters.
  static String _clean(String text) {
    var line = text.split('\n').first;
    line = line
        .replaceAll(_quoted, '…')
        .replaceAll(_contact, '…')
        .replaceAll(_path, '…')
        .replaceAll(_token, '…')
        .replaceAll(_foreign, '…')
        .replaceAll(_digits, '#')
        .trim();
    if (line.length > longestMessage) {
      line = '${line.substring(0, longestMessage)}…';
    }
    return line;
  }

  // `#3      Ledger.save.<anonymous closure> (package:app/x.dart:12:5)`.
  static final _symbolic = RegExp(
    r'^#(\d+) (.+) \(([^()\s]+?)((?::\d+){0,2})\)$',
  );
  // A name in code: letters, digits and what marks closures and generics.
  static final _member = RegExp(r'^[\w$.<>,\[\] ]+$');
  static final _library = RegExp(r'^(?:package|dart):[\w./\-]+$');
  static final _fileName = RegExp(r'^[\w.\-]+$');
  // A release build has addresses for `flutter symbolize`, no names:
  // `#00 abs 0000007b1c virt 00000000001a2b3c _kDartIsolateSnapshotInstructions+0x1f2c`.
  static final _address = RegExp(
    r'^#\d+ abs [0-9a-f]+(?: virt [0-9a-f]+)? [\w.]+\+0x[0-9a-f]+$',
  );

  /// One stack frame as it is kept, or null for a line that is not one.
  /// Only what code is made of passes: a function's name, and its source
  /// as `package:` or `dart:` with the line; a file elsewhere on a disk
  /// (a test run) keeps its name only, never its folders. A release
  /// build's frame is addresses, kept as they are.
  static String? _frame(String raw) {
    final line = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (_address.hasMatch(line)) return line;
    final match = _symbolic.firstMatch(line);
    if (match == null) return null;
    final member = match[2]!;
    if (!_member.hasMatch(member)) return null;
    var source = match[3]!;
    if (!_library.hasMatch(source)) {
      source = source.split(RegExp(r'[/\\]')).last;
      if (!_fileName.hasMatch(source)) return null;
    }
    return '#${match[1]} $member ($source${match[4]})';
  }

  /// The top of [stack] as it is kept: at most [maxFrames] frames and
  /// [maxStackChars] characters, without the log's own frames.
  static List<String> frames(StackTrace stack) {
    final found = <String>[];
    var length = 0;
    for (final raw in '$stack'.split('\n')) {
      final frame = _frame(raw);
      if (frame == null || frame.contains('/diagnostics/error_log.dart')) {
        continue;
      }
      if (found.length == maxFrames || length + frame.length > maxStackChars) {
        break;
      }
      found.add(frame);
      length += frame.length;
    }
    return found;
  }

  /// Keeps that [what] did not work, for 設定 › 關於 › 診斷, rather than letting
  /// it pass unseen: the error's type, a cleaned message and the top of
  /// its [stack]. Without one, an [Error]'s own is used, and failing that
  /// where this was called from, which is where it was caught. Nothing is
  /// printed in a release build, and nothing is written before this
  /// returns.
  void record(String what, Object error, [StackTrace? stack]) {
    if (!kReleaseMode) debugPrint('$what: $error');
    final words = '$what：${describe(error)}';
    final where = frames(
      stack ?? (error is Error ? error.stackTrace : null) ?? StackTrace.current,
    );
    final last = _problems.isEmpty ? null : _problems.last;
    if (last != null && last.same(words, where)) {
      // The same again, as from a screen that fails each time it is
      // drawn: counted, not kept anew, so it does not push the others out.
      last.times++;
      _repeated = true;
    } else {
      _writeTimes();
      final problem = _Problem(AppClock.now(), words, where);
      _problems.add(problem);
      if (_log != null) _pending.add(_line(problem));
      _trim();
    }
    if (_log == null || _noting) return;
    _timer ??= Timer(flushDelay, () => unawaited(flush()));
  }

  /// Puts how often the last problem happened among the lines to write.
  void _writeTimes() {
    if (!_repeated || _problems.isEmpty) return;
    _repeated = false;
    if (_log == null) return;
    final last = _problems.last;
    _pending.add(
      jsonEncode({_at: AppClock.now().toIso8601String(), _times: last.times}),
    );
  }

  /// Writes what waits in memory to the file now, as when the app is
  /// left. Done when it is written, or could not be.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    return _writing = _writing.then((_) => _write());
  }

  Future<void> _write() async {
    final log = _log;
    if (log == null) return;
    _writeTimes();
    if (_pending.isEmpty) return;
    final lines = List.of(_pending);
    _pending.clear();
    try {
      var size = _size ?? (await log.exists() ? await log.length() : 0);
      var text = [for (final line in lines) '$line\n'].join();
      if (size > 0 && size + utf8.encode(text).length > maxFileBytes) {
        await log.rename(_aside(log).path);
        size = 0;
      } else if (_cutShort) {
        text = '\n$text';
      }
      final bytes = utf8.encode(text);
      await log.writeAsBytes(bytes, mode: FileMode.append, flush: true);
      // Only when the file is still the one written to.
      if (identical(log, _log)) {
        _size = size + bytes.length;
        _cutShort = false;
      }
    } on Object catch (error) {
      // Kept in memory; the next problem's write takes these with it.
      if (!identical(log, _log)) return;
      _pending.insertAll(0, lines);
      _size = null;
      _noting = true;
      record(ErrorSteps.logFile, error);
      _noting = false;
    }
  }

  /// The problems kept, newest first: when, and what with its error.
  List<(DateTime, String)> get entries => [
    for (final p in _problems.reversed) (p.at, p.shown),
  ];

  /// How many problems are kept.
  int get count => _problems.length;

  /// Each problem kept, newest first, to export: one line of when and
  /// what, then its stack frames, indented. Everything recorded so far is
  /// here, written to the file yet or not.
  String get text => [
    for (final p in _problems.reversed) ...[
      '${p.at.toIso8601String()}  ${p.shown}',
      for (final frame in p.frames) '    $frame',
    ],
  ].join('\n');
}
