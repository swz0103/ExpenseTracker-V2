/// What the pages say where a way on or out is offered (D85): a list with
/// nothing on it, the tour.
abstract final class FlowWords {
  /// 收支紀錄 with nothing written yet (no search, no filter).
  static const noEntriesYet = '還沒有紀錄';

  /// 收支紀錄 on a month with nothing written, in a book that has entries
  /// in other months (D117).
  static const noEntriesThisMonth = '這個月還沒有紀錄';

  /// What writes the first one.
  static const addEntry = '記一筆';

  /// 收支紀錄 where the search or the filters leave nothing.
  static const noMatches = '沒有符合篩選的紀錄';

  /// What takes the search and the filters away.
  static const clearFilters = '清除篩選';

  /// The preview's 重設範例資料: asked first, with what it clears.
  static const resetSample = '重設';
  static const resetSampleAsk = '重設範例資料？';
  static const resetSampleBody = '目前的變更會清除';

  /// Asked when there is no account to write into, and its yes.
  static const needAccount = '還沒有帳戶';
  static const needAccountBody = '先新增一個帳戶，才能記帳';
  static const addAccount = '新增帳戶';

  /// Under the question of a reconciling entry: the balance kept, the
  /// one counted and the gap the entry closes.
  static String reconcileGap(String book, String counted, String gap) =>
      '帳上 $book，實際 $counted，差 $gap';

  /// Ends the tour at any stop.
  static const skipTour = '略過';

  /// 我的帳戶 with no account yet.
  static const noAccountsYet = '還沒有帳戶，按右上的新增開始';

  /// 代墊與借貸 with no one paid for yet: how someone comes on it.
  static const noPeopleYet = '記一筆支出時按「代墊」選人，幫忙付的錢就會記在這裡，收回時在收入選「對方還錢」';

  /// 代墊與借貸 with no loan yet.
  static const noLoansYet = '房貸、信貸或車貸，按右上的＋新增';
}

/// What settling an account or a person before archiving says: where the
/// money left goes, or what pays the debt; with no account of its
/// currency, the offer to add one or keep it (review 35).
abstract final class SettleWords {
  /// The picker's title: money left goes to an account.
  static const moveTo = '餘額轉到哪個帳戶';

  /// The picker's title: a debt is paid from an account.
  static const payFrom = '由哪個帳戶結清欠款';

  /// No open account of [currency] (its name) to settle with.
  static String noAccount(String currency) => '沒有$currency的帳戶可以結清';

  /// What can be done about it, for [name].
  static String noAccountBody(String name) => '要先新增一個同幣別的帳戶來結清，還是保留「$name」不封存？';

  static const addAccount = '新增帳戶';
  static const keep = '保留';

  /// The person page's question before someone with money left is
  /// settled and archived, for [name], under the archive rule's words.
  static String owingBody(String name) => '要記一筆結清，再封存「$name」嗎？';
}
