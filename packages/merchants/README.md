# merchants

商家與別名的規則，只依賴 `foundation_values`。

- 商家可以同名（例如不同分店），用 ID 區分；每個商家最多 16 個別名。
- 比對只去掉首尾空白並轉小寫；有歧義時回傳所有候選，不自動選。
- 封存、合併與分類相同：保留來源與去向，舊交易不改寫，合併鏈用 `resolveRedirects`。

保存與指令在 `bookkeeping`（`changeCatalog`）。
