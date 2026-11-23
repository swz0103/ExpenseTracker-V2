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
];

/// Pure packages (rule A4) and the tests they must have (rule C1a).
const purePackages = ['packages/core', 'packages/domain'];

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

/// Owners of number formatting and parsing (rule B2): the amount parser,
/// figures and percentages of core, and how the app shows them.
const numberFormatOwners = [
  'packages/core/lib',
  '$appLib/design_system/display/',
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

/// The status words (rule B7): written as a string literal only by their
/// owners; everywhere else they come from the status presentation.
const statusWords = [
  '已逾期',
  '已繳清',
  '已出帳',
  '未出帳',
  '超支',
  '快用完',
  '已賣光',
  '已入帳',
  '已略過',
  '已暫停',
  '已結清',
  '部分收回',
];

/// Where rule B7 looks: the app's code.
const statusWordScopes = ['$appLib/'];

/// Owners of the status words (rule B7): the status presentation and its
/// messages file.
const statusWordOwners = [
  '$appLib/design_system/display/status.dart',
  '$appLib/design_system/display/status_messages.dart',
];

/// Where the registry of single sources lives.
const ownersFile = 'tooling/rules/owners.yaml';

/// Where the ratchet baseline lives.
const baselineFile = 'tooling/rules/baseline.json';
