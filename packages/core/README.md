# core

所有套件共用的值型別與時鐘，純 Dart（只用 `uuid`）。

## foundation_values

- `Money`／`Currency`：BigInt 最小單位，檢查有號 64 位元範圍。
  - `Currency.of` 只接受 `Currency.supported` 裡的常用幣別；台幣、日圓、韓圓沒有小數。
  - 手動輸入超過小數位就拒絕；計算結果才取位（`half-away-from-zero-v1`，`quantizeRatio`）。
  - 分攤用最大餘數法（`allocate`），總和不差一分。
- `PublicId`：UUID v7，依建立時間排序。
- `BusinessDate`、`UtcInstant`：無效日期直接拒絕，不自動進位。`BankingCalendar` 處理假日與 T+2。
- `FxRate`：用正整數比例保存的精確匯率，換算到最後才取位。

## app_core

- `Clock`：唯一的「現在」來源，`today()` 是台灣的今天；測試用 `FixedClock`。
