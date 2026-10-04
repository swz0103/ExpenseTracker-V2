# amount_input

金額輸入的純計算，只依賴 `foundation_values`。不寫入帳本，App 取得結果後由使用者確認才套用。

- `calculateAmount(Currency, String)`：算式求值，回傳 `money` 與是否有取位（`rounded`）。
  - 支援 `+ - * /`、`− × ÷`、小數、括號、一元正負號、百分比。
  - 百分比固定是「除以 100」：`100 + 10%` 是 100.10，打九折要寫 `100 × (1 − 10%)`。
  - 不支援隱式乘法、指數、千分位逗號。
  - 全程用 BigInt 有理數，只在最後依幣別小數位以 `half-away-from-zero-v1` 取位一次；`1 ÷ 3 × 3` 是 1。
  - 上限：128 字元、96 個 token、括號 16 層、中間值 4,096 bits；超過就拒絕，不截斷。
  - 錯誤：`AmountInputException`（`syntax`、`divisionByZero`、`complexity`），訊息不含使用者輸入。
- `proposeSplit`：依平均、百分比或比例把金額分給多個分類，用最大餘數法讓總和不差一分。

目前 App 尚未接上（見 `docs/STATUS.md`）。
