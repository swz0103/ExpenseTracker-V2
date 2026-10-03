import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

final class BoundaryIssue {
  BoundaryIssue(this.code, this.path, this.line, this.message);
  final String code;
  final String path;
  final int line;
  final String message;
  @override
  String toString() => '$path:$line [$code] $message';
}

final class _Package {
  _Package(this.name, this.directory, this.spec);
  final String name;
  final String directory;
  final Map spec;
  Map get dependencies => spec['dependencies'] as Map? ?? {};
}

/// Checks direct business dependencies and every Dart directive in repository
/// package source trees. It is not a transitive dependency or security audit.
List<BoundaryIssue> checkWorkspace(Directory directory) {
  final root = directory.resolveSymbolicLinksSync();
  final policy = jsonDecode(
    File(p.join(root, 'architecture/boundaries.json')).readAsStringSync(),
  ) as Map;
  if (policy['version'] is! int ||
      policy['version'] != 1 ||
      policy['modules'] is! Map ||
      (policy.containsKey('runtimeModules') &&
          policy['runtimeModules'] is! Map) ||
      policy['sdkLibraries'] is! List) {
    throw const FormatException('Unsupported boundary policy');
  }
  final modules = (policy['modules'] as Map).cast<String, Map>();
  final runtimeModules = (policy['runtimeModules'] as Map? ?? {})
      .cast<String, Map>();
  final registered = <String, Map>{...modules, ...runtimeModules};
  if (registered.length != modules.length + runtimeModules.length) {
    throw const FormatException('Duplicate boundary module');
  }
  final sdk = (policy['sdkLibraries'] as List).cast<String>().toSet();
  final issues = <BoundaryIssue>[];
  void report(String code, String file, String message, [int line = 1]) =>
      issues.add(
        BoundaryIssue(code, p.relative(file, from: root), line, message),
      );
  final packages = <String, _Package>{};
  void discover(Directory location) {
    if (!location.existsSync()) return;
    for (final entry in location.listSync(followLinks: false)) {
      if (entry is Link) {
        report(
          'unsafe-path',
          entry.path,
          'Linked package paths are not supported.',
        );
      } else if (entry is Directory &&
          !{'.dart_tool', 'build', '.git'}.contains(p.basename(entry.path))) {
        final specFile = File(p.join(entry.path, 'pubspec.yaml'));
        if (!specFile.existsSync()) {
          discover(entry);
          continue;
        }
        final spec = loadYaml(specFile.readAsStringSync()) as Map;
        final name = spec['name'] as String;
        if (packages.containsKey(name)) {
          report(
            'duplicate-package',
            specFile.path,
            'Package name is already registered.',
          );
          continue;
        }
        packages[name] = _Package(name, entry.path, spec);
        if (p.isWithin(p.join(root, 'packages'), entry.path) &&
            !modules.containsKey(name)) {
          report(
            'unregistered-module',
            specFile.path,
            'Business package needs an explicit boundary policy.',
          );
        } else if (runtimeModules.isNotEmpty &&
            !p.isWithin(p.join(root, 'packages'), entry.path) &&
            !runtimeModules.containsKey(name)) {
          report(
            'unregistered-runtime',
            specFile.path,
            'Runtime package needs an explicit boundary policy.',
          );
        }
      }
    }
  }

  for (final folder in ['apps', 'packages', 'infrastructure', 'prototypes']) {
    final location = p.join(root, folder);
    final type = FileSystemEntity.typeSync(location, followLinks: false);
    if (type == FileSystemEntityType.notFound && folder != 'packages') {
      continue;
    }
    if (type == FileSystemEntityType.link) {
      report('unsafe-path', location, 'Linked package root is not supported.');
    } else {
      discover(Directory(location));
    }
  }
  final graph = <String, Set<String>>{};
  for (final entry in registered.entries) {
    final module = entry.value;
    final owner = packages[entry.key];
    final declaredPath = module['directory'] as String;
    if (p.isAbsolute(declaredPath) ||
        !p.isWithin(root, p.normalize(p.join(root, declaredPath)))) {
      throw const FormatException('Invalid module path');
    }
    if (owner == null ||
        !p.equals(owner.directory, p.normalize(p.join(root, declaredPath)))) {
      report(
        'module-location',
        p.join(root, declaredPath),
        'Expected package is missing or moved.',
      );
      continue;
    }
    final allowed = (module['dependencies'] as List).cast<String>().toSet();
    final deps = owner.dependencies;
    final specFile = p.join(owner.directory, 'pubspec.yaml');
    graph[owner.name] = deps.keys
        .whereType<String>()
        .where(registered.containsKey)
        .toSet();
    if (owner.spec.containsKey('dependency_overrides') ||
        File(p.join(owner.directory, 'pubspec_overrides.yaml')).existsSync()) {
      report(
        'dependency-override',
        specFile,
        'Business dependency overrides need explicit review.',
      );
    }
    for (final dependency in deps.entries) {
      if ((modules.containsKey(owner.name) ||
              registered.containsKey(dependency.key) ||
              dependency.value is Map &&
                  (dependency.value as Map).containsKey('path')) &&
          !allowed.contains(dependency.key)) {
        report(
          'forbidden-dependency',
          specFile,
          'Dependency ${dependency.key} is outside the allowed direction.',
        );
      }
      if (registered.containsKey(dependency.key)) {
        final expected = p.normalize(
          p.join(root, registered[dependency.key]!['directory'] as String),
        );
        final value = dependency.value;
        if (value is! Map ||
            value['path'] is! String ||
            !p.equals(
              p.normalize(p.join(owner.directory, value['path'] as String)),
              expected,
            )) {
          report(
            'dependency-location',
            specFile,
            'Local dependency ${dependency.key} must use its registered path.',
          );
        }
      } else if (dependency.value is Map &&
          (dependency.value as Map).containsKey('path')) {
        report(
          'dependency-location',
          specFile,
          'Unregistered local runtime dependency.',
        );
      }
    }
    for (final value in module['publicEntrypoints'] as List? ?? []) {
      final path = value as String;
      final target = p.normalize(p.join(owner.directory, 'lib', path));
      if (!p.isWithin(p.join(owner.directory, 'lib'), target) ||
          !File(target).existsSync()) {
        report(
          'public-entrypoint',
          target,
          'Declared public entrypoint is missing or outside lib.',
        );
      }
    }
  }
  final visiting = <String>{};
  final visited = <String>{};
  void visit(String name) {
    if (visiting.contains(name)) {
      report(
        'dependency-cycle',
        p.join(root, 'architecture/boundaries.json'),
        'Package dependency cycle includes $name.',
      );
      return;
    }
    if (!visited.add(name)) return;
    visiting.add(name);
    for (final next in graph[name] ?? <String>{}) {
      visit(next);
    }
    visiting.remove(name);
  }

  for (final name in graph.keys) {
    visit(name);
  }

  void inspectFile(_Package owner, File file) {
    final parsed = parseString(
      content: file.readAsStringSync(),
      path: file.path,
      throwIfDiagnostics: false,
    );
    if (parsed.errors.isNotEmpty) {
      report(
        'invalid-dart',
        file.path,
        'Syntax errors prevent reliable directive checks.',
      );
      return;
    }
    final production =
        modules.containsKey(owner.name) &&
        p.isWithin(p.join(owner.directory, 'lib'), file.path);
    final runtimeProduction =
        runtimeModules.containsKey(owner.name) &&
        p.isWithin(p.join(owner.directory, 'lib'), file.path);
    void inspectUri(StringLiteral literal) {
      final line = parsed.lineInfo.getLocation(literal.offset).lineNumber;
      final text = literal.stringValue;
      if (text == null) {
        report(
          'invalid-uri',
          file.path,
          'Directive must use a static URI.',
          line,
        );
        return;
      }
      final uri = Uri.tryParse(text);
      if (uri == null || uri.hasQuery || uri.hasFragment || uri.hasAuthority) {
        report('invalid-uri', file.path, 'Unsupported directive URI.', line);
        return;
      }
      if (uri.scheme == 'dart') {
        final extra =
            (modules[owner.name]?['extraSdkLibraries'] as List?) ?? const [];
        if (production && !sdk.contains(text) && !extra.contains(text))
          report(
            'platform-dependency',
            file.path,
            'Domain cannot depend on $text.',
            line,
          );
        return;
      }
      if (uri.scheme == 'package') {
        // Uri.parse normalizes dot segments. Reject the original spelling first.
        final original = Uri.decodeComponent(
          text.substring(text.indexOf(':') + 1),
        ).split('/');
        if (original.any(
          (part) => part == '.' || part == '..' || part.contains('\\'),
        )) {
          report(
            'invalid-uri',
            file.path,
            'Package URI cannot escape its library.',
            line,
          );
          return;
        }
        final parts = uri.pathSegments;
        if (parts.length < 2 ||
            parts.any(
              (part) =>
                  part.isEmpty ||
                  part == '..' ||
                  part == '.' ||
                  part.contains('\\'),
            )) {
          report(
            'invalid-uri',
            file.path,
            'Package URI cannot escape its library.',
            line,
          );
          return;
        }
        final targetName = parts.first;
        final library = parts.skip(1).join('/');
        if (targetName != owner.name &&
            modules.containsKey(targetName) &&
            !(modules[targetName]!['publicEntrypoints'] as List).contains(
              library,
            )) {
          report(
            'private-import',
            file.path,
            'Use a public entrypoint of $targetName.',
            line,
          );
        }
        if (runtimeProduction &&
            targetName != owner.name &&
            registered.containsKey(targetName) &&
            (!owner.dependencies.containsKey(targetName) ||
                !(runtimeModules[owner.name]!['dependencies'] as List).contains(
                  targetName,
                ))) {
          report(
            'undeclared-import',
            file.path,
            'Runtime import $targetName is not allowed.',
            line,
          );
        }
        if (production && targetName != owner.name) {
          if (!owner.dependencies.containsKey(targetName) ||
              !(modules[owner.name]!['dependencies'] as List).contains(
                targetName,
              )) {
            report(
              'undeclared-import',
              file.path,
              'Runtime import $targetName is not allowed.',
              line,
            );
          }
          if (parts.skip(1).contains('src'))
            report(
              'private-import',
              file.path,
              'Domain cannot import another package implementation.',
              line,
            );
        }
        return;
      }
      if (uri.hasScheme) {
        report(
          'invalid-uri',
          file.path,
          'Only SDK, package or local directives are supported.',
          line,
        );
        return;
      }
      final target = p.normalize(
        p.join(
          p.dirname(file.path),
          uri.toFilePath(windows: Platform.isWindows),
        ),
      );
      if (!p.isWithin(owner.directory, target) ||
          (production && !p.isWithin(p.join(owner.directory, 'lib'), target))) {
        report(
          'relative-escape',
          file.path,
          'Relative directives cannot bypass a package boundary.',
          line,
        );
      } else if (![
        'lib',
        'test',
        'bin',
        'integration_test',
      ].any((tree) => p.isWithin(p.join(owner.directory, tree), target))) {
        report(
          'relative-escape',
          file.path,
          'Directive targets an unchecked source tree.',
          line,
        );
      }
    }

    for (final directive in parsed.unit.directives) {
      if (directive is UriBasedDirective) inspectUri(directive.uri);
      if (directive is NamespaceDirective) {
        for (final configuration in directive.configurations) {
          inspectUri(configuration.uri);
        }
      }
      if (directive is PartOfDirective && directive.uri != null)
        inspectUri(directive.uri!);
    }
  }

  void inspectTree(_Package owner, Directory folder) {
    if (!folder.existsSync()) return;
    for (final entity in folder.listSync(followLinks: false)) {
      if (entity is Link) {
        report(
          'unsafe-path',
          entity.path,
          'Linked source paths are not supported.',
        );
      } else if (entity is Directory) {
        inspectTree(owner, entity);
      } else if (entity is File && entity.path.endsWith('.dart')) {
        inspectFile(owner, entity);
      }
    }
  }

  for (final owner in packages.values) {
    for (final tree in ['lib', 'test', 'bin', 'integration_test']) {
      final path = p.join(owner.directory, tree);
      if (FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.link) {
        report('unsafe-path', path, 'Linked source root is not supported.');
      } else {
        inspectTree(owner, Directory(path));
      }
    }
  }
  issues.sort((a, b) => a.toString().compareTo(b.toString()));
  return issues;
}
