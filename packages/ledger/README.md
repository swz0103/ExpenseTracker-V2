# ledger

分錄的 Domain 規則，只依賴 `foundation_values`。

- `Posting`：期初、收入、支出、轉帳（同幣或跨幣、可含手續費）、退款（可入帳到其他幣別）、沖銷、投資買進／賣出／股利。建立物件本身沒有財務效果，由 `bookkeeping` 在交易中保存。
- 沖銷產生反向分錄、原分錄保留；投資分錄只有作廢交易時能沖銷。
- `RefundBudget`：退款額度由先前的退款重播得出。
- `rebuildBalance`：從有效分錄重算餘額，拒絕重複的分錄 ID 與 OperationKey。
- 備註（`NoteChange`）、分類分攤、標籤與商家選擇。

```sh
dart pub get --enforce-lockfile
dart analyze
dart test --reporter expanded
```
