import '../ledger.dart';
import 'write_batch.dart';
import '../../diagnostics/app_fault.dart';

export 'write_batch.dart';

/// Where the book is kept between launches. The [Ledger] changes itself
/// first, so the screens answer at once, then hands each change here as a
/// [WriteBatch]; when one cannot be kept it reads back what was.
abstract interface class LedgerDataSource {
  /// Everything kept, as a ledger for the screens.
  Future<Ledger> load();

  /// Keeps every record of [batch] and forgets the dropped ones, all
  /// together or, when this throws, none of them.
  Future<void> keep(WriteBatch batch);
}

/// The [LedgerDataSource] could not keep a change: its file is closed, locked or
/// cannot be written.
final class DataSourceException implements CarriedFault {
  const DataSourceException(this.cause);

  @override
  final Object cause;

  @override
  String toString() => 'DataSourceException($cause)';
}
