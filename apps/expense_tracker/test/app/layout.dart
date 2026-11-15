/// The app's folders as data: the one place the rule tests learn them, so
/// a folder that is renamed (docs/adr/0009) is changed here and nowhere
/// else. Paths are from the app folder.
abstract final class Layout {
  static const src = 'lib/src';
  static const coreDir = 'lib/src/core/';
  static const featuresDir = 'lib/src/features/';
  static const appDir = 'lib/src/app/';
  static const demoDir = 'lib/src/app/demo/';
  static const ledgerDir = 'lib/src/core/ledger/';

  /// The parts of core, and the other parts each may import. A part may
  /// always import itself. [navigation] is a single file at the top.
  static const coreParts = <String, List<String>>{
    'text': [],
    'diagnostics': [],
    'look': ['text'],
    'charts': ['look', 'text'],
    'ledger': ['text', 'diagnostics'],
    'platform': ['ledger', 'text', 'diagnostics'],
    'ui': [
      'look',
      'text',
      'ledger',
      'charts',
      'platform',
      'diagnostics',
      'nav.dart',
    ],
  };
  static const navigation = 'nav.dart';

  /// The design system: where colours, type sizes and buttons are named.
  static const designSystemDir = '/core/look/';
  static const themeFile = 'core/look/theme.dart';
  static const typeFile = '/core/look/type.dart';
  static const keysFile = 'core/look/keys.dart';

  /// The folders inside a feature, and those that hold screens.
  static const featureFolders = ['model', 'ui', 'compose'];
  static const screenFolders = ['/ui/', '/compose/'];
  static const modelFolder = '/model/';

  /// Folders that paint, which no model or the ledger may import.
  static const paintingDirs = ['core/look/', 'core/charts/'];

  /// The one file that pushes a route.
  static const routePusher = 'lib/src/core/look/feedback.dart';

  /// The one file of the ledger that touches storage.
  static const storageFile =
      'lib/src/core/ledger/persistence/sql_ledger_data_source.dart';

  /// What the ledger may import besides itself.
  static const ledgerMayImport = [
    'lib/src/core/diagnostics/',
    'lib/src/core/text/',
  ];

  /// Files allowed to be longer than [maxLines], with their own limit.
  static const maxLines = 600;
  static const longer = <String, int>{
    'lib/src/core/look/glyphs.dart': 2100,
    'lib/src/core/ledger/ledger.dart': 650,
  };

  /// Where an exemption from "no colour literals" applies.
  static const colourLiteralExempt = [
    designSystemDir,
    '/core/ledger/',
    modelFolder,
    '/app/demo/',
  ];
}
