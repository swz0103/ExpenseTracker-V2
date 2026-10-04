# foundation_values

所有套件共用的值型別，純 Dart，不依賴其他套件（只用 `uuid`）。

- `Money`／`Currency`：BigInt 最小單位，檢查有號 64 位元範圍；JSON 的金額是字串。
  - `Currency.of` 只接受 `Currency.supported` 裡的常用幣別；台幣、日圓、韓圓沒有小數。
  - 手動輸入超過小數位就拒絕；計算結果才取位（`half-away-from-zero-v1`，`quantizeRatio`）。
  - 分攤用最大餘數法（`largest-remainder-v1`），總和不差一分。
- `PublicId`（UUID v7）、`WorkspaceId`、`OperationId`、`OperationKey`：重試同一個意圖要用同一個 key。
- `BusinessDate`、`UtcInstant`：無效日期直接拒絕，不自動進位。`BankingCalendar` 處理假日順延。
- `FxRate`：用正整數比例保存的精確匯率，換算到最後才取位。`FxObservation` 保存報價日期與取得時間；要用較早的報價必須明說，而且最多 7 天前（`rateFor`）。
- `cleanName`／`nameKey`：名稱整理與比對（算字數、擋控制字元、統一全形半形與大小寫）。
- `resolveRedirects`：分類、標籤、商家共用的合併鏈解析。
