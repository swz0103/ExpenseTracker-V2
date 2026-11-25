import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ledger/trading.dart';
import '../../accounts/forms/account_editor.dart';
import '../../categories/forms/category_editor.dart';
import '../../../core/platform/scan.dart';
import '../model/receipt_photos.dart';

export '../model/compose_form.dart' show ComposeMode;

export 'compose_mode_look.dart';
import 'composer_state.dart';

/// A choice opened inside the sheet in place of the form, such as the
/// accounts: its title, what it shows, and how it is left without one.
final class ComposerPage {
  const ComposerPage(this.title, this.body, this.close);

  final String title;
  final Widget body;
  final VoidCallback close;
}

/// How the composer was left, when not just closed.
enum ComposeOutcome { saved, deleted, refund }

/// Opens the composer as a bottom sheet for a new entry of [type] (filled
/// in from [draft] if given), to show and change [entry], or to refund
/// [refundOf]. A trade's fee is suggested at [brokerDiscount]. Returns
/// what happened and the entry, or null when closed.
Future<(ComposeOutcome, Entry)?> openComposer(
  BuildContext context,
  Ledger ledger, {
  EntryType type = EntryType.expense,
  Entry? entry,
  Entry? draft,
  Entry? refundOf,
  ReceiptPhotos? photos,
  ScanQr? scan,
  int brokerDiscount = defaultBrokerDiscount,
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
      brokerDiscount: brokerDiscount,
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
    this.brokerDiscount = defaultBrokerDiscount,
    this.categoryEditor = showCategoryEditor,
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
  final ScanQr? scan;

  /// The broker's discount a trade's fee is suggested at, in basis points
  /// of the full fee: the preference 券商手續費折扣, for an account
  /// without its own.
  final int brokerDiscount;

  /// Opens the form of a new category picked from the form: the
  /// categories' editor, which the form's state reaches through here.
  final Future<Category?> Function(
    BuildContext context, {
    required String title,
    required Category initial,
    required List<Color> colors,
    Ledger? ledger,
  })
  categoryEditor;

  @override
  State<Composer> createState() => ComposerState();
}
