# domain

記帳規則，純 Dart、不碰平台。App 的畫面模型直接呼叫這些函式，同一條規則只寫在這裡。

## investments

- `sellFromLots`：賣出成本。FIFO 部分賣出的批次按比例、無條件捨去；平均成本只捨去一次，留下的成本再按股數分回各批，最後一批拿餘數。全部賣出時成本全部帶走。
- `reratioLots`：配股、減資、分割。各批按比例增減股數、保留成本與日期；整股市場把零股從最新的批次扣掉；退還股款按成本比例降低成本，超過成本的部分是已實現獲利。`reratioUnits` 算單一批次。
- 股數以 10^-12 股為單位（`unitsPerShare`），成本以最小貨幣單位。
- `TaiwanTradeCharges`、`taiwanSettlementDate`、`supplementaryPremium`：台股手續費（折扣、最低 20 元、零股 1 元）、證交稅（依日期與 ETF）、T+2、二代健保補充保費。

## credit_cards

- `CardSchedule`：結帳日、繳款日、結帳日變更歷史（`CardScheduleChange`）、單期調整（`CardCycleOverride`，前後最多 7 天）。`cycleFor` 回傳某天所在的帳單期，`lastCloseOn` 是某天以前最後一次結帳，`datesOf` 是某個預定結帳日實際的結帳與繳款日。帳單在結帳日當天結束時關閉。
- 分期：`installmentShares`（整除後餘數放第一期）、`installmentStart`（購買日所在期的結帳日起算）、`installmentCloses`（之後每月的結帳日，月底自動調整）。

## data_exchange

- `readCsv`／`writeCsv`：RFC 4180 CSV。
- `parseEInvoices`：財政部電子發票「消費明細」CSV。
