import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core/time/utc_days.dart';
import 'package:vault/backup_security.dart' show FileBox;

import '../../../core/diagnostics/error_log.dart';
import '../../../core/diagnostics/error_steps.dart';
import '../../../core/formatting/json_fields.dart';

/// One stock's finished months of daily closes, by `yyyy-mm`, and whether
/// it is traded over the counter (TPEx).
typedef CodeMonths = ({bool otc, Map<String, List<(DateTime, double)>> months});

/// The finished months of daily closes kept on the phone for the charts,
/// in one file sealed with the ledger's key ([FileBox.prices]): which
/// stocks a chart was opened for, and since when, says what the ledger
/// holds, so neither the codes nor the months are left in the clear.
///
/// A file this ledger's key does not open (another ledger's after a
/// restore, or the old keys' after a reset) or that is damaged is taken
/// away when first read ([settle] as the ledger opens); its months are
/// fetched again.
final class PriceMonths {
  PriceMonths(this.directory, this._box);

  /// The ledger's directory.
  final Directory directory;
  final FileBox _box;

  /// The sealed file's name, also bound into its sealing.
  static const name = 'prices.sealed';

  File get _file => File('${directory.path}/$name');

  /// Where versions before the file was sealed kept one plain file per
  /// stock code, named by it.
  Directory get _plain => Directory('${directory.path}/prices');

  /// What [read] found, read once a run.
  Future<Map<String, CodeMonths>>? _read;

  /// The [write]s, one after another.
  Future<void> _writing = Future.value();

  /// As the ledger opens: takes away the plain folder of older versions,
  /// and a sealed file this ledger's key does not open.
  Future<void> settle() async {
    try {
      if (_plain.existsSync()) await _plain.delete(recursive: true);
    } on Object catch (error, stack) {
      ErrorLog.instance.record(ErrorSteps.priceHistory, error, stack);
    }
    await read();
  }

  /// Every stock's months kept; none when there is no file, or one that
  /// does not open, which is then deleted.
  Future<Map<String, CodeMonths>> read() => _read ??= _open();

  Future<Map<String, CodeMonths>> _open() async {
    final file = _file;
    if (!file.existsSync()) return {};
    try {
      final plain = await _box.open(name, await file.readAsBytes());
      final json = JsonFields.decode(utf8.decode(plain));
      final codes = json.need<Map<String, Object?>>('codes');
      return {
        for (final MapEntry(:key, :value) in codes.entries)
          key: _code(JsonFields.of(value)),
      };
    } on Object catch (error, stack) {
      // Not this ledger's key, or damaged: fetched again.
      ErrorLog.instance.record(ErrorSteps.priceHistory, error, stack);
      try {
        await file.delete();
      } on Object catch (error, stack) {
        ErrorLog.instance.record(ErrorSteps.priceHistory, error, stack);
      }
      return {};
    }
  }

  static CodeMonths _code(JsonFields json) {
    final months = json.need<Map<String, Object?>>('months');
    return (
      otc: json.flag('otc') ?? false,
      months: {
        for (final MapEntry(:key, :value) in months.entries)
          key: [
            for (final row in value is List ? value : const [])
              if (row case [final String day, final num close])
                // UTC midnight, as fetched closes are: a day read back
                // otherwise is local, and neither a buy's day nor the
                // span's first day would match it.
                (dayOf(DateTime.parse(day)), close.toDouble())
              else
                throw const FormatException('A close is a day and a price'),
          ],
      },
    );
  }

  /// Keeps [codes], all of them, sealed: written beside, then renamed
  /// over, so a cut-short write leaves the last whole one. A failure is
  /// noted; the months stay in memory for this run.
  Future<void> write(Map<String, CodeMonths> codes) =>
      _writing = _writing.then((_) => _write(codes));

  Future<void> _write(Map<String, CodeMonths> codes) async {
    final file = _file;
    final next = File('${file.path}.${Random.secure().nextInt(1 << 30)}.new');
    try {
      final plain = utf8.encode(
        jsonEncode({
          'codes': {
            for (final MapEntry(:key, :value) in codes.entries)
              key: {
                'otc': value.otc,
                'months': {
                  for (final MapEntry(:key, :value) in value.months.entries)
                    key: [
                      for (final (day, price) in value)
                        [day.toIso8601String().substring(0, 10), price],
                    ],
                },
              },
          },
        }),
      );
      await directory.create(recursive: true);
      await next.writeAsBytes(await _box.seal(name, plain), flush: true);
      await next.rename(file.path);
    } on Object catch (error, stack) {
      ErrorLog.instance.record(ErrorSteps.priceHistory, error, stack);
      try {
        if (next.existsSync()) await next.delete();
      } on Object catch (error, stack) {
        ErrorLog.instance.record(ErrorSteps.priceHistory, error, stack);
      }
    }
  }
}
