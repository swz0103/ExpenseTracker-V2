# kernel

> 分錄（posting）的核心，純 Dart（只用 `core`）：使用者記的那一筆（意圖，`LedgerIntent`）是唯一真相，分錄由它算出、可以整批丟掉重建。

## 做什麼

- 具型別的 id（`AccountId`、`IntentId`、`IntentType`、`OwnerId`、`CurrencyCode`）與日期 `Day`（yyyymmdd 一個整數，邊界用 core 的 `BusinessDate`）。
- 分錄 `Posting`：帳戶、幣別、金額、日期，加上**數量**（股數，以百萬分之一股為單位，`quantityScale`；由 10^-12 股換算時檢查，不默默取位）與**子帳鍵** `sub`（一批買進）。
- 記帳規則 `PostingRule`：只讀「這一筆」與「它之前的分錄」（`RuleContext.before`），不讀設定。其他擁有者以 `Amender`（修訂者）改寫可修訂種類的分錄（外幣、分期）。
- 唯一的寫入路徑 `Journal`：`put`／`putAll`／`delete`／`rematerialise`，同一串（stream）之後的各筆在同一個交易內重算；結果是型別：`Written`，或 `Unbalanced`、`UnknownAccount`、`CurrencyMismatch`、`UnknownIntentType`、`IntentNotFound`、`RuleRejected`、`UnknownAmendment`（什麼都沒改）。每次寫入檢查：每筆在每種幣別內加總為零，有幣別的帳戶只收它的幣別。
- `BookReader`：某天的餘額、期間收支（依帳戶類別與 `inFlowReports`）、淨值（估值器 `valuers`）、依子帳鍵的批次、各幣別總和（應為零）。
- 擴充點：`ContributionPoint`，寫法 `contributions.on(point).add(owner, item)`。
- `MemoryPostingStore`：記憶體內的 `PostingStore`，與檔案版一樣維護每月合計。

## 不做什麼

- 不知道任何一種紀錄的意思（在 `packages/ledger/postings`）；不碰檔案（SQL 版在 `infrastructure/storage`）。
