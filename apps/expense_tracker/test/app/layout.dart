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
    // The one clock the app reads the time from.
    'time': [],
    'diagnostics': ['time'],
    'look': ['text'],
    'charts': ['look', 'text'],
    'ledger': ['text', 'diagnostics', 'time'],
    'platform': ['ledger', 'text', 'diagnostics', 'time'],
    // What the person is told of the ledger's values, in one place.
    'messages': ['ledger', 'text'],
    'ui': [
      'messages',
      'look',
      'text',
      'ledger',
      'charts',
      'platform',
      'diagnostics',
      'time',
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
  static const featureFolders = ['model', 'ui', 'forms'];
  static const screenFolders = ['/ui/', '/forms/'];
  static const modelFolder = '/model/';

  /// Folders that paint, which no model or the ledger may import.
  static const paintingDirs = ['core/look/', 'core/charts/'];

  /// The one file that pushes a route.
  static const routePusher = 'lib/src/core/look/feedback.dart';

  /// The one file of the ledger that touches storage.
  static const storageFile =
      'lib/src/core/ledger/persistence/sql_ledger_data_source.dart';

  /// The ledger's folders, lowest first: each may use only those before
  /// it, and the plain helpers beside ledger.dart. The persistence folder
  /// and ledger.dart put the book together and may use them all; of
  /// persistence, the commands use only the batch they hand over.
  static const ledgerLayers = [
    'models/',
    'cache/',
    'repositories/',
    'services/',
    'commands/',
  ];
  static const ledgerHelpers = [
    'amount_visibility.dart',
    'card_cycle.dart',
    'portfolio.dart',
    'trading.dart',
  ];
  static const commandsMayUse = [
    'persistence/write_batch.dart',
    'persistence/unit_of_work.dart',
  ];

  /// What the ledger may import besides itself.
  static const ledgerMayImport = [
    'lib/src/core/diagnostics/',
    'lib/src/core/text/',
  ];

  /// How long a file grows before it should be split or say why not.
  static const fileGuide = 600;

  /// Where an exemption from "no colour literals" applies.
  static const colourLiteralExempt = [
    designSystemDir,
    '/core/ledger/',
    modelFolder,
    '/app/demo/',
  ];
}
