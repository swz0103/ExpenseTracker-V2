# 帳本模組

> `core/ledger` 怎麼分：每個 Repository 擁有哪些狀態、每個既有成員搬到哪裡、一個指令怎麼走、拆分進度。理由見 [ADR-0008](adr/0008-ledger-aggregates.md)，名稱對照見 [naming.md](naming.md)。

## 資料夾

```
core/ledger/
  ledger.dart              Ledger：接線、通知、WriteQueue（只留 14 個成員）
  amount_visibility.dart   隱藏金額開關
  models/                  account category entry holding budget recurring trashed，一型別一檔，不含狀態
  repositories/            擁有狀態：entry account category budget recurring trash holding market_data draft receipt
  services/                由狀態算出結果：balance statement budget recurring report portfolio entry_validator
  commands/                協調寫入：entry account category budget recurring holding attachment；unit_of_work
  cache/                   query_cache · topic · topic_notifier
  persistence/             ledger_data_source · sql_ledger_data_source · write_batch · write_queue ·
                           starter_data · record_upgrade
  persistence/codec/       一種紀錄一檔的 JSON 轉換 · json_reader（有型別的讀取，取代 `as` 強轉）
```

`Ledger` 上的屬性：Repository 用複數名詞、型別是只讀的 `*Reader`（`ledger.accounts`）；Service 與 Commands 用完整類別名（`ledger.balanceService`、`ledger.entryCommands`）。

## 成員分配

「現名」是審查時 `Ledger` 上的成員；每一列是新家。

| 新家 | 擁有的狀態 | 成員 |
| --- | --- | --- |
| **EntryRepository** | 全部紀錄、月／日／id／退款索引 | entries · entriesIn · entriesOn · byId · groupOf · groupLead · isGroupTail · tradesOf · refunded · refundable · search · usual · usualTransfers · merchants · categoryAt · lastAt |
| **TrashRepository** | 最近刪除 | trash |
| **AccountRepository** | 帳戶、id 索引 | accounts · account · hasAccount · openAccounts · mainAccount · isUsed |
| **CategoryRepository** | 分類、索引（之後以 id） | categories · category · categoriesFor · categoryNameFree |
| **BudgetRepository** | 預算 | budgets · budgetFor |
| **RecurringRepository** | 定期交易 | recurring · dueDayOf · recurringWorth · booking |
| **MarketDataRepository** | 收盤價、當日漲跌、匯率、報價日 | quotedOn · hasQuote · olderQuote · rates · toHome · convert · unrated |
| **HoldingRepository** | 期初持股、重播出的持股 | holdings · holding · lotsOf · saleCost · holdsWith · investValue · investCost · dayChange · realized · totalDividends |
| **DraftRepository**、**ReceiptRepository** | 暫存表單、收據檔名 | draft · receiptOf · receiptFiles |
| BalanceService | — | balance · worthOf · assets · cardDebt · loanDebt · netWorthAt · weeklyChanges |
| StatementService | — | billed · billedPeriods · closedBy · statement · statementDue · unbilled · instalmentsOn |
| BudgetService | — | daysGone · spentOnTag · forecast · spentAgainst · allowance |
| RecurringService | — | confirmationsIn · pendingDate · nextDate · nextLabel · due · upcoming |
| ReportService | — | income · expense · dividends · spentOn · expenseByCategory · totalsBetween · spendingBetween · merchantsBetween · tagsBetween · tagStats · merchantStats · tags · categoriesByUse · owedBy · effect · firstDay |
| EntryValidator | — | problemWith |
| **EntryCommands** | — | add · addAll · replace · replaceAll · replaceGroup · remove · removeAll · restore · restoreAll · restoreTrashed · recategorize · moveToAccount · renameTag · renameMerchant |
| **AccountCommands** | — | addAccount · updateAccount · removeAccount · placeAccounts · setBalance · moveClose |
| **CategoryCommands** | — | addCategory · updateCategory · mergeCategory · placeCategories |
| **BudgetCommands** | — | setBudget · removeBudget |
| **RecurringCommands** | — | saveRecurring · removeRecurring · unskip · confirm · bookDue |
| **HoldingCommands** | — | setMarket |
| **AttachmentCommands** | — | setDraft · setReceipt |

### Ledger 留下的成員

`today` · `checkDay` · `newId` · `settled` · `problem` · `dataSource` · `watch` · `revision` · `revisionOf` · `amounts` · `resetTo` · `account(id)` · `category(name)` · `holding(code)`。後三個只是轉呼叫各 Repository，因為全 App 用了上百次。

## 一個指令怎麼走

**合併分類**（跨 Repository）：`CategoryCommands.mergeCategory(from, into)` 開一個 `UnitOfWork`，依序叫 `entries.moveCategory`、`trash.moveCategory`、`recurring.moveCategory`、`budgets.drop`、`categories.remove`；各 Repository 把動到的紀錄和還原動作登記到 `UnitOfWork`。全部成功後 `UnitOfWork` 組成一個 `WriteBatch` 交給 `WriteQueue`，並通知受影響的 `Topic`；任何一步失敗就逐一還原，畫面沒有半個狀態。

**記一筆賣出**：`EntryCommands.add` → `entries.add` → `holdings.replay`（持股不夠丟 `SharesShort`，`UnitOfWork` 還原 `entries`）→ `receipts` 記收據 → 送出。

**讀報表**：`ReportService` 在 `QueryCache` 裡執行；它讀了 `entries` 與 `accounts`，快取記下這兩個依賴，之後只有這兩個變動才作廢，改預算不會動它。

## 規則

- Repository 只改自己的狀態；Service 只讀；跨 Repository 的寫入只在 Commands 裡，用 `UnitOfWork`。
- 檔案不用 `part`；一個檔案一個公開類別。
- 依賴只有 ADR-0008 的圖上的邊，`layers_test` 檢查。
- 新的查詢一律經 `QueryCache`，不手寫失效條件。

## 進度

| 步驟 | 狀態 |
| --- | --- |
| 草稿、收據獨立成類別（目前叫 `Drafts`、`Receipts`，改名見 [naming.md](naming.md)） | 完成，待改名 |
| 隱藏金額獨立成物件（`AmountVisibility`） | 完成 |
| 快取一致性測試（隨機修改 × 二十多種查詢） | 完成 |
| 規模量測（`scale_bench_test`） | 完成 |
| 錯誤記錄獨立成 `core/diagnostics`，全部 catch 記錄或說明 | 完成 |
| 儲存層改通用名稱並放進 `persistence/`（`LedgerDataSource`、`SqlLedgerDataSource`、`WriteBatch`、`Collection`、`DataSourceException`；`Area` 改 `Topic`） | 完成 |
| `WriteQueue` 獨立（依序寫入、失敗回報、清空後重讀），有 8 個行為測試 | 完成 |
| `Topic`、`TopicNotifier`（計數與通知）、`QueryCache`（依主題作廢）獨立到 `cache/`，各有單元測試與隨機比對測試 | 完成 |
| `QueryCache` 自動追蹤依賴（取代手寫 `on:`） | 隨 Repository 完成 |
| `UnitOfWork` 取代 `_before`／`_since` 與各指令手寫的還原 | 尚未 |
| `models/` 依型別拆檔（一型別一檔，`models.dart` 轉出） | 完成 |
| `EntryRepository`（紀錄清單與月、日、id、退款索引，寫入即自動作廢）與隨機比對測試 | 完成 |
| `EntryRepository` 索引改增量維護（記一筆後的月份／單日查詢，10 萬筆時 84／36 ms 降到 0.0／0.1 ms） | 完成 |
| `TrashRepository`（最新在前、依 id 或物件放回、改名合併時一起改），8 個測試 | 完成 |
| Account、MarketData、Holding Repository | 尚未 |
| 分類 id：`Category.id`、`CategoryRefs`、版本 2 資料格式、舊帳本在一個交易裡自動升級，12 個升級測試（含失敗時完全不動、改名只寫一列） | 完成 |
| `CategoryRepository` | 尚未 |
| `BudgetRepository`（設定、移除、改名時同名只留第一個），8 個測試 | 完成 |
| Recurring Repository、各 Service 與各 Commands | 尚未 |
| Ledger 瘦身與 `layers_test` 新規則 | 尚未 |
