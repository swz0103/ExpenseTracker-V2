# market_data

行情與參考匯率的讀取層。依賴 `foundation_values` 與 `investments`，沒有 UI、保存或入帳；HTTP 由 `infrastructure/market_adapters` 注入。

- 每個結果都是 `available`、`stale`、`missing`、`unsupported`、`failed`、`throttled` 之一，附上來源、報價日期與取得時間。缺值不會變成 0 或 1:1，過期的值不會當成現價。
- 日終收盤（免金鑰）：TWSE、TPEx 官方 OpenAPI；代號只收一般股票（4 碼）與 ETF（00 開頭）。
- 參考匯率（免金鑰）：ECB（EUR 基準，反向會標示）、CBC 的 USD/TWD、Frankfurter v2（只取必要欄位，指數表示也精確解析）。歷史查詢最多往前 7 天並標為 `stale`。
- 盤中（選用）：Fugle、Twelve Data 需要使用者自己的 API key；Yahoo Chart 是非正式 API，只能由使用者手動開啟，不能當背景提醒的唯一來源（ADR-06）。
- `MarketDataRouter`：可設優先順序、固定來源、明確備援、交叉核對（容許 0.5% 差異，不取平均）。
- 同一主機的請求會排隊等冷卻，不會直接回報限流；快照依代號建索引。
- `evaluatePriceAlert`：價格穿越提醒；冷卻期間的穿越會在冷卻後補發。
- `IntradayRefreshController`：1–5 分鐘更新、手動與排程不重疊、失敗時退避。

尚未接到 App（見 `docs/STATUS.md`）。
