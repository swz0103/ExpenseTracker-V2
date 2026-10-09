import 'package:flutter/widgets.dart';

import '../demo/ledger.dart';

/// The pages under 更多 and the account page, by key.
abstract final class Pages {
  static const reports = 'reports';
  static const investments = 'investments';
  static const budgets = 'budgets';
  static const recurring = 'recurring';
  static const categories = 'categories';
  static const settings = 'settings';

  /// `account:<id>`.
  static String account(String id) => 'account:$id';
}

/// What a page may ask of the app frame.
final class Nav {
  const Nav({
    required this.open,
    required this.back,
    required this.compose,
    required this.showEntry,
  });

  /// Opens a page from [Pages].
  final ValueChanged<String> open;

  /// Returns from an opened page.
  final VoidCallback back;

  /// Opens the composer for a new entry of [type], or to edit [entry].
  final Future<void> Function({EntryType type, Entry? entry}) compose;

  /// Shows an entry's details, with delete and edit.
  final ValueChanged<Entry> showEntry;
}
