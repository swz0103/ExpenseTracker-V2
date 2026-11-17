# 帳本模組

> `core/ledger` 怎麼分：每個 Repository 擁有哪些狀態、每個既有成員搬到哪裡、一個指令怎麼走、拆分進度。理由見 [ADR-0008](adr/0008-ledger-aggregates.md)，名稱對照見 [naming.md](naming.md)。

## 資料夾

```
core/ledger/
  ledger.dart              Ledger：組合各 Repository、Service、Commands，通知畫面，持有 WriteQueue
  amount_visibility.dart   隱藏金額開關
  card_cycle.dart          信用卡帳期（Account 的擴充）
  portfolio.dart           持股重播（證券用語 Portfolio）
  trading.dart             台股代號與手續費建議
  models/                  account category entry holding budget recurring trashed，一型別一檔，不含狀態
  cache/                   query_cache · topic · topic_notifier
  repositories/            擁有狀態：entry account category budget recurring trash holding market_data draft receipt
  services/                由狀態算出結果：balance statement report entry_query budget recurring · entry_validator
  commands/                寫入：entry account category budget recurring holding attachment · command_context · command_exceptions
  persistence/             ledger_data_source · write_batch · unit_of_work · write_queue · sql_ledger_data_source ·
                           record_version · category_id_migration
  persistence/codec/       一種紀錄一檔的 JSON 轉換
```

依賴只往下：`models` ← `cache` ← `repositories` ← `services` ← `commands`；根目錄的輔助檔（`card_cycle`、`portfolio`、`trading`、`amount_visibility`）只用 `models`。Commands 對 `persistence` 只用 `write_batch` 與 `unit_of_work`。`persistence` 與 `ledger.dart` 組出整本帳，可以用全部。`layers_test` 逐條檢查，也禁止 `part`。

## Ledger 上有什麼

- **Repository**（只讀的 `*Reader`，複數名詞）：`accounts` · `categories` · `entries` · `holdings` · `budgets` · `recurring` · `trash` · `marketData` · `receipts` · `drafts`。只看一種紀錄的問題在這裡問，例如 `ledger.entries.inMonth(y, m)`、`ledger.accounts.main`、`ledger.marketData.toHome(...)`。
- **Service**（只讀、跨 Repository）：`balanceService` · `statementService` · `reportService` · `entryQueryService` · `budgetService` · `recurringService` · `entryValidator`。
- **Commands**（寫入）：`entryCommands` · `accountCommands` · `categoryCommands` · `budgetCommands` · `recurringCommands` · `holdingCommands` · `attachmentCommands`。
- **Ledger 自己**：`today` · `checkDay` · `newId` · `settled` · `problem` · `dataSource` · `watch` · `revision` · `revisionOf` · `amounts` · `resetTo`，以及 `account(id)`、`category(name)`、`holding(code)` 三個全 App 用上百次的轉呼叫。

Service 與 Commands 在第一次用到時才建立，共用同一組 Repository 與同一個 `QueryCache`。Commands 經 `CommandContext`（Core J2EE Patterns 的 Context Object）取得今天、通知畫面、交出 `WriteBatch`，不直接碰 `Ledger`。

## 成員分配

| 類別 | 讀或寫 | 成員 |
| --- | --- | --- |
| **EntryReader** | 讀 | all · length · isEmpty · byId · inMonth · onDay · firstDate · refundedTotal |
| **AccountReader** | 讀 | all · open · byId · contains · resolve · main |
| **CategoryReader** | 讀 | all · byName · forEntries · isNameFree |
| **HoldingReader** | 讀 | all · byCode · hasQuote · lotsOf · saleCost · sharesOn · holdsWith · marketValue · costBasis · dayChange · realizedGain · dividends |
| **MarketDataReader** | 讀 | quotedOn · rates · moves · quoteDays · rateOf · moveOf · olderQuote · toHome · convert |
| **BudgetReader**、**RecurringReader**、**TrashReader**、**ReceiptReader**、**DraftReader** | 讀 | all · forCategory／byId／of… |
| BalanceService | 讀 | effect · balance · worthOf · unrated · assets · cardDebt · loanDebt · netWorthAt · weeklyChanges |
| StatementService | 讀 | billed · billedPeriods · closedBy · statement · statementDue · unbilled · instalmentsOn |
| ReportService | 讀 | income · expense · dividends · spentOn · totalsBetween · spendingBetween · merchantsBetween · tagsBetween · firstDay · owedBy · tagStats · merchantStats · tags · categoriesByUse |
| EntryQueryService | 讀 | search · merchants · categoryAt · lastAt · usual · usualTransfers · groupOf · groupLead · isGroupTail · tradesOf · refunded · refundable |
| BudgetService | 讀 | daysGone · spentOnTag · forecast · spentAgainst · allowance |
| RecurringService | 讀 | confirmationsIn · pendingDate · nextDate · nextLabel · due · upcoming · dueDayOf · worth · booking |
| EntryValidator | 讀 | problemWith · holdsWith |
| **EntryCommands** | 寫 | add · addAll · replace · replaceAll · replaceGroup · remove · removeAll · restore · restoreAll · restoreTrashed · recategorize · moveToAccount · renameTag · renameMerchant |
| **AccountCommands** | 寫 | addAccount · updateAccount · removeAccount · placeAccounts · setBalance · moveClose · isUsed |
| **CategoryCommands** | 寫 | addCategory · updateCategory · mergeCategory · placeCategories |
| **BudgetCommands** | 寫 | setBudget · removeBudget |
| **RecurringCommands** | 寫 | saveRecurring · removeRecurring · unskip · confirm · bookDue |
| **HoldingCommands** | 寫 | setMarket |
| **AttachmentCommands** | 寫 | setDraft · setReceipt · receiptFiles |

## 一個指令怎麼走

**合併分類**（跨 Repository）：`CategoryCommands.mergeCategory(from, into)` 開一個 `UnitOfWork`，依序改 `entries.changeAll`、`trash.changeEntries`、`recurring.renameCategory`、`budgets.remove`、`categories.removeMerged`；各 Repository 只改自己的狀態並回傳動到的紀錄，由指令登記到 `UnitOfWork`（Repository 不依賴它）。最後 `UnitOfWork.batch` 組成一個 `WriteBatch` 交給 `WriteQueue`，並通知受影響的 `Topic`。這些步驟不會中途失敗；會失敗的只有持股重播，見下一段。

**記一筆賣出**：`EntryCommands.add` → `entries.add` → `holdings.replay`（持股不夠丟 `StateError`，指令把 `entries` 還原後再重播一次並往上丟；刪除與還原則改成 `problem` 告知 `SharesShort`）→ `receipts` 記收據 → 送出。

**讀餘額**：`BalanceService.balance` 經 `QueryCache` 記住每個帳戶每天的答案，讀的主題是 `entries` 與 `accounts`；改預算不會讓它重算。

## 規則

- Repository 只改自己的狀態；Service 只讀；跨 Repository 的寫入只在 Commands 裡，多筆時用 `UnitOfWork`。
- 檔案不用 `part`；依賴只往下，`layers_test` 檢查。
- 新的查詢一律經 `QueryCache`；讀了哪些主題由 Reader 自動回報，只有從參數拿到的紀錄要在 `reads:` 寫明。
- `?.` 不會執行參數：先做修改，再把結果交給 `unit?.register…`。

## 進度

| 步驟 | 狀態 |
| --- | --- |
| 草稿、收據獨立成 `DraftRepository`、`ReceiptRepository`（各有 `*Reader`），11 個測試 | 完成 |
| 隱藏金額獨立成物件（`AmountVisibility`） | 完成 |
| 快取一致性測試（隨機修改 × 二十多種查詢） | 完成 |
| 規模量測（`scale_bench_test`） | 完成 |
| 錯誤記錄獨立成 `core/diagnostics`，全部 catch 記錄或說明 | 完成 |
| 儲存層改通用名稱並放進 `persistence/`（`LedgerDataSource`、`SqlLedgerDataSource`、`WriteBatch`、`Collection`、`DataSourceException`；`Area` 改 `Topic`） | 完成 |
| `WriteQueue` 獨立（依序寫入、失敗回報、清空後重讀），有 8 個行為測試 | 完成 |
| `Topic`、`TopicNotifier`（計數與通知）、`QueryCache`（依主題作廢）獨立到 `cache/`，各有單元測試與隨機比對測試 | 完成 |
| `QueryCache` 自動追蹤依賴：Service 拿到的 Reader 包一層 `Tracked*Reader`，每次讀取向快取回報主題，巢狀查詢往外傳；什麼都沒讀到時當作讀了全部。只剩參數帶進來的資料要手寫（信用卡、定期交易），隨機比對測試擴充到帳單、定期交易、匯率，刻意拿掉定期交易的手寫依賴會失敗 | 完成 |
| `UnitOfWork`（Fowler：`registerDirty`、`registerDeleted`）取代 `_before`／`_since` 的整本比對：合併分類、改名標籤、改名商家只登記動到的紀錄；各 Repository 的批次修改改為回傳動到的紀錄。14 個測試，其中 8 個隨機種子逐步比對舊的整本比對結果，並以刻意漏登記確認測試會失敗 | 完成 |
| `models/` 依型別拆檔（一型別一檔，`models.dart` 轉出） | 完成 |
| `EntryRepository`（紀錄清單與月、日、id、退款索引，寫入即自動作廢）與隨機比對測試 | 完成 |
| `EntryRepository` 索引改增量維護（記一筆後的月份／單日查詢，10 萬筆時 84／36 ms 降到 0.0／0.1 ms） | 完成 |
| `TrashRepository`（最新在前、依 id 或物件放回、改名合併時一起改），8 個測試 | 完成 |
| `AccountRepository`（id 索引隨寫入作廢、只加入新 id、原位替換、拖曳排序、移除），9 個測試 | 完成 |
| `MarketDataRepository`（匯率、當日漲跌、報價日；交出的 Map 不可改、傳入的會複製），8 個測試 | 完成 |
| `HoldingRepository`（期初持股與重播；賣超時丟出且不動原狀態，寬鬆模式略過；交出的清單之後不變），9 個測試 | 完成 |
| 分類 id：`Category.id`、`CategoryRefs`、版本 2 資料格式、舊帳本在一個交易裡自動升級，12 個升級測試（含失敗時完全不動、改名只寫一列） | 完成 |
| `CategoryRepository`（依拖曳位置排序、名稱索引、改名連同子分類、合併後子分類獨立、編輯保留 id 與位置），11 個測試；`allSpending` 移到 `models/budget.dart` | 完成 |
| `BudgetRepository`（設定、移除、改名時同名只留第一個），8 個測試 | 完成 |
| `RecurringRepository`（儲存、只替換仍在的項目、移除、分類改名），8 個測試 | 完成 |
| 各 Service 與各 Commands（7 個 Service、7 個 Commands、`CommandContext`），呼叫端 544 處由 `tool/reroute.py` 依分析器錯誤改寫；Service 38 個、Commands 17 個單獨測試，不經過 `Ledger` | 完成 |
| Ledger 只剩組合與通知（382 行，原本 650 行上限的特例已取消）；`*Reader` 成為 Ledger 上的屬性；`layers_test` 新增 ledger 內依賴方向與禁止 `part` 兩條規則，並確認故意違規會失敗 | 完成 |
| 帳本健檢 `IntegrityService`：紀錄、最近刪除、定期交易指向不存在的帳戶，退款指向不存在的原始消費；開帳時每種問題記一行到診斷記錄（只寫種類，不含名稱、金額、id），5 個測試。找不到帳戶時仍以空帳戶計算，但不再無聲 | 完成 |
