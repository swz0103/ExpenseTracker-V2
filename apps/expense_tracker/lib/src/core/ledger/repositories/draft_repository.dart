import '../../formatting/json_fields.dart';
import '../../diagnostics/error_log.dart';
import '../../diagnostics/error_steps.dart';

/// What the composer may ask of the forms put aside.
abstract interface class DraftReader {
  /// The form put aside on [tab], as JSON; null when none.
  String? of(String tab);

  /// The receipt photos the forms put aside have chosen, so they are not
  /// swept away before the form is taken up again.
  Iterable<String> get receipts;
}

/// The forms put aside in the composer, as JSON by tab, kept across a
/// restart of the app. Plain state; the ledger decides when a change is
/// kept.
final class DraftRepository implements DraftReader {
  DraftRepository([Map<String, String> from = const {}]) : _byTab = {...from};

  final Map<String, String> _byTab;

  @override
  String? of(String tab) => _byTab[tab];

  /// Keeps the form put aside on [tab], or clears it when [json] is null.
  /// Whether that changed anything.
  bool set(String tab, String? json) {
    if (_byTab[tab] == json) return false;
    if (json == null) {
      _byTab.remove(tab);
    } else {
      _byTab[tab] = json;
    }
    return true;
  }

  @override
  Iterable<String> get receipts sync* {
    for (final json in _byTab.values) {
      try {
        final file = JsonFields.decode(json).text('receipt');
        if (file != null) yield file;
      } on FormatException catch (error) {
        // A form that cannot be read keeps no photo.
        ErrorLog.instance.record(ErrorSteps.draft, error);
      }
    }
  }

  /// Takes the forms of [other], as when the book is read again.
  void replaceWith(DraftRepository other) {
    _byTab
      ..clear()
      ..addAll(other._byTab);
  }
}
