# 帳本模組

> `core/ledger` 怎麼分：每個 Repository 擁有哪些狀態、每個既有成員搬到哪裡、一個指令怎麼走、拆分進度。理由見 [ADR-0008](adr/0008-ledger-aggregates.md)，名稱對照見 [naming.md](naming.md)。

## 資料夾

```
core/ledger/
  ledger.dart              Ledger：接線、UnitOfWork、通知（只留 14 個成員）
  amount_visibility.dart   隱藏金額開關
  models/                  account category entry holding lot budget recurring trashed，一型別一檔，不含狀態
  repositories/            擁有狀態：entry account category budget recurring trash holding market_data draft receipt
  services/                由狀態算出結果：balance statement budget recurring report portfolio entry_validator
  cache/                   query_cache（依賴自動追蹤）· topic（變動主題）
  persistence/             ledger_data_source · sql_ledger_data_source · write_batch · write_queue ·
                           unit_of_work · starter_data · record_upgrade
  persistence/codec/       一種紀錄一檔的 JSON 轉換 · json_reader（有型別的讀取，取代 `as` 強轉）
```

`Ledger` 上的屬性：Repository 用複數名詞（`ledger.accounts`），Service 用完整類別名（`ledger.balanceService`）。

## 成員分配

「現名」是審查時 `Ledger` 上的成員；每一列是新家。

| 新家 | 擁有的狀態 | 成員 |
| --- | --- | --- |
| **EntryRepository** | 全部紀錄、月／日／id／退款索引 | entries · entriesIn · entriesOn · byId · add · addAll · replace · replaceAll · replaceGroup · remove · removeAll · groupOf · groupLead · isGroupTail · tradesOf · refunded · refundable · search · usual · usualTransfers · merchants · categoryAt · lastAt |
| **TrashRepository** | 最近刪除 | trash · restore · restoreAll · restoreTrashed |
| **AccountRepository** | 帳戶、id 索引 | accounts · account · hasAccount · openAccounts · mainAccount · addAccount · updateAccount · removeAccount · isUsed · placeAccounts · setBalance · moveClose |
| **CategoryRepository** | 分類、索引（之後以 id） | categories · category · categoriesFor · categoryNameFree · addCategory · updateCategory · mergeCategory · placeCategories |
| **BudgetRepository** | 預算 | budgets · setBudget · removeBudget · budgetFor |
| **RecurringRepository** | 定期交易 | recurring · saveRecurring · removeRecurring · dueDayOf · unskip · recurringWorth · booking · confirm · bookDue |
| **MarketDataRepository** | 收盤價、當日漲跌、匯率、報價日 | setMarket · quotedOn · hasQuote · olderQuote · rates · toHome · convert · unrated |
| **HoldingRepository** | 期初持股、重播出的持股 | holdings · holding · lotsOf · saleCost · holdsWith · investValue · investCost · dayChange · realized · totalDividends |
| **DraftRepository**、**ReceiptRepository** | 暫存表單、收據檔名 | draft · setDraft · receiptOf · setReceipt · receiptFiles |
| BalanceService | — | balance · worthOf · assets · cardDebt · loanDebt · netWorthAt · weeklyChanges |
| StatementService | — | billed · billedPeriods · closedBy · statement · statementDue · unbilled · instalmentsOn |
| BudgetService | — | daysGone · spentOnTag · forecast · spentAgainst · allowance |
| RecurringService | — | confirmationsIn · pendingDate · nextDate · nextLabel · due · upcoming |
| ReportService | — | income · expense · dividends · spentOn · expenseByCategory · totalsBetween · spendingBetween · merchantsBetween · tagsBetween · tagStats · merchantStats · tags · categoriesByUse · owedBy · effect · firstDay |
| EntryValidator | — | problemWith |

### Ledger 留下的成員

`today` · `checkDay` · `newId` · `settled` · `problem` · `dataSource` · `watch` · `revision` · `revisionOf` · `amounts` · `resetTo` · `account(id)` · `category(name)` · `holding(code)`。後三個只是轉呼叫各 Repository，因為全 App 用了上百次。

## 一個指令怎麼走

**合併分類**（跨 Repository）：`Ledger.mergeCategory(from, into)` 開一個 `UnitOfWork`，依序叫 `entries.moveCategory`、`trash.moveCategory`、`recurring.moveCategory`、`budgets.drop`、`categories.remove`；各 Repository 把動到的紀錄登記到 `UnitOfWork`。全部成功後 `UnitOfWork` 組成一個 `WriteBatch` 交給 `WriteQueue`，並通知受影響的 `Topic`。任何一步失敗就逐一還原，畫面沒有半個狀態。

**記一筆賣出**：`entries.add` → `holdings.replay`（持股不夠丟 `SharesShort`，`UnitOfWork` 還原 `entries`）→ `receipts` 記收據 → 送出。

**讀報表**：`ReportService` 在 `QueryCache` 裡執行；它讀了 `entries` 與 `accounts`，快取記下這兩個依賴，之後只有這兩個變動才作廢，改預算不會動它。

## 規則

- Repository 只改自己的狀態；Service 不持有狀態。
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
| `WriteQueue` 獨立 | 尚未 |
| `QueryCache` 與自動依賴、`Topic` | 尚未 |
| `UnitOfWork` 取代 `_before`／`_since` | 尚未 |
| `models/` 依型別拆檔（一型別一檔，`models.dart` 轉出） | 完成 |
| `EntryRepository` 與增量索引 | 尚未 |
| Trash、Account、MarketData、Holding Repository | 尚未 |
| `CategoryRepository` 與分類 id | 尚未 |
| Budget、Recurring Repository 與各 Service | 尚未 |
| Ledger 瘦身與 `layers_test` 新規則 | 尚未 |
