import 'dart:io';

import 'package:architecture_checks/app_syntax.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The app's rules that are about its code, read from the syntax tree
/// rather than matched as text: a comment, a string or another way of
/// writing the same thing neither trips them nor slips past them.
/// docs/design.md and docs/architecture.md say why each rule is there.
void main() {
  final root = p.normalize(p.join(Directory.current.path, '..', '..'));
  final units = appUnits(root);
  List<String> found(bool Function(String path) where, Finder finder) => [
    for (final MapEntry(key: path, value: unit) in units.entries)
      if (where(path))
        for (final what in (finder..found.clear()).run(unit)) '$path: $what',
  ];

  test('colours are named in core/design_system, not written in a page', () {
    // A category's colour is data, kept with the ledger and made up for
    // the preview; the design system names every other colour.
    const exempt = [
      'src/core/design_system/',
      'src/core/ledger/',
      '/model/',
      'src/app/demo/',
    ];
    final faults = found(
      (path) => !exempt.any(path.contains),
      ColourLiterals(),
    );
    expect(faults, isEmpty, reason: 'name the colour in theme.dart');
  });

  test('words take a size from the type scale', () {
    // Also a size picked between two, as `fontSize: done ? 16 : 15`; a
    // size worked out from another, as `size * 0.44`, may stand.
    final faults = found(
      (path) => !path.endsWith('core/design_system/type.dart'),
      FontSizeLiterals(),
    );
    expect(faults, isEmpty, reason: 'use TextSize from type.dart');
  });

  test('casts of outside data only become fewer', () {
    // Read through JsonFields (core/formatting/json_fields.dart) instead:
    // a cast throws a TypeError for one field of the wrong kind and takes
    // the rest down with it. What is left is the ledger's own rows.
    const most = 12;
    final casts = found((_) => true, Casts());
    expect(casts.length, lessThanOrEqualTo(most), reason: casts.join('\n'));
    expect(casts.length, most, reason: 'fewer now: lower `most`');
  });

  test('fewer screens take the whole ledger', () {
    // A screen or a model that needs only the entries, or the reports,
    // takes that part (EntryReader, ReportService, exported by
    // ledger.dart): it says what it uses, and a test gives it only that.
    // Only the features count: the app's own files put the ledger
    // together and hand it out (lib/app_syntax.dart).
    const most = 58;
    final whole = wholeLedgerFiles(units);
    expect(whole.length, lessThanOrEqualTo(most), reason: 'take the part');
    expect(whole.length, most, reason: 'fewer now: lower `most`');
  });

  test('fewer models take the whole ledger', () {
    // A model takes the readers, services and commands it uses, and the
    // day as a value: its dependencies show, and a test needs no whole
    // book (docs/adr/0013-models-take-what-they-use.md). Goal: none.
    // A form model that is a page's whole state may hold it, marked
    // `// Exception to models take what they use: <why>`.
    const most = 0;
    final whole = [
      for (final path in wholeLedgerFiles(units))
        if (path.contains('/model/'))
          if (!File(p.join(root, 'apps', 'expense_tracker', 'lib', path))
              .readAsStringSync()
              .contains('// Exception to models take what they use:'))
            path,
    ];
    expect(whole.length, lessThanOrEqualTo(most), reason: whole.join('\n'));
    expect(whole.length, most, reason: 'fewer now: lower `most`');
  });
}
