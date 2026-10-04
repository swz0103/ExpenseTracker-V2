# categories

分類的規則，只依賴 `foundation_values`。

- 兩層：根分類與子分類；收入／支出種類建立後不能改。
- 同一層、同種類不能重名（比對統一全形半形與大小寫）。名稱算字數，擋控制字元。
- 封存保留 ID；要先封存子分類才能封存父分類，啟用則相反。
- 合併：來源保留並記下去向，舊交易不改寫；報表歸到合併後的分類。合併鏈用 `resolveRedirects` 一次解開（不遞迴、偵測循環）。
- `CategoryCatalog` 一次驗證整個工作空間的分類；每次變更產生新的 catalog。

保存與指令在 `bookkeeping`（`changeCatalog`）。
