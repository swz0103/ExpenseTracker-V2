# data_exchange

簡易收支的 JSON／CSV 交換格式（`expensetracker-v2-simple-transactions`），依賴 `foundation_values`、`accounts`、`ledger`。

- `SimpleTransactionCodec`：JSON 與 CSV 互轉。每筆有來源工作空間、來源交易 ID、日期、帳戶、收入或支出、金額（整數最小單位）與備註。CSV 備註用 JSON 字串，逗號、換行、中文都能來回。
- 來源 ID 重複、混合工作空間、日期或金額錯誤、未知欄位或版本、超過 5,000 筆或 24 MiB，整份拒絕。
- `SimpleImportPreview.prepare`：使用者對應帳戶後，逐列檢查帳戶、幣別、狀態與日期，並按幣別合計；不寫入帳本。

這不是備份格式：轉帳、退款、更正、分類等完整歷史只在加密備份裡。App 尚未接上匯入匯出（見 `docs/STATUS.md`）。
