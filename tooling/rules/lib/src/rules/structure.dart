import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../config.dart';
import '../engine.dart';

/// D2: a library is one file; `part` splits one thing into pieces that
/// cannot be read or tested apart.
///
/// Known noise: none; every `part` and `part of` directive counts 1.
final class NoPart extends FileRule {
  const NoPart();

  @override
  String get id => 'D2-no-part';

  @override
  String get purpose => 'a file uses part or part of';

  @override
  bool appliesTo(SourceFile file) => file.isUnder(appLib);

  @override
  List<Violation> checkFile(SourceFile file) => [
    for (final d in file.unit.directives)
      if (d is PartDirective || d is PartOfDirective)
        Violation(
          id,
          file.path,
          file.lineOfNode(d),
          d is PartDirective ? 'part directive' : 'part of directive',
        ),
  ];
}

final class _Handling extends RecursiveAstVisitor<void> {
  var handled = false;

  @override
  void visitRethrowExpression(RethrowExpression node) => handled = true;

  @override
  void visitThrowExpression(ThrowExpression node) => handled = true;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    const reporters = {'record', 'report', 'completeError'};
    if (reporters.contains(node.methodName.name) ||
        (node.target?.toSource().contains('ErrorLog') ?? false) ||
        node.methodName.name == 'ErrorLog') {
      handled = true;
    }
    super.visitMethodInvocation(node);
  }
}

final class _Catches extends RecursiveAstVisitor<void> {
  final unhandled = <CatchClause>[];

  @override
  void visitCatchClause(CatchClause node) {
    final handling = _Handling();
    node.body.accept(handling);
    if (!handling.handled) unhandled.add(node);
    super.visitCatchClause(node);
  }
}

/// E1: a caught error is passed on or recorded, never swallowed.
///
/// Known noise: a catch that deliberately ignores an expected failure
/// (a parse that may fail, a missing optional file) is flagged; a catch
/// that handles the error by returning a fallback after logging by another
/// name is flagged; any method called `record` or `report` counts as
/// recording, whatever it does.
final class CatchHandled extends FileRule {
  const CatchHandled();

  @override
  String get id => 'E1-catch-handled';

  @override
  String get purpose =>
      'a catch clause neither rethrows, throws nor records the error';

  @override
  bool appliesTo(SourceFile file) => file.isUnder(appLib);

  @override
  List<Violation> checkFile(SourceFile file) {
    final visitor = _Catches();
    file.unit.accept(visitor);
    return [
      for (final c in visitor.unhandled)
        Violation(
          id,
          file.path,
          file.lineOfNode(c),
          'error caught and not handled',
        ),
    ];
  }
}

/// C1: every unit of the pure packages and every feature has a test.
///
/// (a) A file `lib/src/**/<name>.dart` of core or domain needs a
/// `<name>_test.dart` anywhere under the package's `test/`. (b) A feature
/// folder needs at least one `*_test.dart` under its test folder.
///
/// Known noise: matching by file name only. A file tested through another
/// file's test is flagged; a test that merely shares the name passes;
/// files with no logic of their own (barrels, constants) are flagged.
final class TestsExist extends Rule {
  const TestsExist();

  @override
  String get id => 'C1-tests-exist';

  @override
  String get purpose => 'a core/domain file or a feature has no test file';

  @override
  List<Violation> check(Project project) {
    final found = <Violation>[];
    final paths = [for (final f in project.files) f.path];
    for (final pkg in purePackages) {
      final testNames = {
        for (final path in paths)
          if (path.startsWith('$pkg/test/')) p.posix.basename(path),
      };
      for (final path in paths) {
        if (!path.startsWith('$pkg/lib/src/')) continue;
        final base = p.posix.basenameWithoutExtension(path);
        if (!testNames.contains('${base}_test.dart')) {
          found.add(
            Violation(id, path, 1, 'no ${base}_test.dart under $pkg/test'),
          );
        }
      }
    }
    final features = <String>{
      for (final path in paths)
        if (path.startsWith('$featuresDir/') &&
            path.substring(featuresDir.length + 1).contains('/'))
          path.substring(featuresDir.length + 1).split('/').first,
    };
    for (final name in features) {
      final dir = '$featureTestsDir/$name/';
      final tested = paths.any(
        (x) => x.startsWith(dir) && x.endsWith('_test.dart'),
      );
      if (!tested) {
        found.add(
          Violation(id, '$featuresDir/$name', 1, 'no *_test.dart under $dir'),
        );
      }
    }
    return found;
  }
}
