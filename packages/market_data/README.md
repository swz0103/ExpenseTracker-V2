# market_data

台股收盤價與臺灣銀行牌告匯率，各只用一個免費、免帳號的來源。依賴 `foundation_values` 與 `investments`；HTTP 由 `infrastructure/market_adapters` 注入。

- `stockClose`：TWSE（`STOCK_DAY_ALL`）與 TPEx（上櫃每日收盤）的最新收盤價，價格是十進位文字，不經過 `double`。代號只收一般股票（4 碼，可帶一個英文字，如特別股）與 ETF（00 開頭）。
- `bankRates`：臺灣銀行牌告（`rate.bot.com.tw/xrt/flcsv/0/day`），每個幣別有現金與即期的買入、賣出。外幣帳戶估值用即期買入（`valuation`）。App 沒用到的幣別略過。
- 結果是 `available`、`stale`、`missing`、`unsupported`、`failed` 之一。缺值不會變成 0；收盤日超過 4 天、或更新失敗而沿用上一份，都標為 `stale`。
- 同一份快照 20 分鐘內共用，同時的查詢只發一次請求；失敗後 1 分鐘內不重試。
