import 'dart:convert';

import '../../../core/ledger/ledger.dart';
import '../../../core/ledger/persistence/codec/record_json.dart';
import 'compose_form.dart';

/// A form put aside with 暫存: the entry as it stood and the receipt
/// photo chosen for it, which is not part of the entry until it is saved.
final class ComposeDraft {
  const ComposeDraft(this.entry, this.receipt, [this.lent]);

  final Entry entry;
  final String? receipt;

  /// What was paid in the spending for others, by person.
  final List<(String, int)>? lent;

  /// The draft as text, to keep.
  String toJson() => jsonEncode({
    'entry': entryToJson(entry),
    'receipt': ?receipt,
    if (lent case final shares?)
      'lent': [
        for (final (p, a) in shares) [p, a],
      ],
  });

  /// The draft kept as [json]; null when there is none, or it cannot be
  /// read, which leaves it out rather than stopping the form.
  static ComposeDraft? read(String? json) {
    if (json == null) return null;
    try {
      if (jsonDecode(json)
          case {'entry': final Map<String, Object?> entry} &&
              final Map<String, Object?> map) {
        return ComposeDraft(
          entryFromJson(entry),
          switch (map['receipt']) {
            final String name => name,
            _ => null,
          },
          switch (map['lent']) {
            final List<Object?> shares => [
              for (final p in shares)
                if (p case [final String person, final int amount])
                  (person, amount),
            ],
            _ => null,
          },
        );
      }
      return null;
    } on Object {
      // A form that cannot be read is left out.
      return null;
    }
  }
}

/// Forms put aside with 暫存, by tab, kept in the ledger they were
/// written for, so they outlast the app being closed by the phone.
final class ComposeDrafts {
  const ComposeDrafts(this._drafts, this._commands);

  final DraftReader _drafts;
  final AttachmentCommands _commands;

  ComposeDraft? operator [](ComposeMode tab) =>
      ComposeDraft.read(_drafts.of(tab.name));

  void operator []=(ComposeMode tab, ComposeDraft draft) =>
      _commands.setDraft(tab.name, draft.toJson());

  void remove(ComposeMode tab) => _commands.setDraft(tab.name, null);
}
