# ledger_postings

> 現行紀錄在分錄（`packages/kernel`）裡的樣子，純 Dart：每種意圖的記帳規則、外幣與分期兩個修訂者、它們記到的帳戶。

## 做什麼

- 意圖種類（`model/intents.dart`）：期初餘額、支出（可分攤）、收入與退款、轉帳（手續費分類存在意圖裡）、期初持股、買進、賣出、股利（現金、配股、分割、減資同一種），以及舊帳本「不計入持股的交易」。外幣金額與分期**不是**另外的種類，而是修訂：`Slots.fx`（`ForeignValue`：`Worth`，或舊帳本才會有、明確記錄的 `SameNumber`／`ReceivedFeeSameNumber`）與 `Slots.instalments`。
- 帳戶命名、固定帳戶（期初、匯兌、已實現損益、股利、不計入持股）、串、標籤：`model/vocabulary.dart`，一個地方。
- 規則只讀意圖與之前的分錄：批次與賣出、配股、分割、減資都呼叫 `packages/domain` 的 `sellFromLots`／`reratioLots`，金額用 `ledger_trade_costs` 的 `settlementAmount`；分期的入帳日用 domain 的 `installmentBillingDays`，與 App 的餘額同一個來源。
- 股數以百萬分之一股記在分錄的數量上；比這更細的批次拒絕（`quantity.tooFine`），不默默取位。
- 信用卡帳單應繳（`calc/statement.dart`）：結帳時的欠款減去之後由其他資金帳戶繳入的款項。

## 不做什麼

- 不讀設定、不讀時鐘；不決定舊帳本的形狀怎麼搬（由 App 的重放決定並記錄）。
