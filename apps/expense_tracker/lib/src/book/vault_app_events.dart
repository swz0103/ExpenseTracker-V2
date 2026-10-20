part of 'vault_journal.dart';

const _linkKind = '${appEventPrefix}recurring-link';
const _removedKind = '${appEventPrefix}recurring-removed';
const _ratesKind = '${appEventPrefix}rates';
const _carryKind = '${appEventPrefix}budget-carry';
const _quotesKind = '${appEventPrefix}quotes';
const _trashKind = '${appEventPrefix}trash';
const _restoredKind = '${appEventPrefix}trash-restored';

/// How long a deleted entry is kept to be restored.
const _keptInTrash = Duration(days: 30);

/// The app's own facts the ledger has no command for, kept as `app.`
/// events in its journal so backups carry them: recurring links, deleted
/// recurring items and the last rate board.
extension _AppEvents on VaultJournal {
  /// The payloads of the app events of [kind], oldest first.
  List<Map<String, Object?>> _events(String kind) {
    final rows = _vault.store.select(
      'SELECT payload FROM events WHERE workspace = ? AND kind = ? '
      'ORDER BY seq',
      [_workspace.toString(), kind],
    );
    return [
      for (final row in rows)
        jsonDecode(row['payload']! as String) as Map<String, Object?>,
    ];
  }

  /// Adds an app event of [kind], queued behind the ledger's commands.
  Future<void> _append(String kind, Map<String, Object?> payload) {
    final text = jsonEncode(payload);
    return _books.exclusive(() async {
      await _vault.store.write((t) async {
        t.append(
          id: PublicId.generate(),
          workspace: _workspace,
          kind: kind,
          payload: text,
        );
      });
    });
  }

  /// The recurring item behind each booking: the ones the ledger
  /// confirmed, and the bookings the app linked itself.
  Map<PublicId, PublicId> _recurringLinks() {
    final links = _store.recurringByPosting(_workspace);
    for (final json in _events(_linkKind)) {
      final posting = PublicId.parse(json['posting']! as String);
      links[posting] = PublicId.parse(json['template']! as String);
    }
    return links;
  }

  /// Links [posting] to [template]: an edited booking, whose ledger
  /// confirmation stays with the entry it replaced, or one the ledger
  /// could not confirm.
  Future<void> _linkRecurring(PublicId posting, PublicId template) {
    final link = {'posting': posting.value, 'template': template.value};
    return _append(_linkKind, link);
  }

  /// The recurring items the person deleted: the ledger can only stop
  /// them.
  Set<String> _removedTemplates() => {
    for (final json in _events(_removedKind)) json['template']! as String,
  };

  /// Whether each budget, by its plan id, adds last month's leftover; the
  /// last word for a budget counts.
  Map<String, bool> _carries() => {
    for (final json in _events(_carryKind))
      json['budget']! as String: json['carry']! as bool,
  };

  /// Entries deleted in the last [_keptInTrash] and not restored, newest
  /// first.
  List<ui.Trashed> _trash() {
    final restored = {
      for (final json in _events(_restoredKind)) json['entry']! as String,
    };
    final today = _clock.today();
    final from = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).subtract(_keptInTrash);
    final kept = <ui.Trashed>[];
    for (final json in _events(_trashKind)) {
      final on = BusinessDate.parse(json['on']! as String);
      final day = DateTime.utc(on.year, on.month, on.day);
      if (day.isBefore(from)) continue;
      final entry = entryFromJson(json['entry']! as Map<String, Object?>);
      if (restored.contains(entry.id)) continue;
      kept.add(ui.Trashed(entry, day));
    }
    return kept.reversed.toList();
  }

  /// The closes last fetched, kept so holdings are valued offline: the
  /// prices, the day's change per share and the listed names.
  void _restoreQuotes() {
    final kept = _events(_quotesKind);
    if (kept.isEmpty) return;
    final last = kept.last;
    Map<String, Object?> part(String key) =>
        last[key] as Map<String, Object?>? ?? const {};
    for (final MapEntry(:key, :value) in part('prices').entries) {
      if (value is num) _quotes[key] = value.toDouble();
    }
    for (final MapEntry(:key, :value) in part('moves').entries) {
      if (value is num) _moves[key] = value.toDouble();
    }
    for (final MapEntry(:key, :value) in part('names').entries) {
      if (value is String) _names[key] = value;
    }
    if (last['on'] case final String on) _quotedOn = DateTime.tryParse(on);
  }

  /// The board last fetched, kept so foreign accounts are valued offline.
  Map<String, double> _keptRates() {
    final kept = _events(_ratesKind);
    if (kept.isEmpty) return const {};
    final rates = kept.last['rates']! as Map<String, Object?>;
    return {
      for (final MapEntry(:key, :value) in rates.entries)
        key: (value! as num).toDouble(),
    };
  }
}
