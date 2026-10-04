# investments

股票與 ETF 的規則，只依賴 `foundation_values`。所有預覽都不寫入帳本；保存在 `bookkeeping` 的 `InvestmentBook`。

- 身分：`BrokerIdentity`、`InvestmentAccount`（連結交割的現金或銀行帳戶）、`InvestmentInstrument`（市場＋代號，穩定 ID）。
- 數量與價格是十進位文字，不經過 `double`；台股股數只收整數（零股也是整數股）。
- `InvestmentBuyPreview`／`InvestmentSellPreview`：成交價金與數量×價格比對，容許券商捨入差 1 個最小單位；賣出用 FIFO 或平均成本，同一持股只能用一種。淨額可以是 0 或負數。
- `InvestmentDividendPreview`：含預扣稅、手續費、二代健保補充保費。
- `StockSplitPreview`、`CorporateActionPreview`：分割、反向分割、配股、減資（畸零股與退還股款以現金處理，先沖減成本）。
- `TaiwanTradeCharges`、`taiwanSettlementDate`、`supplementaryPremium`：台股手續費（折扣、最低 20 元）、證交稅、T+2、補充保費試算。
- 績效：`InvestmentPerformance`、`InvestmentPortfolioSummary`（同幣別合計，缺報價就不給市值）、`CrossCurrencyInvestmentSummary`（成本、已實現、股利用當時入帳的台幣值，只有市值用今日匯率）、`calculateInvestmentXirr`（ACT/365）。

績效與 XIRR 尚未接到 App（見 `docs/STATUS.md`）。
