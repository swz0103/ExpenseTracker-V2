import 'dart:async';

import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/intents.dart';
import 'package:ledger_postings/model/vocabulary.dart';

import '../../diagnostics/error_log.dart';
import '../../diagnostics/error_steps.dart';
import '../journal/book_mapping.dart';
import '../journal/parity.dart';
import '../journal/replay.dart';
import '../ledger.dart';
import '../repositories/holding_repository.dart';
import 'write_batch.dart';

/// The version of the posting rules. Postings an older version posted are
/// posted afresh when the book opens: raise it when a rule changes what a
/// record posts.
const journalRules = 1;

// Exception to the motion scale: a slice of work, not a movement.
/// How long the journal's work in the background runs before it lets the
/// screen draw: half a frame at 60 Hz.
const journalSlice = Duration(milliseconds: 8);

/// How many intents one transaction posts when the whole book is posted
/// afresh: about 12 ms of a desktop's time (journal bench), so the screen
/// is drawn between them on a phone too, at a few more commits.
const journalChunk = 100;

/// Keeps the journal of postings beside the records, and checks it. When
/// the book opens, its postings are posted afresh unless they are the
/// records' own (the store's mark: this [journalRules] and the records'
/// revision); after each change kept, the changed records are posted;
/// then, in the background, the journal's sums are compared with the
/// figures the app shows. A difference is kept in the diagnostics log,
/// never shown and never in the way: nothing the person sees reads the
/// journal yet.
final class JournalKeeper {
  JournalKeeper({
    required this._store,
    required this._revision,
    required this._entrySeqs,
    required this._recordOf,
    required this._isOpen,
    this._busy = _never,
    this._quiet = _now,
    this._postApart,
    this.compares = true,
  });

  final PostingStore _store;

  /// The records' revision now.
  final int Function() _revision;

  /// Where each entry kept stands, by id: the order the records keep.
  final Map<String, int> Function() _entrySeqs;

  /// The entry kept under an id, with its place, read from the records.
  final KeptEntry? Function(String id) _recordOf;

  /// Whether the store can still be read and written: work left when the
  /// book is closed is let go.
  final bool Function() _isOpen;

  /// Whether another isolate uses the records' connection now (a write
  /// or a read apart, a posting afresh): the journal shares it, so it
  /// never posts, reads or compares while one does.
  final bool Function() _busy;

  /// Done once no other isolate uses the connection; [_busy] is asked
  /// again after, since another may have taken it meanwhile.
  final Future<void> Function() _quiet;

  static bool _never() => false;
  static Future<void> _now() async {}

  /// Posts the whole book afresh off this isolate, from the records as
  /// kept, given the stocks held from the start, and keeps the mark of
  /// the records' revision last; none (tests in memory) posts it here.
  final Future<ReplayReport> Function(List<Holding> start)? _postApart;

  /// Whether the journal is compared with the figures the app shows
  /// after it changes: as the app keeps it; a bench timing the posting
  /// alone leaves it out.
  final bool compares;

  var _chain = Future<void>.value();
  var _queued = 0;
  Ledger? _ledger;
  Journal? _journal;
  late BookMapping _mapping;
  final _accounts = <String, Account>{};
  final _categories = <String, Category>{};
  List<Holding> _start = const [];
  ParityScope? _wanted;
  var _checking = false;

  /// What the last comparison found; null before one finished.
  Parity? get lastParity => _last;
  Parity? _last;

  /// What the last posting afresh found; null when the book opened with
  /// its postings up to date.
  ReplayReport? get lastReplay => _replay;
  ReplayReport? _replay;

  /// Done once everything asked so far is done, and what that asked in
  /// turn (a comparison after a change).
  Future<void> get settled async {
    for (;;) {
      final waiting = _chain;
      await waiting;
      if (identical(waiting, _chain)) return;
    }
  }

  /// The journal's sums, as the comparison reads them.
  BookReader get reader =>
      BookReader(_store, _journal!.accounts, Contributions(), homeCurrency);

  /// Takes up [ledger], just opened: posts the book afresh when its
  /// postings are not the records' own, then compares everything.
  void open(Ledger ledger) =>
      _then(() => _open(ledger), _wantAll, ErrorSteps.journalUpdate);

  /// Brings the journal up to date with [batch], just kept.
  void kept(WriteBatch batch) {
    if (batch.onlyDrafts || batch.isEmpty) return;
    final revision = _revision();
    _then(
      () async => _apply(batch, revision),
      () => _want(_scopeOf(batch)),
      ErrorSteps.journalUpdate,
    );
  }

  /// Runs [step] after what is queued, then asks for a check; a fault is
  /// kept in the log as [what], and leaves the journal to be posted
  /// afresh at the next opening (its mark is not moved).
  void _then(Future<void> Function() step, void Function() then, String what) {
    _queued++;
    _chain = _chain.then((_) async {
      try {
        while (_blocked) {
          await _quiet();
        }
        await step();
        then();
      } on Object catch (error, stack) {
        // The book closed (locked, left): what was left is let go, the
        // mark not moved, so it is posted afresh at the next opening.
        if (error is! _Closed) ErrorLog.instance.record(what, error, stack);
      } finally {
        _queued--;
      }
      _checkWhenIdle();
    });
  }

  Future<void> _open(Ledger ledger) async {
    _ledger = ledger;
    _accounts
      ..clear()
      ..addEntries(ledger.accounts.all.map((a) => MapEntry(a.id, a)));
    _categories
      ..clear()
      ..addEntries(ledger.categories.all.map((c) => MapEntry(c.id, c)));
    _start = (ledger.holdings as HoldingRepository).start;
    _remap();
    final tree = AccountTree([..._store.accounts(), ..._mapping.tree]);
    _journal = Journal(
      registry: registryFor(() => _mapping),
      accounts: tree,
      store: _store,
      source: (id) => switch (_recordOf(id.value)) {
        final kept? => _mapping.map(kept.entry, kept.seq).intent,
        null => null,
      },
    );
    final revision = _revision();
    if (_store.mark != (rules: journalRules, revision: revision)) {
      await _rebuild(revision);
    }
  }

  void _remap() => _mapping = BookMapping(
    accounts: _accounts.values,
    categories: _categories.values,
    start: _start,
  );

  /// Posts the whole book afresh, as of [revision]: off this isolate when
  /// the store can ([_postApart]), the tree then read back; else here,
  /// from the records as the ledger holds them.
  Future<void> _rebuild(int revision) async {
    final apart = _postApart;
    if (apart != null) {
      while (_blocked) {
        await _quiet();
      }
      _replay = await apart(_start);
      while (_blocked) {
        await _quiet();
      }
      _store.accounts().forEach(_journal!.accounts.put);
      _noteRounded();
      return;
    }
    final ledger = _ledger!;
    final seqs = _entrySeqs();
    _replay = await replayBook(
      mapping: _mapping,
      journal: _journal!,
      store: _store,
      entries: [
        for (final e in ledger.entries.all)
          if (seqs[e.id] case final seq?) (entry: e, seq: seq),
      ],
      chunk: journalChunk,
      pause: _slicer(),
    );
    _store.transaction(
      () => _store.keepMark((rules: journalRules, revision: revision)),
    );
    _noteRounded();
  }

  /// Tells the diagnostics log, once per posting afresh, that quantities
  /// finer than a millionth of a share were rounded (decision D48): how
  /// often is kept in the report, never an amount.
  void _noteRounded() {
    if ((_replay?.rounded ?? 0) == 0) return;
    ErrorLog.instance.record(
      ErrorSteps.journalUpdate,
      StateError('lot quantities rounded to a millionth of a share'),
    );
  }

  /// Brings the journal up to date with [batch], kept as of [revision].
  Future<void> _apply(WriteBatch batch, int revision) async {
    final journal = _journal;
    if (journal == null) return;
    final streams = <String>{};
    final gone = <IntentId>[];
    final intents = <LedgerIntent>[];
    final records = <IntentId, Entry>{};
    var remap = batch.categories.isNotEmpty;
    for (final a in batch.accounts) {
      final was = _accounts[a.id];
      _accounts[a.id] = a;
      remap = true;
      if (was != null && !_sameSchedule(was, a)) {
        streams.add(Streams.instalments(moneyAccount(a.id)));
      }
      if (was?.opening != a.opening) {
        if (a.opening != 0) {
          intents.add(
            OpeningBalance(
              id: BookMapping.openingId(a.id),
              seq: 0,
              account: moneyAccount(a.id),
              amount: a.opening,
            ),
          );
        } else if (was != null) {
          gone.add(BookMapping.openingId(a.id));
        }
      }
    }
    for (final c in batch.categories) {
      _categories[c.id] = c;
    }
    for (final (collection, key) in batch.dropped) {
      switch (collection) {
        case Collection.entry:
          gone.add(IntentId(key));
        case Collection.account:
          if (_accounts.remove(key) != null) {
            gone.add(BookMapping.openingId(key));
            remap = true;
          }
        case Collection.category:
          remap |= _categories.remove(key) != null;
        case _:
          break;
      }
    }
    if (remap) {
      _remap();
      _mapping.tree.forEach(journal.accounts.put);
    }
    for (final e in batch.entries) {
      final seq = _recordOf(e.id)?.seq;
      if (seq == null) continue; // taken away by a later change, kept since
      final mapped = _mapping.map(e, seq);
      mapped.accounts.forEach(journal.accounts.put);
      intents.add(mapped.intent);
      records[mapped.intent.id] = e;
    }
    void mark() {
      _store.keepAccounts(journal.accounts.all);
      _store.keepMark((rules: journalRules, revision: revision));
    }

    var sound = true;
    for (final id in gone) {
      final r = journal.delete(id);
      sound &= r is Written || r is IntentNotFound;
    }
    for (final stream in streams) {
      sound &= journal.rematerialise(stream) is Written;
    }
    while (sound) {
      final r = journal.putAll(intents, also: mark);
      if (r is Written) break;
      final refused = r as JournalRefusal;
      final at = intents.indexWhere((i) => i.id == refused.intent);
      final entry = records[refused.intent];
      // An old sale oversold when it is written again: posted as its
      // holdings read it today, as when the book is posted afresh.
      if (at >= 0 &&
          entry != null &&
          refused is RuleRejected &&
          refused.code == Refusals.oversold &&
          intents[at] is! OutOfHoldings) {
        intents[at] = _mapping.outOfHoldings(entry, intents[at]);
        continue;
      }
      sound = false;
    }
    // A change the journal could not take as it is (a later trade of its
    // stock refused): the whole book is posted afresh.
    if (!sound) await _rebuild(revision);
  }

  static bool _sameSchedule(Account a, Account b) =>
      a.closingDay == b.closingDay &&
      a.dueDay == b.dueDay &&
      _sameCloses(a.closes, b.closes) &&
      _sameHistory(a, b);

  static bool _sameCloses(
    Map<DateTime, DateTime> a,
    Map<DateTime, DateTime> b,
  ) => a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  static bool _sameHistory(Account a, Account b) {
    if (a.history.length != b.history.length) return false;
    for (final (i, h) in a.history.indexed) {
      final o = b.history[i];
      if (h.until != o.until ||
          h.closingDay != o.closingDay ||
          h.dueDay != o.dueDay) {
        return false;
      }
    }
    return true;
  }

  /// The accounts, months and stocks [batch] touched.
  static ParityScope _scopeOf(WriteBatch batch) {
    final accounts = <String>{for (final a in batch.accounts) a.id};
    final months = <int>{};
    final codes = <String>{};
    for (final e in batch.entries) {
      accounts.add(e.account);
      if (e.to case final to?) accounts.add(to);
      months.add(e.date.year * 100 + e.date.month);
      if (e.holding case final code?) codes.add(code);
    }
    // A record taken away: its accounts, month and stock are not known
    // here any more, so all of them are compared.
    final dropped = batch.dropped.any(
      (d) => d.$1 == Collection.entry || d.$1 == Collection.account,
    );
    return dropped || batch.categories.isNotEmpty
        ? everything
        : (accounts: accounts, months: months, codes: codes);
  }

  void _wantAll() => _want(everything);

  void _want(ParityScope scope) {
    final was = _wanted;
    Set<T>? both<T>(Set<T>? a, Set<T>? b) =>
        a == null || b == null ? null : {...a, ...b};
    _wanted = was == null
        ? scope
        : (
            accounts: both(was.accounts, scope.accounts),
            months: both(was.months, scope.months),
            codes: both(was.codes, scope.codes),
          );
  }

  /// Compares once nothing else is queued and the ledger's own writes
  /// have all been kept, so both sides say the same book.
  void _checkWhenIdle() {
    if (!compares || _queued > 0 || _checking || _wanted == null) return;
    _checking = true;
    _queued++;
    _chain = _chain.then((_) async {
      try {
        await _check();
      } on Object catch (error, stack) {
        // Closed under it: compared again after the next opening.
        if (error is! _Closed) {
          ErrorLog.instance.record(ErrorSteps.journalParity, error, stack);
        }
      } finally {
        _queued--;
        _checking = false;
      }
    });
  }

  Future<void> _check() async {
    final ledger = _ledger;
    final scope = _wanted;
    if (ledger == null || scope == null) return;
    await ledger.settled;
    while (_blocked) {
      await _quiet();
    }
    if (_queued > 1) return; // more changes to take first; they ask again
    _wanted = null;
    final revision = ledger.revision;
    final parity = await checkParity(
      today: (
        day: ledger.today,
        entries: ledger.entries,
        accounts: ledger.accounts,
        holdings: ledger.holdings,
        balances: ledger.balanceService,
        reports: ledger.reportService,
        statements: ledger.statementService,
      ),
      reader: reader,
      scope: scope,
      shapes: _replay?.shapes ?? const {},
      unposted: _replay?.unposted ?? const [],
      pause: _slicer(),
    );
    if (ledger.revision != revision || !_isOpen()) {
      // The book changed while it was compared: compared again once that
      // change is kept.
      _want(scope);
      return;
    }
    _last = parity;
    if (parity is OutOfParity) {
      final figures = {for (final d in parity.differences) d.figure.name};
      ErrorLog.instance.record(
        ErrorSteps.journalParity,
        StateError('figures differ: ${figures.join(', ')}'),
      );
    }
  }

  /// A pause that lets the screen draw once [journalSlice] has passed
  /// since the last one, and otherwise none.
  ///
  /// After any pause the store is ready again ([_blocked]) before the work
  /// goes on: no write apart running, the book not closing.
  Future<void> Function() _slicer() {
    final watch = Stopwatch()..start();
    return () async {
      if (watch.elapsed < journalSlice) return;
      await Future<void>.delayed(Duration.zero);
      while (_blocked) {
        await _quiet();
      }
      watch.reset();
    };
  }

  /// Whether another isolate uses the store now; throws [_Closed] once
  /// the book is closing or closed. Asked in a loop, `while (_blocked)
  /// await _quiet();`, so that what follows the loop, up to the next
  /// await, has the store to itself: the check and the work run with
  /// nothing else on this isolate in between (a backup waiting for the
  /// same moment may take the store first; then this waits again).
  bool get _blocked {
    if (!_isOpen()) throw const _Closed();
    return _busy();
  }
}

/// The book closed under the journal's work in the background.
final class _Closed implements Exception {
  const _Closed();
}
