import 'engine.dart';
import 'rules/imports.dart';
import 'rules/structure.dart';
import 'rules/usage.dart';

/// Every rule that is checked, in the order they are reported.
const List<Rule> allRules = [
  FeatureIsolation(),
  UiNoData(),
  PureCalc(),
  NumberFormat(),
  ClockAndPadding(),
  TextLiterals(),
  NoPart(),
  CatchHandled(),
  TestsExist(),
];
