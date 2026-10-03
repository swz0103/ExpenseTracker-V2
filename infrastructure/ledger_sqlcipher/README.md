# ledger_sqlcipher

基礎設施層（ADR-0001）：`bookkeeping` 各個儲存介面的 SQLCipher 實作，加上給畫面讀的查詢。

- `ledgerSchema`：`ledger` 模組的 migration。已發佈的步驟永遠不改，只能在末尾新增（目前 10 步）。
- `LedgerStore`：寫入交易提供 `SqlBookkeeping`。投影表（餘額、月報、分類月報、帳單、持股、預算、定期交易）和事件在同一交易更新。
- 查詢：
  - 帳戶、餘額、逐筆餘額（`runningBalance`）、最近分錄、是否已沖銷（`reversedBy`）；
  - 月報、分類合計、月報事實、預算狀態；
  - 信用卡：帳單、帳單明細（`statementItems`）、待入帳授權、可用額度、分期；
  - 投資：投資帳戶、商品、持有中的商品、持股、交易歷史、已實現損益與股利（`investmentIncome`）；
  - 定期交易：範本清單、到期的項目。
- `LedgerReplay`：從事件日誌重建所有投影表；`projectionRows` 用來逐列比對。
- 測試：
  - 300 筆亂數指令的對照測試；
  - 從日誌重建，涵蓋每一種事件；
  - 帶資料從舊版本升級；
  - 1 萬筆規模測試。
