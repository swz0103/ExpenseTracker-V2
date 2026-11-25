import 'dart:async';

import '../../../core/design_system/dialogs.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/pickers.dart';
import '../model/compose_form.dart';
import 'people_choices.dart';
import 'composer_state.dart';

// Picking whom 代墊 is for or from: choices opened in the form's place.

extension ComposerLendPickers on ComposerState {
  /// Picks whom a spending is paid for, any number of people, or adds a
  /// new person; the amount is then shared evenly.
  Future<void> chooseLent() async {
    final picked = await openPage<List<String>>(
      '代墊給誰',
      (done) => PeopleChoices(
        people: form.people,
        selected: [
          for (final (p, _) in form.lent ?? const <(String, int)>[]) p,
        ],
        color: color,
        onDone: done,
        onAdd: _addPerson,
      ),
    );
    if (picked == null || !mounted) return;
    update(() => form.lendTo(picked));
  }

  /// Asks for a new person's name and opens an account for what they owe.
  Future<Account?> _addPerson() async {
    final name = await askText(context, '代墊對象的名字');
    if (name == null || !mounted) return null;
    return form.addPerson(name);
  }

  /// Picks whom the money is for, or adds a new person.
  Future<void> choosePerson() async {
    const adding = '';
    final picked = form.people.isEmpty
        ? adding
        : await openPage<String>(
            form.back ? '誰還錢' : '幫誰付',
            (done) => OptionGrid<String>(
              selected: form.to,
              columns: 3,
              ring: color,
              onPick: done,
              options: [
                for (final a in form.people)
                  Option(a.id, a.name, Glyph.heart, AppColors.muted),
                const Option(adding, '新增對象', Glyph.add, AppColors.muted),
              ],
            ),
          );
    if (picked == null || !mounted) return;
    if (picked != adding) {
      update(() {
        form.to = picked;
        if (form.back) form.payAll();
      });
      return;
    }
    final account = await _addPerson();
    if (account == null) return;
    update(() {
      form.to = account.id;
      form.paying = {};
    });
  }
}
