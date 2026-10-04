# recurring_transactions

定期交易的規則，只依賴 `foundation_values`。

- `RecurringTemplate`：帳戶、金額（負數為支出）、起始日、每 N 日／週／月／年、結束日，可帶分類、標籤、商家。
- `dueCandidates`：找出區間內到期的項目（`after` 不含、`through` 含），離線多天後可一次補齊。月底與閏日以起始日為準，短月取當月最後一天。
- 每個到期項目的身分是「範本＋到期日」，修改範本不會讓同一天多出一筆。
- `RecurringTemplateCodec`：版本化、有大小上限的 JSON。

確認入帳（可改實際金額與日期、每期只能確認一次）在 `bookkeeping` 的 `PlanningBook`。
