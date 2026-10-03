# bookkeeping

應用層（ADR-0001 階段 3）：帳戶與收支指令，跑在 `app_core` 的 `CommandRunner` 上。

- 指令：開戶（可含期初餘額）、改名、封存／重新啟用、收入／支出、轉帳（可跨幣別、可含手續費）、沖銷。
- 每個指令的事件、投影表與操作紀錄在同一交易提交；重試回傳同一結果，同一 key 換輸入則是 `operation.input-mismatch`。
- 帳戶規則（版本、幣別、狀態、開戶日）在寫入交易內檢查；違規轉成 `AppFailure`，代碼如 `account.versionConflict`、`ledger.sameAccount`。
- 沖銷只新增反向分錄，原分錄保留；同一筆不能沖兩次；已結清帳戶不能被沖銷改動餘額。
- `AccountCodec`／`PostingCodec`：版本化 JSON，解碼一律重新走 domain 工廠驗證。
- 儲存介面 `BookkeepingTransaction`，SQLCipher 實作在 `infrastructure/ledger_sqlcipher`。
- 尚未搬：分類分攤、退款、投資現金分錄、結清帳戶（需未結項目查詢）。
