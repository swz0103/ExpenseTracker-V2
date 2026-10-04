# reports

報表用的共用型別，依賴 `foundation_values` 與 `ledger`：

- `ReportMonth`：不受時區影響的日曆月份。
- `MonthlyFact`、`CategoryAllocation`：一筆分錄對報表的影響，由 `bookkeeping` 的 `reportFact` 產生；預算與 `ledger_sqlcipher` 的月報、分類合計都用它。

報表數字由 `ledger_sqlcipher` 的投影表直接查詢，不另外在記憶體裡重算。
