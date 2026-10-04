# credit_cards

信用卡帳單的規則，只依賴 `foundation_values`。

- `CreditCardTerms`：結帳日、繳款日、額度，有版本。
  - `reschedule`：結帳日變更只影響之後的帳單，過去的帳單日期不變。
  - `overrideCycle`：發卡行移動某一期的實際結帳日或繳款日。
  - `cycleFor(date)`：某天的消費落在哪一期；繳款日是結帳後第一個繳款日，遇假日順延（`BankingCalendar`）。
- `CardCharge`：授權（pending）→ 入帳（posted），入帳以實際金額為準；種類有消費、發卡行費用、回饋。可記原幣金額與國外交易手續費；外幣退刷以原幣為上限。
- 帳單：前期結轉、本期消費、費用、退款、繳款、分期當期金額、應繳與最低應繳。
- `CardInstallmentSchedule`：分期，尾差全部併入第一期（例如 10,001 分 3 期為 3,335／3,333／3,333）；分期計畫自存結帳日。

指令、保存與帳單查詢在 `bookkeeping` 的 `CardBook` 與 `ledger_sqlcipher`。
