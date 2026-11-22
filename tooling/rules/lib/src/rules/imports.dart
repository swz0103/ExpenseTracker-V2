import '../config.dart';
import '../engine.dart';
import 'calls.dart';

/// The feature a file of the app belongs to, or null.
String? featureOf(String path) {
  const prefix = '$featuresDir/';
  if (!path.startsWith(prefix)) return null;
  final rest = path.substring(prefix.length);
  final slash = rest.indexOf('/');
  return slash < 0 ? null : rest.substring(0, slash);
}

/// A2: a feature does not reach into another feature; what two features
/// share goes to a lower layer.
///
/// Known noise: exports count as imports; a feature file that re-exports
/// a sibling feature's barrel is flagged.
final class FeatureIsolation extends FileRule {
  const FeatureIsolation();

  @override
  String get id => 'A2-feature-isolation';

  @override
  String get purpose => 'a feature imports a file of another feature';

  @override
  bool appliesTo(SourceFile file) => featureOf(file.path) != null;

  @override
  List<Violation> checkFile(SourceFile file) {
    final own = featureOf(file.path);
    return [
      for (final (uri, line) in directiveUris(file))
        if (resolveAppImport(file.path, uri) case final target?)
          if (featureOf(target) case final other?)
            if (other != own)
              Violation(
                id,
                file.path,
                line,
                'feature $own imports $other: $uri',
              ),
    ];
  }
}

/// A3: UI code does not touch storage, vault, market or the platform
/// folder; it asks the application layer.
///
/// Known noise: a feature that only needs a data package's plain value
/// type is flagged all the same; the ratchet records it.
final class UiNoData extends FileRule {
  const UiNoData();

  @override
  String get id => 'A3-ui-no-data';

  @override
  String get purpose =>
      'a feature imports storage, vault, market or a data folder';

  @override
  bool appliesTo(SourceFile file) => file.isUnder(featuresDir);

  @override
  List<Violation> checkFile(SourceFile file) {
    final found = <Violation>[];
    for (final (uri, line) in directiveUris(file)) {
      final package = dataPackages.any((n) => uri.startsWith('package:$n/'));
      final target = resolveAppImport(file.path, uri);
      final folder = target != null && dataFolders.any(target.startsWith);
      if (package || folder) {
        found.add(Violation(id, file.path, line, 'a feature imports $uri'));
      }
    }
    return found;
  }
}

/// A4: the pure packages stay free of Flutter, the platform and hidden
/// inputs (the clock, randomness).
///
/// Known noise: `Random(seed)` with a fixed seed is deterministic and is
/// flagged anyway; the clock implementation file is the one exception
/// (see `clockFiles` in config.dart).
final class PureCalc extends FileRule {
  const PureCalc();

  @override
  String get id => 'A4-pure-calc';

  @override
  String get purpose =>
      'a pure package imports Flutter or the platform, or reads the clock or Random';

  @override
  bool appliesTo(SourceFile file) =>
      switch (purePackageOf(file.path)) {
        final pkg? => file.isUnder('$pkg/lib'),
        null => false,
      } &&
      !clockFiles.contains(file.path);

  @override
  List<Violation> checkFile(SourceFile file) {
    final found = <Violation>[];
    for (final (uri, line) in directiveUris(file)) {
      if (impurePrefixes.any(uri.startsWith)) {
        found.add(Violation(id, file.path, line, 'pure package imports $uri'));
      }
    }
    for (final call in callsIn(file)) {
      final what = isDateTimeNow(call)
          ? 'DateTime.now()'
          : call.matches(null, 'Stopwatch')
          ? 'Stopwatch()'
          : call.matches(null, 'Random') || call.matches('Random', 'secure')
          ? 'Random'
          : null;
      if (what != null) {
        found.add(
          Violation(
            id,
            file.path,
            file.lineOfNode(call.node),
            'pure package uses $what',
          ),
        );
      }
    }
    return found;
  }
}
