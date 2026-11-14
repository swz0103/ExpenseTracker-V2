import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The design system's rules, as docs/design.md sets them out: colours,
/// sizes of words and buttons come from core/look, never written in a
/// page, so one change there reaches every page and both themes.
void main() {
  final files = [
    for (final f in Directory('lib/src').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f,
  ];
  String path(File f) => f.uri.path;
  bool under(File f, List<String> places) =>
      places.any((p) => path(f).contains(p));

  test('colours are named in core/look, not written in a page', () {
    // A category's colour is data, kept with the ledger and made up for
    // the preview; the look names every other colour.
    const exempt = ['/core/look/', '/core/ledger/', '/model/', '/app/demo/'];
    final literal = RegExp(r'(Color|Shade)\(0x');
    for (final f in files) {
      if (under(f, exempt)) continue;
      expect(
        literal.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '${path(f)}: name the colour in core/look/theme.dart',
      );
    }
  });

  test('words take a size from the type scale', () {
    final literal = RegExp(r'fontSize: \d');
    for (final f in files) {
      if (path(f).endsWith('/core/look/type.dart')) continue;
      expect(
        literal.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '${path(f)}: use TextSize from core/look/type.dart',
      );
    }
  });

  test('buttons take their look from core/look', () {
    final own = RegExp(r'(Filled|Text)Button\.styleFrom\(');
    for (final f in files) {
      if (under(f, ['/core/look/'])) continue;
      expect(
        own.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '${path(f)}: use solidButton or wordButton',
      );
    }
  });
}
