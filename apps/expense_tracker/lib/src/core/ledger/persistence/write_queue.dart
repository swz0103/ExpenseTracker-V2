// Exception to ledger words: the diagnostics log is labelled in words.

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../diagnostics/error_log.dart';
import '../ledger.dart';
import 'ledger_data_source.dart';

/// Hands each change of the ledger to the [LedgerDataSource] in the order it
/// was made, one after another. The ledger changes itself first, so the
/// screens answer at once; when a change cannot be kept, it is reported
/// through [problem], and once nothing else waits the book is read back
/// and taken up again, so the screens show what was kept.
final class WriteQueue {
  WriteQueue(
    this._dataSource, {
    required this.problem,
    required this._onReloaded,
  });

  final LedgerDataSource _dataSource;
  final void Function(Ledger fresh) _onReloaded;

  /// The last change the data source refused, for the screens to report.
  final ValueNotifier<LedgerProblem?> problem;

  var _chain = Future<void>.value();
  var _waiting = 0;

  /// Whether a refused change left the screens ahead of the data source.
  var _stale = false;

  /// Done once every change so far has reached the data source.
  Future<void> get settled => _chain;

  /// How many changes the data source refused so far: unchanged across a
  /// wait for [settled] means every change made before it was kept.
  int get refused => _refused;
  var _refused = 0;

  /// Keeps [batch] after every change before it. An empty one is not sent.
  void enqueue(WriteBatch batch) {
    if (batch.isEmpty) return;
    _waiting++;
    _chain = _chain.then((_) => _keep(batch));
  }

  Future<void> _keep(WriteBatch batch) async {
    try {
      await _dataSource.keep(batch);
    } on Object catch (error) {
      ErrorLog.instance.record('寫入帳本', error);
      _refused++;
      problem.value = KeepFailed(error);
      _stale = true;
    }
    if (--_waiting > 0 || !_stale) return;
    _stale = false;
    try {
      final fresh = await _dataSource.load();
      // A change made while loading is newer than what was loaded: this
      // load is dropped, and the screens are still ahead of the data
      // source, so the load after that change brings both.
      if (_waiting == 0) {
        _onReloaded(fresh);
      } else {
        _stale = true;
      }
    } on Object catch (error) {
      ErrorLog.instance.record('重新讀取帳本', error);
      problem.value = ReloadFailed(error);
      _stale = true;
    }
  }
}
