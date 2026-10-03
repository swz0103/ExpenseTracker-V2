import 'dart:convert';
import 'dart:io';

import 'package:architecture_checks/check.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Map<String, Object> modules;
  late Map<String, Object> runtimeModules;
  void write(String path, String text) {
    final file = File(p.join(root.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  void policy() => write(
    'architecture/boundaries.json',
    jsonEncode({
      'version': 1,
      'sdkLibraries': ['dart:core', 'dart:math'],
      'modules': modules,
      'runtimeModules': runtimeModules,
    }),
  );
  void package(
    String directory,
    String name, {
    Map<String, Object> dependencies = const {},
  }) {
    write(
      '$directory/pubspec.yaml',
      jsonEncode({'name': name, 'dependencies': dependencies}),
    );
    write('$directory/lib/$name.dart', '');
  }

  Set<String> codes() => checkWorkspace(root).map((e) => e.code).toSet();
  setUp(() {
    root = Directory.systemTemp.createTempSync('expense-architecture-');
    modules = {
      'values': {
        'directory': 'packages/values',
        'publicEntrypoints': ['values.dart'],
        'dependencies': <String>[],
      },
      'ledger': {
        'directory': 'packages/ledger',
        'publicEntrypoints': ['ledger.dart'],
        'dependencies': ['values'],
      },
    };
    runtimeModules = {
      'app': {
        'directory': 'prototypes/app',
        'dependencies': ['ledger'],
      },
    };
    package('packages/values', 'values');
    package(
      'packages/ledger',
      'ledger',
      dependencies: {
        'values': {'path': '../values'},
      },
    );
    package(
      'prototypes/app',
      'app',
      dependencies: {
        'ledger': {'path': '../../packages/ledger'},
      },
    );
    write(
      'packages/ledger/lib/ledger.dart',
      "import 'package:values/values.dart';",
    );
    policy();
  });
  tearDown(() {
    final actual = root.resolveSymbolicLinksSync();
    final parent = Directory.systemTemp.resolveSymbolicLinksSync();
    if (!p.isWithin(parent, actual) ||
        !p.basename(actual).startsWith('expense-architecture-')) {
      throw StateError('Unsafe test cleanup');
    }
    root.deleteSync(recursive: true);
  });
  test('public dependency direction and own internal exports pass', () {
    write('packages/values/lib/values.dart', "export 'src/value.dart';");
    write('packages/values/lib/src/value.dart', 'class Value {}');
    write(
      'prototypes/app/lib/app.dart',
      "import 'package:ledger/ledger.dart';",
    );
    expect(checkWorkspace(root), isEmpty);
  });
  test('runtime storage dependency is rejected even when not yet imported', () {
    package('packages/ledger', 'ledger', dependencies: {'sqlite3': '3.6.0'});
    expect(codes(), contains('forbidden-dependency'));
  });
  test('conditional import and export check every branch', () {
    write(
      'packages/values/lib/values.dart',
      "import 'dart:math' if (dart.library.io) 'dart:io';\nexport 'dart:core' if (dart.library.ui) 'dart:ui';",
    );
    final issues = checkWorkspace(root)
        .where((e) => e.code == 'platform-dependency')
        .toList();
    expect(issues.length, 2);
    expect(issues.map((e) => e.line), [1, 2]);
  });
  test('only a module that declares an extra SDK library may import it', () {
    (modules['values']! as Map)['extraSdkLibraries'] = ['dart:io'];
    policy();
    write('packages/values/lib/values.dart', "import 'dart:io';");
    write('packages/ledger/lib/ledger.dart', "import 'dart:io';");
    final issues = checkWorkspace(root)
        .where((e) => e.code == 'platform-dependency')
        .toList();
    expect(issues, hasLength(1));
    expect(p.basename(issues.single.path), 'ledger.dart');
  });
  test(
    'consumer cannot import a business implementation or undocumented entry',
    () {
      write(
        'prototypes/app/lib/app.dart',
        "import 'package:values/src/value.dart';\nexport 'package:ledger/helper.dart';",
      );
      expect(
        checkWorkspace(root).where((e) => e.code == 'private-import').length,
        2,
      );
    },
  );
  test('comments and literal text do not create false import violations', () {
    write('packages/values/lib/values.dart', r'''
// import 'dart:io';
/* export 'package:ledger/src/private.dart'; */
const text = "import 'dart:ui';";
''');
    expect(checkWorkspace(root), isEmpty);
  });
  test('relative imports and part directives cannot escape package', () {
    write(
      'packages/ledger/lib/ledger.dart',
      "import '../../values/lib/src/value.dart';\npart '../../values/lib/piece.dart';",
    );
    expect(
      checkWorkspace(root).where((e) => e.code == 'relative-escape').length,
      2,
    );
  });
  test('part-of and lib-to-test references cannot bypass public APIs', () {
    write(
      'packages/values/lib/piece.dart',
      "part of '../../ledger/lib/ledger.dart';",
    );
    write('packages/ledger/lib/ledger.dart', "import '../test/helper.dart';");
    expect(
      checkWorkspace(root).where((e) => e.code == 'relative-escape').length,
      2,
    );
  });
  test('undeclared and development-only imports are rejected in Domain', () {
    write(
      'packages/ledger/lib/ledger.dart',
      "import 'package:test/test.dart';",
    );
    expect(codes(), contains('undeclared-import'));
  });
  test('policy cannot permit an actual business dependency cycle', () {
    (modules['values'] as Map)['dependencies'] = ['ledger'];
    package(
      'packages/values',
      'values',
      dependencies: {
        'ledger': {'path': '../ledger'},
      },
    );
    policy();
    expect(codes(), contains('dependency-cycle'));
  });
  test('new business module cannot silently skip registration', () {
    package('packages/new_feature', 'new_feature');
    expect(codes(), contains('unregistered-module'));
  });
  test('new runtime package cannot silently skip registration', () {
    package('prototypes/new_feature', 'new_feature');
    expect(codes(), contains('unregistered-runtime'));
  });
  test('new infrastructure package cannot skip registration', () {
    package('infrastructure/new_adapter', 'new_adapter');
    expect(codes(), contains('unregistered-runtime'));
  });
  test('new app cannot skip registration', () {
    package('apps/new_app', 'new_app');
    expect(codes(), contains('unregistered-runtime'));
  });
  test('runtime cannot add an unapproved local dependency', () {
    package('prototypes/storage', 'storage');
    runtimeModules['storage'] = {
      'directory': 'prototypes/storage',
      'dependencies': <String>[],
    };
    package(
      'prototypes/app',
      'app',
      dependencies: {
        'storage': {'path': '../storage'},
      },
    );
    policy();
    expect(codes(), contains('forbidden-dependency'));
  });
  test('runtime cannot import an unlisted local package', () {
    write(
      'prototypes/app/lib/app.dart',
      "import 'package:values/values.dart';",
    );
    expect(codes(), contains('undeclared-import'));
  });
  test('runtime cannot point a local dependency at a different package', () {
    package(
      'prototypes/app',
      'app',
      dependencies: {
        'ledger': {'path': '../../packages/values'},
      },
    );
    expect(codes(), contains('dependency-location'));
  });
  test('runtime cycle is rejected across prototype packages', () {
    package(
      'prototypes/storage',
      'storage',
      dependencies: {
        'app': {'path': '../app'},
      },
    );
    runtimeModules['storage'] = {
      'directory': 'prototypes/storage',
      'dependencies': ['app'],
    };
    (runtimeModules['app'] as Map)['dependencies'] = ['storage'];
    package(
      'prototypes/app',
      'app',
      dependencies: {
        'storage': {'path': '../storage'},
      },
    );
    policy();
    expect(codes(), contains('dependency-cycle'));
  });
  test(
    'registered local dependency cannot resolve to another implementation',
    () {
      package(
        'packages/ledger',
        'ledger',
        dependencies: {
          'values': {'path': '../../prototypes/app'},
        },
      );
      expect(codes(), contains('dependency-location'));
    },
  );
  test('dependency overrides and missing public entrypoint fail', () {
    write('packages/ledger/pubspec_overrides.yaml', 'dependency_overrides: {}');
    File(p.join(root.path, 'packages/values/lib/values.dart')).deleteSync();
    expect(codes(), containsAll(['dependency-override', 'public-entrypoint']));
  });
  test('malformed Dart and escaped package URIs are rejected', () {
    write(
      'packages/ledger/lib/ledger.dart',
      "import 'package:values/../ledger/private.dart';",
    );
    write('packages/values/lib/values.dart', 'import ;');
    expect(codes(), containsAll(['invalid-uri', 'invalid-dart']));
  });
  test('unknown policy version fails instead of disabling the gate', () {
    write(
      'architecture/boundaries.json',
      jsonEncode({'version': 2, 'modules': modules, 'sdkLibraries': []}),
    );
    expect(() => checkWorkspace(root), throwsFormatException);
  });
  test(
    'encoded package escapes and unchecked relative helpers are rejected',
    () {
      write(
        'packages/ledger/lib/ledger.dart',
        "import 'package:values/%2e%2e/ledger/private.dart';",
      );
      write('prototypes/app/lib/app.dart', "import '../hidden.dart';");
      expect(codes(), containsAll(['invalid-uri', 'relative-escape']));
    },
  );
}
