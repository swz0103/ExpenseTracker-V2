/// Line coverage from an lcov report, and the per-package floors it is held to
/// (tooling/coverage_floors.json; rule C5).

/// Lines hit and lines instrumented in an lcov report.
class LineCoverage {
  const LineCoverage(this.hit, this.total);

  final int hit;
  final int total;

  /// A package with no instrumented line counts as fully covered.
  double get percent => total == 0 ? 100 : hit * 100 / total;
}

/// Counts the `DA:<line>,<hits>` records of [lcov]; a line listed twice (the
/// same file merged from several runs) counts once, hit if any record hit it.
LineCoverage parseLcov(String lcov) {
  final lines = <String, Map<int, bool>>{};
  Map<int, bool>? file;
  for (final raw in lcov.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('SF:')) {
      file = lines.putIfAbsent(line.substring(3), () => {});
    } else if (line.startsWith('DA:') && file != null) {
      final parts = line.substring(3).split(',');
      if (parts.length < 2) continue;
      final number = int.tryParse(parts[0]);
      final hits = int.tryParse(parts[1]);
      if (number == null || hits == null) continue;
      file[number] = (file[number] ?? false) || hits > 0;
    } else if (line == 'end_of_record') {
      file = null;
    }
  }
  var hit = 0;
  var total = 0;
  for (final file in lines.values) {
    total += file.length;
    hit += file.values.where((h) => h).length;
  }
  return LineCoverage(hit, total);
}

/// The outcome for one package.
class FloorResult {
  const FloorResult(this.package, this.floor, this.percent);

  final String package;
  final int floor;

  /// Null when the package has no coverage report.
  final double? percent;

  bool get missing => percent == null;
  bool get belowFloor => percent != null && percent! < floor;
  bool get failed => missing || belowFloor;

  /// Coverage has grown well past the floor: it should be raised.
  bool get raiseHint => percent != null && percent! >= floor + 3;

  @override
  String toString() {
    if (missing) return '$package: no coverage report (floor $floor%)';
    final shown = percent!.toStringAsFixed(1);
    if (belowFloor) return '$package: $shown% is below the floor of $floor%';
    final base = '$package: $shown% (floor $floor%)';
    return raiseHint ? '$base - raise the floor in coverage_floors.json' : base;
  }
}

/// Compares each package's coverage in [measured] (null: no report) with its
/// [floors] entry.
List<FloorResult> checkFloors(
  Map<String, int> floors,
  Map<String, double?> measured,
) => [
  for (final entry in floors.entries)
    FloorResult(entry.key, entry.value, measured[entry.key]),
];
