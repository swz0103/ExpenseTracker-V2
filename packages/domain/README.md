# domain

> 記帳規則，純 Dart、不碰平台。App 直接呼叫這些函式，同一條規則只寫在這裡。

## 做什麼

- 賣出成本：FIFO 部分賣出按比例、無條件捨去；平均成本只捨去一次，餘數給最後一批；全部賣出時成本全部帶走。
- 配股、減資、分割：各批按比例增減股數、保留成本與日期；整股市場把零股從最新的批次扣掉；退還股款超過成本的部分是已實現獲利。
- 股數以 10^-12 股為單位，成本以最小貨幣單位。
- 台股手續費（折扣、最低 20 元、零股 1 元）、證交稅（依日期與 ETF）、T+2、二代健保補充保費。
- 信用卡：結帳日與繳款日、結帳日變更歷史、單期調整（前後最多 7 天）；帳單在結帳日當天結束時關閉。
- 分期：整除後餘數放第一期，從購買日所在期的結帳日起算，之後每月結帳日（月底自動調整）。
- 貸款月付：本息平均、本金平均、只繳息三種，利率以整數萬分比保存。
- CSV（RFC 4180）：以 `= + - @`、tab 開頭的文字匯出時加 `'`，試算表打開不當成公式；讀回時拿掉。

## 對外入口

| 入口 | 內容 |
| --- | --- |
| `investments.dart` | `sellFromLots`、`reratioLots`、`reratioUnits`、`unitsPerShare`、`TaiwanTradeCharges`、`taiwanSettlementDate`、`supplementaryPremium` |
| `credit_cards.dart` | `CardSchedule`（`cycleFor`、`lastCloseOn`、`datesOf`）、`CardScheduleChange`、`CardCycleOverride`、`installmentShares`、`installmentStart`、`installmentCloses` |
| `loans.dart` | `loanPlan`（本息平均、本金平均、只繳息：`LoanRepay`）、`rateOf`、`rateText` |
| `data_exchange.dart` | `readCsv`、`writeCsv`、`parseEInvoices`（財政部電子發票「消費明細」CSV） |

## 不做什麼

- 不保存狀態、不讀寫檔案：需要帳本內容的計算由 App 的 `Ledger` 帶資料進來。
