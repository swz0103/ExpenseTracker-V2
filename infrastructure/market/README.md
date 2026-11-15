# market

> 收盤價與匯率：證交所、櫃買中心收盤價與臺灣銀行牌告，以及走 dart:io 的傳輸。

## 做什麼

- 每種資料只用一個免費、免帳號的來源；價格是十進位文字，不經過 `double`。
- 代號只收一般股票（4 碼，可帶一個英文字，如特別股）與 ETF（00 開頭）。
- 上市：證交所 `STOCK_DAY_ALL`；當天總表沒有時改查 `STOCK_DAY` 本月或上個月最後一個收盤。上櫃：櫃買中心每日收盤。
- 走勢圖：上市讀 `STOCK_DAY`、上櫃讀 `tradingStock`，一檔一個月。
- 匯率：臺灣銀行牌告 CSV，每個幣別有現金與即期的買入、賣出；外幣帳戶估值用即期買入。
- 結果是 `available`、`stale`、`missing`、`unsupported`、`failed` 之一。缺值不變成 0；收盤日超過 4 天，或更新失敗而沿用上一份，都標為 `stale`。
- 同一份快照 20 分鐘內共用，同時的查詢只發一次請求；失敗後 1 分鐘內不重試。數 MiB 的 JSON 每份只解析一次，`decodeJson` 可換成在別的 isolate 解析（App 用 `Isolate.run`）。

## 對外入口

| 入口 | 內容 |
| --- | --- |
| `market_data.dart` | `stockClose`、`listedHistoryClose`、`monthCloses`、`bankRates`、`valuation`；依賴 `foundation_values` 與 `investments` |
| `market_adapters.dart` | dart:io 傳輸：只連 TWSE、TPEx、臺灣銀行的 HTTPS，不跟隨轉址，每階段 10 秒逾時，回應有大小上限 |

## 不做什麼

- 不做盤中行情（正式來源要付費簽約）；不保存價格（App 存在帳本與 `prices/`）。
