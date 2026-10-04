# tags

標籤的規則，只依賴 `foundation_values`。標籤不擁有金額或交易。

- 名稱不重複（統一全形半形與大小寫比對），可改名、封存、合併。
- 合併保留來源與去向，舊交易不改寫；新交易不能選已封存或已合併的標籤。合併鏈用 `resolveRedirects`。
- 一筆交易最多 16 個標籤。

保存與指令在 `bookkeeping`（`changeCatalog`）。
