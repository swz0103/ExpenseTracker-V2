import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import 'config.dart';

/// One broken rule at one place.
final class Violation {
  const Violation(this.ruleId, this.file, this.line, this.message);

  final String ruleId;

  /// Relative to the repository root, `/` between folders.
  final String file;
  final int line;
  final String message;

  @override
  String toString() => '$file:$line  [$ruleId] $message';
}

/// A Dart file read from the repository (or from a test's string).
final class SourceFile {
  SourceFile(this.path, this.content);

  final String path;
  final String content;

  late final ParseStringResult _parsed = parseString(
    content: content,
    path: path,
    throwIfDiagnostics: false,
  );

  /// The syntax tree; no resolution, so `DateTime.now()` is a method
  /// invocation, not a constructor call.
  CompilationUnit get unit => _parsed.unit;

  int lineOf(int offset) => _parsed.lineInfo.getLocation(offset).lineNumber;

  int lineOfNode(AstNode node) => lineOf(node.offset);

  /// Whether this file is [prefix] itself or below it (a prefix ending in
  /// `/` is a folder).
  bool isUnder(String prefix) =>
      path == prefix ||
      path.startsWith(prefix.endsWith('/') ? prefix : '$prefix/');

  bool isUnderAny(Iterable<String> prefixes) => prefixes.any(isUnder);
}

/// All the Dart files the rules look at.
final class Project {
  Project(Map<String, String> sources)
    : files = [for (final e in sources.entries) SourceFile(e.key, e.value)]
        ..sort((a, b) => a.path.compareTo(b.path));

  /// Reads every `.dart` file under [scanRoots] below [root].
  factory Project.discover(String root) {
    final sources = <String, String>{};
    for (final top in scanRoots) {
      final dir = Directory(p.join(root, top));
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final rel = p.posix.joinAll(p.split(p.relative(f.path, from: root)));
        sources[rel] = f.readAsStringSync();
      }
    }
    return Project(sources);
  }

  final List<SourceFile> files;
}

/// A rule: [check] returns every violation in the project.
abstract class Rule {
  const Rule();

  /// Stable id; the baseline is keyed by it.
  String get id;

  /// One line: what the rule prevents.
  String get purpose;

  List<Violation> check(Project project);
}

/// A rule that reads one file at a time.
abstract class FileRule extends Rule {
  const FileRule();

  bool appliesTo(SourceFile file);

  List<Violation> checkFile(SourceFile file);

  @override
  List<Violation> check(Project project) => [
    for (final f in project.files)
      if (appliesTo(f)) ...checkFile(f),
  ];
}

/// The repository-relative path of an import or export [uri] written in
/// [from], or null when it is not a file of the app (`dart:`, other
/// packages).
String? resolveAppImport(String from, String uri) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    const own = 'package:$appPackage/';
    if (!uri.startsWith(own)) return null;
    return '$appLib/${uri.substring(own.length)}';
  }
  return p.posix.normalize(p.posix.join(p.posix.dirname(from), uri));
}

/// The URI of every import and export of [file], with its line.
Iterable<(String, int)> directiveUris(SourceFile file) sync* {
  for (final d in file.unit.directives) {
    if (d is NamespaceDirective) {
      final uri = d.uri.stringValue;
      if (uri != null) yield (uri, file.lineOfNode(d));
    }
  }
}
