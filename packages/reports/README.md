# reports

報表的計算，依賴 `foundation_values` 與 `ledger`。輸入是 `bookkeeping` 的 `reportFact` 產生的事實。

- `MonthlyReport`：每月依幣別的收入、支出，以及分類、商家、帳戶小計。
- `AssetReport`：依幣別合計各帳戶餘額，可排除不計入淨資產的帳戶；不做跨幣別總計。

App 目前直接讀 `ledger_sqlcipher` 的月報投影；這兩個報表尚未接到畫面（見 `docs/STATUS.md`）。
