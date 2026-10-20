# storage

加密的 SQLite（SQLCipher）儲存：事件與操作紀錄，以及記帳指令的投影（餘額、帳單、持股、預算、定期交易）。

每一節對應一個公開入口（`package:storage/<入口>.dart`），原本是獨立的套件。

## storage_sqlcipher

基礎設施層（ADR-0001）：單一 SQLCipher 加密資料庫，實作 `app_core` 的 `UnitOfWork`。

- 一個檔案、WAL、`synchronous=FULL`；崩潰復原交給 SQLite，不自行解讀 journal。
- `events` 只能新增、`operations` 不能改或刪（觸發器強制），和業務寫入同一交易提交。
- 開啟時檢查：函式庫必須是 SQLCipher（否則 `notEncrypted`）、金鑰正確（否則 `wrongKey`，錯誤訊息不含金鑰）、schema 不比程式新（否則 `newerSchema`）。
- Migration 只能往 `lib/src/storage_sqlcipher/schema.dart` 末尾新增，每一步和 `user_version` 在同一交易。
- `bin/crash_worker.dart` 給 SIGKILL 測試用，CI 會先編譯它。

## ledger_sqlcipher

基礎設施層（ADR-0001）：`bookkeeping` 各個儲存介面的 SQLCipher 實作，加上給畫面讀的查詢。

- `ledgerSchema`：`ledger` 模組的 migration。已發佈的步驟永遠不改，只能在末尾新增（目前 12 步）。
- 原始碼依領域分檔（同一個 library 的 part）：`schema.dart`（migration）、`ledger_store.dart`（核心讀取）、`card_queries.dart`、`investment_queries.dart`、`report_queries.dart`（各領域查詢，以 extension 掛在 `LedgerStore` 上）、`sql_bookkeeping.dart`（寫入交易）。
- `LedgerStore`：寫入交易提供 `SqlBookkeeping`。投影表（餘額、帳單、持股、預算、定期交易）和事件在同一交易更新。
- `ledger_monthly`、`ledger_category_monthly` 已停用：不再寫入也不再讀取，App 的報表自行從分錄計算。表格仍留在 schema 裡，因為已發佈的 migration 不改，舊帳本也已有這兩張表。
- 查詢：
  - 帳戶、餘額、整本帳的分錄與附加資料（`book_queries.dart`）；
  - 信用卡：條款、帳單、分期；
  - 投資：投資帳戶、商品、持有中的商品、持股；
  - 定期交易：範本清單、到期的項目。
- `LedgerReplay`：從事件日誌重建所有投影表；`projectionRows` 用來逐列比對。
- `package:storage/testing.dart`（只供測試，vault 的備份測試也用）：`EveryEventKind` 建一本用到每種事件的帳本，重播與備份測試共用。
- `bin/posting_worker.dart`：給行程終止測試用，CI 會先編譯。
- 測試：
  - 從日誌重建，涵蓋每一種事件；
  - 帶資料從舊版本升級；
  - 記帳或升級到一半被強制結束，重開後完整；
  - 每種被拒絕的指令都不改任何資料；
  - 1 萬筆規模測試。
