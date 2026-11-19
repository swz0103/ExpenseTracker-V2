import 'package:flutter/material.dart';

import '../../../core/look/keys.dart';
import '../../../core/look/spacing.dart';
import '../model/compose_form.dart';
import 'compose_actions.dart';
import 'compose_chips.dart';
import 'fields_fold.dart';
import 'note_field.dart';
import '../../../core/text/words.dart';

/// The merchant, tags, note and receipt under one heading at the foot of
/// the entry form, opened and closed with it; closed, the heading shows
/// what is filled in. Open, they are no list: the note a large box with
/// the receipt beside it, merchants and tags words to tap in a row.
final class ExtrasFields {
  const ExtrasFields(this._a);

  final ComposeActions _a;

  ComposeForm get _f => _a.form;

  /// The fold, the merchant only for a spending ([expense]).
  Widget build({required bool expense}) {
    final filled = [
      if (expense && _f.merchant.isNotEmpty) _f.merchant,
      for (final tag in _f.tags) '#$tag',
      if (_a.note.text.trim().isNotEmpty) _a.note.text.trim(),
      if (_f.receipt != null) Words.receipt,
    ];
    final photos = _a.photos;
    final withPhoto = photos != null || _f.receipt != null;
    if (_a.viewing && filled.isEmpty) return const SizedBox.shrink();
    final open = _f.more || _a.viewing;
    final names = [
      if (expense) Words.merchant,
      Words.tag,
      Words.note,
      if (withPhoto) Words.receipt,
    ];
    return FieldsFold(
      headingKey: Keys.extras,
      viewing: _a.viewing,
      onToggle: () => _a.update(() => _f.more = !_f.more),
      closed: filled.isEmpty ? names.join('、') : filled.join(' · '),
      open: open,
      body: [
        // The square as tall as the note box and level with it.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: NoteField(
                  controller: _a.note,
                  viewing: _a.viewing,
                  lines: 3,
                ),
              ),
              if (photos != null && (!_a.viewing || _f.receipt != null)) ...[
                const SizedBox(width: Space.s2),
                Padding(
                  padding: const EdgeInsets.only(top: Space.s2),
                  child: _a.receiptSquare(photos),
                ),
              ],
            ],
          ),
        ),
        if (expense && (!_a.viewing || _f.merchant.isNotEmpty)) ...[
          const GroupLabel(Words.merchant),
          WordRow([
            for (final name in _f.merchantChoices())
              WordChip(
                name,
                () => _a.update(() => _f.toggleMerchant(name)),
                color: _a.color,
                picked: name == _f.merchant,
              ),
            if (!_a.viewing) WordChip('＋', _a.pickMerchant, color: _a.color),
          ]),
        ],
        if (!_a.viewing || _f.tags.isNotEmpty) ...[
          const GroupLabel(Words.tag),
          WordRow([
            for (final tag in _f.tagChoices())
              WordChip(
                '#$tag',
                () => _a.update(() => _f.toggleTag(tag)),
                color: _a.color,
                picked: _f.tags.contains(tag),
              ),
            if (!_a.viewing) WordChip('＋', _a.pickTags, color: _a.color),
          ]),
        ],
      ],
    );
  }
}
