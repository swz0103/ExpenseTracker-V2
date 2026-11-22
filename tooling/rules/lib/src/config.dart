/// Every path the rules know about, in one place. Today's layout; later
/// phases move code and only edit this file. All paths are relative to the
/// repository root, with `/` between folders.
library;

/// The app's Dart root.
const appLib = 'apps/expense_tracker/lib';

/// The app's tests.
const appTest = 'apps/expense_tracker/test';

/// The app's package name, for `package:` imports of its own files.
const appPackage = 'expense_tracker';

/// Where each feature lives: `<featuresDir>/<name>/...`.
const featuresDir = '$appLib/src/features';

/// Where each feature's tests live: `<featureTestsDir>/<name>/...`.
const featureTestsDir = '$appTest/features';

/// The composition layer of the app.
const appShellDir = '$appLib/src/app';

/// Roots scanned for Dart files (code and tests).
const scanRoots = [
  'apps/expense_tracker/lib',
  'apps/expense_tracker/test',
  'packages/core/lib',
  'packages/core/test',
  'packages/domain/lib',
  'packages/domain/test',
  'packages/ledger',
];

/// Pure packages (rule A4) and the tests they must have (rule C1a).
const purePackages = ['packages/core', 'packages/domain'];

/// Folders whose every subfolder is a pure package, such as
/// `packages/ledger/entries`.
const purePackageGroups = ['packages/ledger'];

/// The pure package [path] lies in, such as `packages/ledger/entries`;
/// null outside them.
String? purePackageOf(String path) {
  for (final pkg in purePackages) {
    if (path.startsWith('$pkg/')) return pkg;
  }
  for (final group in purePackageGroups) {
    if (!path.startsWith('$group/')) continue;
    final rest = path.substring(group.length + 1);
    final slash = rest.indexOf('/');
    if (slash > 0) return '$group/${rest.substring(0, slash)}';
  }
  return null;
}

/// Packages a feature must not import (rule A3).
const dataPackages = ['storage', 'vault', 'market'];

/// Folders a feature must not import from (rule A3).
const dataFolders = [
  '$appLib/src/app/android/',
  '$appLib/src/core/ledger/persistence/',
];

/// Imports forbidden in the pure packages (rule A4).
const impurePrefixes = ['package:flutter/', 'dart:io', 'dart:ui', 'dart:ffi'];

/// The clock implementation: the one file of the pure packages that may
/// call `DateTime.now()` (rule A4).
const clockFiles = ['packages/core/lib/src/app_core/clock.dart'];

/// Owners of number formatting and parsing (rule B2).
const numberFormatOwners = [
  'packages/core/lib',
  '$appLib/src/core/formatting/',
];

/// Owners of "now" (rule B3): the time folder and the composition roots.
const clockOwners = [
  '$appLib/src/core/time/',
  '$appLib/main.dart',
  '$appLib/main_preview.dart',
];

/// Owner of padding numbers into text (rule B3).
const paddingOwners = ['$appLib/src/core/formatting/'];

/// Where user-facing text must not be written inline (rule B9).
const textScopes = ['$appLib/src/features/', '$appLib/src/app/'];

/// Owner of the user-facing text (rule B9).
const textOwners = ['$appLib/src/core/messages/'];

/// Where the registry of single sources lives.
const ownersFile = 'tooling/rules/owners.yaml';

/// Where the ratchet baseline lives.
const baselineFile = 'tooling/rules/baseline.json';
