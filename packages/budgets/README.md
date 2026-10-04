# budgets

每月支出預算的規則，只依賴 `foundation_values`、`categories`、`reports`。

- `BudgetPlan`：工作空間、月份、上限（正數）、警示百分比（1–100），可選分類、帳戶、標籤；`repeats` 為每月沿用（`forMonth`）。
  - 帳戶、標籤各自多選時是「任一符合」，和分類之間是「全部符合」；選父分類包含子分類。
  - 只能選支出分類。
- `evaluateBudget`：用月報事實算已用、剩餘、是否到警示。不同幣別不換算，回報略過的筆數。
- `BudgetPlanCodec`：版本化 JSON，未知欄位、重複選項、過大資料一律拒絕。

保存、版本衝突與「合併過的分類算進目標分類」在 `bookkeeping` 的 `PlanningBook` 與 `ledger_sqlcipher`。
