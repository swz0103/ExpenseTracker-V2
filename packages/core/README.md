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
| `money/amount_parser.dart` | `parseAmount`：人輸入或匯入的金額文字的唯一解析；不丟例外，回傳金額或原因（空白、不是數字、小數太多、太大、有歧義）；`maxAmountUnits`（999,999,999）是全 App 唯一的金額上限 |
| `money/amount_format.dart` | 千分位、依幣別小數位寫出數字、正負號拆分、半數遠離零的取位；不含中文 |
| `money/price.dart` | 股數乘股價的精確金額（`timesPrice`），股價取到萬分之一再以整數運算 |
| `money/amount_sum.dart` | 計算機算式的精確運算（分數，不經 `double`）與是否為合法金額 |
| `percent/percent.dart` | 百分比與比例，唯一的取位規則（半數遠離零）；超過與否用 `isOver` 比金額 |
| `app_core.dart` | `Clock`：唯一的「現在」，`today()` 是台灣的今天；測試用 `FixedClock` |

## 不做什麼

- 不碰平台、檔案、網路；不含任何記帳規則（在 `domain`）。
