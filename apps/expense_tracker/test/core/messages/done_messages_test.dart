import 'package:expense_tracker/src/core/messages/done_messages.dart';
import 'package:flutter_test/flutter_test.dart';

/// D82: what each note says once a change is made, a single sentence
/// without 。 (D81).
void main() {
  test('each change is said in its own words', () {
    expect(DoneWords.deleted('午餐'), '已刪除「午餐」');
    expect(DoneWords.deletedBooking('房租'), '已刪除「房租」，這一期跳過');
    expect(DoneWords.deletedEntries(3), '已刪除 3 筆');
    expect(DoneWords.archived('舊卡'), '已封存「舊卡」');
    expect(DoneWords.unarchived('舊卡'), '已恢復「舊卡」');
    expect(DoneWords.merged('早餐', '飲食'), '已把「早餐」合併到「飲食」');
    expect(DoneWords.renamed('#旅行', '#出遊'), '已把「#旅行」改成「#出遊」');
    expect(DoneWords.budgetDeleted('#家用'), '已刪除「#家用」的額度');
    expect(DoneWords.imported(12), '已匯入 12 筆紀錄');
  });
}
