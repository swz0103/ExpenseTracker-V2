# domain

> 記帳規則，純 Dart、不碰平台。App 直接呼叫這些函式，同一條規則只寫在這裡。

## 做什麼

- 賣出成本：FIFO 部分賣出按比例、無條件捨去；平均成本只捨去一次，餘數給最後一批；全部賣出時成本全部帶走。
- 配股、減資、分割：各批按比例增減股數、保留成本與日期；整股市場把零股從最新的批次扣掉；退還股款超過成本的部分是已實現獲利。
- 股數以 10^-12 股為單位，成本以最小貨幣單位。
- 信用卡：結帳日與繳款日、結帳日變更歷史、單期調整（前後最多 7 天）；帳單在結帳日當天結束時關閉。
- 分期：整除後餘數放第一期，從購買日所在期的結帳日起算，之後每月結帳日（月底自動調整）。
- CSV（RFC 4180）：以 `= + - @`、tab 開頭的文字匯出時加 `'`，試算表打開不當成公式；讀回時拿掉。

## 對外入口

| 入口 | 內容 |
| --- | --- |
| `investments.dart` | `sellFromLots`、`reratioLots`、`reratioUnits`、`unitsPerShare` |
| `credit_cards.dart` | `CardSchedule`（`cycleFor`、`lastCloseOn`、`datesOf`）、`CardScheduleChange`、`CardCycleOverride`、`installmentShares`、`installmentStart`、`installmentCloses` |
| `data_exchange.dart` | `readCsv`、`writeCsv`、`parseEInvoices`（財政部電子發票「消費明細」CSV） |

手續費、證交稅、二代健保、交割金額與交割日在 `packages/ledger/trade_costs`；貸款月付在 `modules/loans`。

## 不做什麼

- 不保存狀態、不讀寫檔案：需要帳本內容的計算由 App 的 `Ledger` 帶資料進來。
