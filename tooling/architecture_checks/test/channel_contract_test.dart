import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:architecture_checks/app_syntax.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The Dart side and the Android side of the app talk over one
/// MethodChannel by method name. A name changed on one side compiles on
/// both and fails only on the phone, so this test reads both sides and
/// asks that every name sent is one the other side answers.
void main() {
  final root = p.normalize(p.join(Directory.current.path, '..', '..'));
  final app = p.join(root, 'apps', 'expense_tracker');
  // What the app's builds are made of: the shared code and each flavor's
  // (sideload has the update installer, play has stand-ins); not the tests.
  final kotlin = [
    for (final source in ['main', 'sideload', 'play'])
      if (Directory(
        p.join(app, 'android', 'app', 'src', source, 'kotlin'),
      ).existsSync())
        for (final f in Directory(
          p.join(app, 'android', 'app', 'src', source, 'kotlin'),
        ).listSync(recursive: true))
          if (f is File && f.path.endsWith('.kt')) f.readAsStringSync(),
  ];
  final dart = appSources(root);

  test('every method the app asks of Android is answered there', () {
    final sent = <String>{for (final s in dart) ..._sentNames(s.unit)};
    final answered = <String>{for (final k in kotlin) ..._whenBranches(k)};
    expect(sent, isNotEmpty);
    expect(
      sent.difference(answered),
      isEmpty,
      reason: 'sent by Dart, answered by no Kotlin handler',
    );
    expect(
      answered.difference(sent),
      isEmpty,
      reason: 'answered in Kotlin, never sent: dead, or a name misspelt',
    );
  });

  test('every method Android asks of the app is answered there', () {
    final sent = {
      for (final k in kotlin)
        for (final m in RegExp(r'invokeMethod\("(\w+)"').allMatches(k)) m[1]!,
    };
    final answered = {
      for (final s in dart)
        for (final m in RegExp(
          r"call\.method == '(\w+)'|case '(\w+)'",
        ).allMatches(s.lines.join('\n')))
          (m[1] ?? m[2])!,
    };
    expect(sent, isNotEmpty);
    expect(sent.difference(answered), isEmpty);
  });
}

/// The names a Kotlin handler answers: the `"name" ->` branches of each
/// `when (call.method)`, and `call.method != "name"` / `== "name"` tests.
Set<String> _whenBranches(String source) {
  final names = <String>{
    for (final m in RegExp(r'call\.method [!=]= "(\w+)"').allMatches(source))
      m[1]!,
  };
  for (final block in RegExp(r'when \(call\.method\) \{').allMatches(source)) {
    // The block runs to its closing brace at the same depth.
    var depth = 0;
    var end = block.end - 1;
    for (var i = block.end - 1; i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}' && --depth == 0) {
        end = i;
        break;
      }
    }
    final body = source.substring(block.end, end);
    for (final line in body.split('\n')) {
      final branch = RegExp(r'^\s*((?:"\w+",?\s*)+)->').firstMatch(line);
      if (branch == null) continue;
      for (final n in RegExp(r'"(\w+)"').allMatches(branch[1]!)) {
        names.add(n[1]!);
      }
    }
  }
  return names;
}

/// The method names a unit sends with `invokeMethod` (or its list and map
/// forms): a literal, or a
/// parameter of the function around it, filled with a literal by each call
/// of that function in the same unit (as the keystore's wrap and unwrap).
Set<String> _sentNames(CompilationUnit unit) {
  final finder = _Invokes()..run(unit);
  final names = <String>{};
  for (final call in finder.found) {
    final first = call.argumentList.arguments.first.argumentExpression;
    if (first is SimpleStringLiteral) {
      names.add(first.value);
      continue;
    }
    if (first is! SimpleIdentifier) continue;
    final function = call.thisOrAncestorOfType<MethodDeclaration>();
    final name = function?.name.lexeme;
    final at = function?.parameters?.parameters.indexWhere(
      (parameter) => parameter.name?.lexeme == first.name,
    );
    if (name == null || at == null || at < 0) continue;
    for (final caller in finder.calls) {
      if (caller.methodName.name != name) continue;
      final value = caller.argumentList.arguments[at].argumentExpression;
      if (value is SimpleStringLiteral) names.add(value.value);
    }
  }
  return names;
}

/// MethodChannel's ways of sending a call.
const _sends = {'invokeMethod', 'invokeListMethod', 'invokeMapMethod'};

final class _Invokes extends RecursiveAstVisitor<void> {
  final found = <MethodInvocation>[];
  final calls = <MethodInvocation>[];

  void run(CompilationUnit unit) => unit.accept(this);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    calls.add(node);
    if (_sends.contains(node.methodName.name) &&
        node.argumentList.arguments.isNotEmpty) {
      found.add(node);
    }
    super.visitMethodInvocation(node);
  }
}
