/// What 掃發票 says of the invoice read: a code that is not the left one,
/// one already kept, the items still on the right code, and an invoice
/// filled from its left code alone when the right one could not be read.
abstract final class InvoiceMessages {
  /// A code read that is not a paper e-invoice's left one.
  static const notLeft = '這不是電子發票左邊的 QR Code，請掃左邊那個';

  /// The left code says more items are on the right one.
  static const scanRight = '還有品項在右邊的 QR Code，請再掃一次';

  /// The right code was not read: the items it carries are not known.
  static const itemsUnread = '品項未讀到';

  /// Before the seller's tax id in the note.
  static const seller = '統編';

  /// Said when the form was filled from the left code alone (D30).
  static const filledWithoutItems =
      '$itemsUnread：已用左邊的 QR Code 填入金額、日期、賣方統編與發票號碼，可以再修改';

  /// An invoice already in the book.
  static String recorded(String number) => '發票 $number 已經記過了';
}
