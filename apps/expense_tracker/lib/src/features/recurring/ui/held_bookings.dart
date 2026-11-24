import 'package:flutter/material.dart';

import '../../../core/design_system/dialogs.dart' show confirm;
import '../../../core/design_system/feedback.dart' show showNote;
import '../../../core/ledger/ledger.dart';
import '../../../core/messages/recurring_messages.dart';

/// What the automatic booking left (D61, R5), told as the ledger opens
/// and comes back: asked once before booking the items with more than
/// one day waiting, and said once what could not be booked by itself.
final class HeldBookings {
  /// What was told already, so coming back does not ask again about the
  /// same days.
  final _told = <String>{};

  /// Tells in [context] how many days were [booked] by themselves, then
  /// [held]: the question first, then [notice] with what could not be
  /// booked by itself.
  Future<void> tell(
    BuildContext context,
    Ledger ledger,
    int booked,
    List<HeldBooking> held, {
    required Future<void> Function(String title, String text) notice,
  }) async {
    if (booked > 0) showNote(context, autoBooked(booked));
    final fresh = [
      for (final h in held)
        if (_told.add('${h.item.id}:${h.days.length}:${h.days.first}')) h,
    ];
    final asked = [
      for (final h in fresh)
        if (h.confirmable) h,
    ];
    final refused = [
      for (final h in fresh)
        if (!h.confirmable) h,
    ];
    if (asked.isNotEmpty && context.mounted) {
      final ok = await confirm(
        context,
        heldTitle,
        heldConfirm,
        body: heldBody(asked),
      );
      if (ok) {
        var count = 0;
        for (final h in asked) {
          count += ledger.recurringCommands.bookDays(h.item, h.days);
        }
        if (context.mounted && count > 0) {
          showNote(context, heldBooked(count));
        }
      }
    }
    if (refused.isNotEmpty && context.mounted) {
      await notice(heldRefusedTitle, refused.map(heldLine).join('\n'));
    }
  }
}
