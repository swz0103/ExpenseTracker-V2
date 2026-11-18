import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/look/dialogs.dart';
import '../../../core/text/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/ui/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ledger/trading.dart';
import '../../accounts/compose/account_editor.dart';
import '../../../core/ui/calculator.dart';
import '../../categories/compose/category_editor.dart';
import '../../../core/ui/pickers.dart';
import '../model/compose_draft.dart';
import '../model/compose_form.dart';
import '../../../core/messages/installment_messages.dart';
import '../model/receipt_photos.dart';
import '../../import_export/model/import_export.dart' show invoiceRecorded;
import '../../import_export/model/invoice_qr.dart';
import '../../../core/ui/shown_amounts.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../core/text/dates.dart';
import '../../../core/look/spacing.dart';

export '../model/compose_form.dart' show ComposeMode;

import 'compose_cards.dart';
import 'compose_mode_look.dart';
import 'compose_widgets.dart';
import 'entry_view_card.dart';
import 'compose_actions.dart';
import 'extras_fields.dart';
import 'investment_fields.dart';
import 'lend_fields.dart';
import 'fill_layout.dart';
import 'form_frame.dart';
import 'form_rows.dart';
import 'holding_choices.dart';
import 'note_field.dart';
import 'people_choices.dart';
import 'receipt_square.dart';

export 'compose_mode_look.dart';

part 'composer_fields.dart';
part 'composer_lend.dart';
part 'composer_state.dart';
part 'composer_extras.dart';
part 'composer_pickers.dart';
part 'composer_amount.dart';

/// A choice opened inside the sheet in place of the form, such as the
/// accounts: its title, what it shows, and how it is left without one.
final class _Page {
  const _Page(this.title, this.body, this.close);

  final String title;
  final Widget body;
  final VoidCallback close;
}

/// How the composer was left, when not just closed.
enum ComposeOutcome { saved, deleted, refund }

/// Opens the composer as a bottom sheet for a new entry of [type] (filled
/// in from [draft] if given), to show and change [entry], or to refund
/// [refundOf]. Returns what happened and the entry, or null when closed.
Future<(ComposeOutcome, Entry)?> openComposer(
  BuildContext context,
  Ledger ledger, {
  EntryType type = EntryType.expense,
  Entry? entry,
  Entry? draft,
  Entry? refundOf,
  ReceiptPhotos? photos,
  Future<String?> Function()? scan,
}) async {
  if (!await ensureAccount(context, ledger) || !context.mounted) return null;
  return showSheet<(ComposeOutcome, Entry)>(
    context,
    (_) => Composer(
      ledger: ledger,
      type: entry?.type ?? draft?.type ?? type,
      entry: entry,
      draft: draft,
      refundOf: refundOf ?? _original(ledger, entry),
      photos: photos,
      scan: scan,
    ),
    capHeight: true,
  );
}

/// The spending a refund gives back, when [entry] is one.
Entry? _original(Ledger ledger, Entry? entry) {
  final id = entry?.refundOf;
  return id == null ? null : ledger.entries.byId(id);
}

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.ledger,
    required this.type,
    this.entry,
    this.draft,
    this.refundOf,
    this.photos,
    this.scan,
  });

  final Ledger ledger;
  final EntryType type;

  /// The entry being changed, if any.
  final Entry? entry;

  /// A new entry's starting values, such as a card payment.
  final Entry? draft;

  /// The spending being refunded, for a refund.
  final Entry? refundOf;

  /// The phone's receipt photos; none in the preview, which hides them.
  final ReceiptPhotos? photos;

  /// Reads a QR code with the camera, for a paper e-invoice; none in the
  /// preview.
  final Future<String?> Function()? scan;

  @override
  State<Composer> createState() => _ComposerState();
}
