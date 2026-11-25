import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kernel/kernel.dart';
import 'package:shell/points.dart';
import 'package:shell/setting_topic.dart';

const module = OwnerId('loans');
const transfer = IntentType('transfer');

/// A whole NT$ amount, kept as an int.
const paid = Slot<int>('loans.paid', encode: _same, decode: _whole);
Object? _same(int value) => value;
int? _whole(Object? kept) => kept is int ? kept : null;

void main() {
  test('no two points share a name', () {
    final names = [for (final p in ShellPoints.all) p.name];
    expect(names.toSet(), hasLength(names.length));
    expect(names, hasLength(12));
  });

  test('a module adds to a point, the screen reads it with who added it', () {
    final c = Contributions();
    final item = SettingsItem(
      page: const SettingsPageKey('loans'),
      topic: const SettingTopic('貸款提醒', words: ['還款']),
      build: (_) => const SizedBox(),
    );
    c.on(ShellPoints.settings).add(module, item);
    c
        .on(ShellPoints.overview)
        .add(
          module,
          OverviewBlockItem(
            key: 'loans',
            title: '貸款',
            build: (_) => const Text(''),
          ),
        );
    expect(c.owned(ShellPoints.settings), [(module, item)]);
    expect(c.of(ShellPoints.settings).single.topic.matches('還款'), isTrue);
    expect(c.of(ShellPoints.overview).single.key, 'loans');
    expect(c.of(ShellPoints.budgetScopes), isEmpty);
  });

  test('a draft keeps values by slot, and slots it does not know as they '
      'came', () {
    final draft = Draft.fromJson({'fx.home': 3200});
    expect(draft.get(paid), isNull);
    draft.set(paid, 5059);
    expect(draft.get(paid), 5059);
    expect(draft.toJson(), {'fx.home': 3200, 'loans.paid': 5059});
    draft.set(paid, null);
    expect(draft.toJson(), {'fx.home': 3200});
    // A value of another type under the slot reads as none.
    expect(Draft.fromJson({'loans.paid': 'x'}).get(paid), isNull);
  });

  test('an entry kind builds its intent from a draft and opens it again', () {
    final kind = EntryKind(
      kind: transfer,
      label: '轉帳',
      order: 3,
      build: (draft, id) => draft.get(paid) == null ? null : null,
      open: (intent) => Draft(),
    );
    final c = Contributions()..on(ShellPoints.composerKinds).add(module, kind);
    final read = c.of(ShellPoints.composerKinds).single;
    expect((read.kind, read.label, read.order), (transfer, '轉帳', 3));
    expect(read.build(Draft(), const IntentId('a')), isNull);
  });

  testWidgets('a field of a module draws from the draft and keeps a change, '
      'read back through the point however its type', (tester) async {
    final draft = Draft()..set(paid, 100);
    var changes = 0;
    final c = Contributions()
      ..on(ShellPoints.composerFields).add(
        module,
        ComposerField<int>(
          slot: paid,
          order: 10,
          kinds: {transfer},
          build: (context, host) => TextButton(
            onPressed: () => host.changed((host.value ?? 0) + 1),
            child: Text('${host.value} ${host.problem ?? ''}'),
          ),
        ),
      );
    final field = c.of(ShellPoints.composerFields).single;
    expect(field.order, 10);
    expect(field.kinds, {transfer});
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => field.buildIn(
            context,
            draft,
            changed: () => changes++,
            problem: '太多',
          ),
        ),
      ),
    );
    expect(find.text('100 太多'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    expect(draft.get(paid), 101);
    expect(changes, 1);
  });

  test(
    'the points declared for the modules still to move take their items',
    () {
      final c = Contributions();
      c
          .on(ShellPoints.entryMarks)
          .add(
            module,
            EntryMark(kind: transfer, build: (_, _) => const SizedBox()),
          );
      c
          .on(ShellPoints.editors)
          .add(module, IntentEditor(kind: transfer, open: (_, _) async {}));
      c
          .on(ShellPoints.importColumns)
          .add(
            module,
            ImportColumn(headers: const ['還款'], slot: paid, read: int.tryParse),
          );
      c
          .on(ShellPoints.formDefaults)
          .add(module, FormDefault(slot: paid, suggest: (_) => 5059));
      c
          .on(ShellPoints.reminders)
          .add(module, ReminderSource(key: 'loans.due', due: (_) => const []));
      c
          .on(ShellPoints.integrity)
          .add(
            module,
            IntegrityCheck(key: 'loans.paid', problems: (_) => const []),
          );
      c
          .on(ShellPoints.backupSections)
          .add(
            module,
            BackupSection(
              key: 'loans.terms',
              version: 1,
              write: () => const {},
              read: (_, _) {},
            ),
          );
      c
          .on(ShellPoints.budgetScopes)
          .add(
            module,
            BudgetScope(key: 'loans', label: '貸款', accounts: (_) => const {}),
          );
      expect(c.of(ShellPoints.entryMarks).single.kind, transfer);
      expect(c.of(ShellPoints.editors).single.kind, transfer);
      expect(c.of(ShellPoints.importColumns).single.read('12'), 12);
      expect(c.of(ShellPoints.formDefaults).single.suggest(Draft()), 5059);
      expect(
        c.of(ShellPoints.reminders).single.due(Day.stored(20261125)),
        isEmpty,
      );
      expect(c.of(ShellPoints.integrity).single.key, 'loans.paid');
      expect(c.of(ShellPoints.backupSections).single.version, 1);
      expect(
        c.of(ShellPoints.budgetScopes).single.accounts(AccountTree()),
        isEmpty,
      );
    },
  );
}
