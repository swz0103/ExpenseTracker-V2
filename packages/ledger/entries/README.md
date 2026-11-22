# ledger_entries

> 一筆紀錄是什麼、能不能寫進帳本：「資料是否合法」唯一的出處。純 Dart，只依賴 `core` 與 `ledger_trade_costs`（`Entry.settlement` 用它算交易的錢）。

## 做什麼

- `Entry`（一筆紀錄）、`EntryType`、`AccountKind` 與帳本固定的分類名稱（轉帳、投資、股息收入、其他支出）。
- 寫入規則，全部是純函式：輸入紀錄本身和少數事實（帳戶的種類與幣別、帳戶在不在、持股、可退金額、扣款後餘額），輸出問題清單。
- 問題分兩種嚴重度：`error` 拒絕寫入；`warning` 儲存前提醒、仍可儲存（目前只有「買股票後扣款帳戶餘額為負」）。
- 紀錄：金額大於 0 且不超過 App 唯一的上限（`core` 的 `maxMinorUnits`：台幣 999,999,999、美元 999,999,999.99）、日期是 UTC 午夜、轉帳要有另一個存在的轉入帳戶、外幣收支要有台幣金額、拆分每項大於 0 且合計等於總額、分期只限信用卡支出且 0–60 期，以及原有的投資、退款、卡費規則。
- 定期項目：金額大於 0、間隔至少 1、日期 1–31、結束不早於開始。
- 帳戶：名稱不可空白、結帳日與繳款日 1–31、信用額度不為負。預算：額度不為負、提醒比例 1–100%。
- 從備份讀回的紀錄另有一組「形狀」規則（`entryShapeIssues` 等）：只拒絕任何版本都不會寫出、也無法計算的資料，舊帳本照樣能還原。

## 對外入口

| 入口 | 內容 |
| --- | --- |
| `model.dart` | `Entry`、`EntryType`、`AccountKind`、`AccountFacts`、`homeCode`、`transferCategory` 等 |
| `rules.dart` | `entryIssues`、`EntryFacts`、`RefundFacts`、`entryShapeIssues`、`recurringIssues`、`accountIssues`、`budgetIssues`（及各自的 shape 版本）、`RecordIssue` 與各問題、`Severity` |

## 不做什麼

- 不讀帳本、不保存狀態：事實由 App 的 `EntryValidator` 查好傳進來；強制執行在 App 的寫入指令。
- 不含文字：問題是值，給人看的字在 App 的 `core/messages`。
