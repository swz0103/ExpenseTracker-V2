import 'package:kernel/kernel.dart';
import 'package:ledger_loans/feature/loans_module.dart';

/// The modules the app is built with, each taken in through the
/// contribution points: the one place that names a module's feature
/// (tooling/architecture_checks, modules_test). Removing a module is its
/// line here and its line in pubspec.yaml; its records stay, and the
/// accounts it claimed fall to the balance sheet's unclaimed row.
void installModules(Contributions contributions) {
  LoansModule.install(contributions);
}
