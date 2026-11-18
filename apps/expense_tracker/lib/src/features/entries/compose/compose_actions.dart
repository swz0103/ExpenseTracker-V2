import 'package:flutter/widgets.dart';

import '../../../core/ledger/ledger.dart';
import '../model/compose_form.dart';
import '../model/receipt_photos.dart';

/// What a section of the entry form, such as its investment fields, asks of
/// the form it is in: its fields and how it looks, to change the fields
/// and draw again, to ask for a figure or a choice, and the pieces every
/// tab shares.
abstract interface class ComposeActions {
  /// The fields and their rules.
  ComposeForm get form;

  /// Whether the entry is only looked at, nothing to change.
  bool get viewing;

  /// The colour of the tab.
  Color get color;

  /// The note as typed.
  TextEditingController get note;

  /// Makes [change] to the fields and draws the form again.
  void update(VoidCallback change);

  /// Asks for a whole figure on the keypad, [title] over it in [unit];
  /// null when it is closed.
  Future<int?> ask(String title, int initial, {String unit = homeCode});

  /// Asks for the amount on the keypad and keeps it.
  Future<void> calculate();

  /// Opens every holding to pick the trade's.
  Future<void> pickHolding();

  /// Turns the trade into [trade]: a buy, a sale or a dividend.
  void changeTrade(EntryType trade);

  /// The amount in the middle of the form, [under] it such as 常用, in
  /// [unit] when not the account's currency.
  Widget hero({Widget? under, String? unit});

  /// Two fields side by side.
  Widget pair(Widget left, Widget right);

  /// The account the entry is on, called [label].
  Widget accountPick(String label);

  /// The day of the entry.
  Widget datePick();

  /// Where receipt photos come from; null where there are none, as in
  /// tests.
  ReceiptPhotos? get photos;

  /// Opens the merchants to pick or type one.
  Future<void> pickMerchant();

  /// Opens the tags to pick or type any.
  Future<void> pickTags();

  /// The receipt photo as a square beside the note.
  Widget receiptSquare(ReceiptPhotos photos);

  /// Whether an entry already kept is being changed.
  bool get editing;

  /// Picks whom the money is for or from, or adds a new person.
  Future<void> pickPerson();

  /// Picks whom a spending is paid for, any number of people.
  Future<void> pickLent();

  /// Back from 代墊 or 對方還錢 to a plain entry of the same tab.
  void unlend();

  /// The row of categories, those of spending when [expense].
  Widget categories({required bool expense});
}
