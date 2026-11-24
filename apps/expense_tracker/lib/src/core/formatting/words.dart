/// Words the app says in many places, kept here so each reads the same
/// everywhere and changes in one place: the kinds of money, the actions
/// on a panel, and the names of what a book holds. A page writes
/// `Words.income`, never '收入' itself (`design_rules_test`).
abstract final class Words {
  // The kinds of money.
  static const income = '收入';
  static const expense = '支出';

  /// Spending given back: an income entry that refunds an expense.
  static const refund = '退款';
  static const transfer = '轉帳';
  static const dividend = '股息';
  static const investment = '投資';
  static const fee = '手續費';
  static const lend = '代墊';

  // What a book holds.
  static const account = '帳戶';
  static const category = '分類';
  static const tag = '標籤';
  static const merchant = '商家';

  /// An e-invoice: the tag an invoice entry carries, and the word its
  /// number follows in the note (`invoiceNote`).
  static const invoice = '發票';
  static const receipt = '收據';
  static const date = '日期';
  static const amount = '金額';
  static const note = '備註';

  /// What an amount in a foreign currency is worth at home, in NT$: the
  /// form's row, an entry's details and what asks for it. Not the column
  /// of an imported file, which is `homeAmountColumn` (台幣金額).
  static const homeWorth = '折合新台幣';

  // Actions.
  static const cancel = '取消';
  static const delete = '刪除';
  static const done = '完成';
  static const edit = '編輯';
  static const add = '新增';
  static const back = '返回';

  // Leaving a form with changes (D83).
  static const discardAsk = '要捨棄修改嗎？';
  static const discard = '捨棄';
  static const keepEditing = '繼續編輯';

  // Days and months.
  static const today = '今天';
  static const previousMonth = '上個月';
  static const nextMonth = '下個月';
}
