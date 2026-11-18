import 'package:flutter/widgets.dart';

import '../../../core/look/glyphs.dart';
import '../../../core/look/theme.dart';
import '../model/compose_form.dart';

/// How each kind of record looks on its tab.
extension ComposeModeLook on ComposeMode {
  Glyph get icon => switch (this) {
    ComposeMode.expense => Glyph.bag,
    ComposeMode.income => Glyph.income,
    ComposeMode.transfer => Glyph.transfer,
    ComposeMode.lend => Glyph.heart,
    ComposeMode.investment => Glyph.investment,
  };

  Color get color => switch (this) {
    ComposeMode.expense => Hue.negative,
    ComposeMode.income => Hue.positive,
    ComposeMode.transfer => Hue.transfer,
    ComposeMode.lend => Hue.receivable,
    ComposeMode.investment => Hue.investment,
  };
}
