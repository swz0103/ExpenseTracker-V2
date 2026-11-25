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
  /// always import itself.
  static const coreParts = <String, List<String>>{
    'formatting': [],
    // The one clock the app reads the time from.
    'time': [],
    'diagnostics': ['time'],
    'design_system': ['formatting'],
    'charts': ['design_system', 'formatting'],
    'ledger': ['formatting', 'diagnostics', 'time'],
    'platform': ['ledger', 'formatting', 'diagnostics', 'time'],
    // What the person is told, in one place: of the ledger's values, and
    // of what the phone answered (a scan, the look for a newer version),
    // whose outcomes platform names. Platform uses no words, so the two
    // cannot come to need each other.
    'messages': ['ledger', 'formatting', 'platform'],
    'widgets': [
      'messages',
      'design_system',
      'formatting',
      'ledger',
      'charts',
      'platform',
      'diagnostics',
      'time',
      'navigation',
    ],
    // Opening pages and flows: Nav, AppRoutes, openFullScreen; a page of
    // the settings opened on the setting a search found (its words).
    'navigation': ['ledger', 'platform', 'formatting'],
  };

  /// The design system: where colours, type sizes and buttons are named.
  static const designSystemDir = '/core/design_system/';
  static const typeFile = '/core/design_system/type.dart';
  static const keysFile = 'core/design_system/keys.dart';

  /// The folders inside a feature, and those that hold screens.
  static const featureFolders = ['model', 'ui', 'forms'];
  static const screenFolders = ['/ui/', '/forms/'];
  static const modelFolder = '/model/';

  /// Folders that paint, which no model or the ledger may import.
  static const paintingDirs = ['core/design_system/', 'core/charts/'];

  /// The one file that pushes a route.
  static const routePusher = 'lib/src/core/design_system/feedback.dart';

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
    // The journal of postings beside the records: what the records are
    // as intents, posted afresh, and checked against the services.
    'journal/',
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
    'lib/src/core/formatting/',
  ];

  /// How long a file grows before it should be split or say why not.
  static const fileGuide = 600;
}
