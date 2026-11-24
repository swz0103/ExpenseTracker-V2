import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/layout.dart';

/// D83: every edit form has 取消, and leaving it with changes asks
/// 要捨棄修改嗎？ first, through the one guard (design_system/
/// edit_guard.dart). The forms are listed here; any other file that
/// holds typed or chosen values in a State (under a `forms/` folder, or
/// with a text field) is either one of them or says below why it is not.
void main() {
  test('every edit form is guarded and has 取消', () {
    final missing = <String>[];
    for (final MapEntry(key: path, value: cancel) in _forms.entries) {
      final text = File('${Layout.src}/$path').readAsStringSync();
      if (!text.contains('EditGuard(')) missing.add('$path: no EditGuard');
      if (cancel != null &&
          !File('${Layout.src}/$cancel')
              .readAsStringSync()
              .contains('CancelButton(')) {
        missing.add('$path: no CancelButton in $cancel');
      }
      // Closing past the guard would ask 要捨棄修改嗎？ after a save.
      if (RegExp(r'Navigator\.of\(context\)\.pop\(').hasMatch(text) &&
          !_ownPickers.contains(path)) {
        missing.add('$path: leaves with Navigator.pop, not EditGuard.close');
      }
    }
    expect(missing, isEmpty);
  });

  test('no form goes unlisted', () {
    final found = <String>[];
    for (final f in Directory(Layout.src).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      final holds =
          text.contains('extends State<') &&
          (f.path.contains('/forms/') ||
              text.contains('TextEditingController(') ||
              text.contains('TextField('));
      if (!holds) continue;
      final path = f.path.substring(Layout.src.length + 1);
      if (_forms.containsKey(path) || _notForms.containsKey(path)) continue;
      found.add(path);
    }
    expect(
      found,
      isEmpty,
      reason:
          'Guard each with EditGuard and list it in _forms, or say in '
          '_notForms why it is not an edit form',
    );
  });

  test('the lists name files that exist', () {
    for (final path in [
      ..._forms.keys,
      ..._forms.values.nonNulls,
      ..._notForms.keys,
    ]) {
      expect(File('${Layout.src}/$path').existsSync(), isTrue, reason: path);
    }
  });
}

/// The edit forms, each with the file that shows its 取消.
const _forms = <String, String?>{
  'features/accounts/forms/account_editor_state.dart':
      'features/accounts/forms/account_editor_edit_card.dart',
  'features/budgets/forms/budget_editor.dart':
      'features/budgets/forms/budget_editor.dart',
  'features/categories/forms/category_editor.dart':
      'features/categories/forms/category_editor.dart',
  'features/entries/forms/composer_state.dart':
      'features/entries/forms/form_frame.dart',
  'features/recurring/forms/recurring_editor.dart':
      'features/recurring/forms/recurring_editor.dart',
  'features/tags/ui/tag_page.dart': 'features/tags/ui/tag_page.dart',
  // 對帳 and every amount: a keypad with no 取消 of its own (an open
  // decision); what was typed is asked about before it goes.
  'core/widgets/calculator.dart': null,
};

/// Forms whose file also opens small pickers of its own, which close
/// their own sheet with Navigator.pop.
const _ownPickers = <String>{
  'features/accounts/forms/account_editor_state.dart',
  'features/tags/ui/tag_page.dart',
};

/// Files holding typed or chosen values that are not edit forms, and why.
const _notForms = <String, String>{
  'features/accounts/forms/loan_fields.dart':
      'a one-field panel inside the account form, with 取消',
  'features/entries/forms/holding_choices.dart':
      'a choice inside the entry form, which is guarded',
  'features/entries/forms/merchant_tag_pickers.dart':
      'a choice inside the entry form, which is guarded',
  'features/entries/forms/people_choices.dart':
      'a choice inside the entry form, which is guarded',
  'features/overview/forms/overview_editor.dart':
      'keeps each change as it is made; nothing to lose',
  'features/recurring/forms/recurring_repeat.dart':
      'sheets changing the recurring form as they go, which is guarded',
  'features/entries/ui/entries_filter_sheet.dart':
      'a filter, applied or not; nothing kept',
  'features/entries/ui/entries_search.dart': 'a search field',
  'features/entries/ui/entries_page.dart': 'a search field',
  'app/settings_search.dart': 'a search field',
  'app/demo/launch.dart': 'the preview start',
  'features/lock/ui/lock_screen.dart': 'the password, not an edit',
  'features/lock/ui/views/new_password_view.dart':
      'a password set before anything else; no way to leave it',
  'features/lock/ui/views/unlock_view.dart': 'the password, not an edit',
  'features/lock/ui/security_section.dart':
      'password panels with 取消; a secret is not kept to ask about',
  'core/design_system/dialogs.dart': 'askText: a dialog with 取消',
  'core/design_system/password_field.dart': 'a field of the lock screens',
  'core/widgets/pickers_days.dart': 'a picker; a choice closes it',
};
