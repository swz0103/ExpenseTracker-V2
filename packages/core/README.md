# core

> 所有套件共用的值型別與時鐘，純 Dart（只用 `uuid`）。

## 做什麼

- 金額用 BigInt 最小單位，檢查有號 64 位元範圍；台幣、日圓、韓圓沒有小數。
- 手動輸入超過小數位就拒絕；計算結果才取位（`half-away-from-zero-v1`）；分攤用最大餘數法，總和不差一分。
- 匯率用正整數比例保存，換算到最後才取位，不經 `double`。
- 無效日期直接拒絕，不自動進位；假日與 T+2 由 `BankingCalendar` 處理。

## 對外入口

| 入口 | 內容 |
| --- | --- |
| `foundation_values.dart` | `Money`、`Currency`（`Currency.supported` 的常用幣別）、`FxRate`、`PublicId`（UUID v7）、`BusinessDate`、`UtcInstant`、`BankingCalendar` |
| `app_core.dart` | `Clock`：唯一的「現在」，`today()` 是台灣的今天；測試用 `FixedClock` |

## 不做什麼

- 不碰平台、檔案、網路；不含任何記帳規則（在 `domain`）。
