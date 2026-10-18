part of 'vault_journal.dart';

const _linkKind = '${appEventPrefix}recurring-link';
const _removedKind = '${appEventPrefix}recurring-removed';
const _ratesKind = '${appEventPrefix}rates';

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
