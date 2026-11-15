# ADR-0008：帳本拆成 Repository 與 Service，每份狀態只有一個擁有者

- 狀態：採用（2026-11-15）；分階段實作，進度見 [ledger.md](../ledger.md#進度)
- 補充：ADR-0001、ADR-0003；名稱依 [naming.md](../naming.md)

## 背景

審查時 `Ledger` 是一個類別：2,282 行、9 個檔（一個 `part` 加 8 個 `extension`）、約 150 個成員、13 個集合。`part` 讓九個檔共用私有狀態，所以「每檔 600 行以內」的規則只是形式上滿足。實際的問題：

- 快取失效是手寫的：`_forget` 逐一清 8 個可空欄位，每個查詢另在 `on:` 手動宣告依賴；漏一個，畫面就顯示舊數字。
- 修改多筆紀錄時，先複製五個清單、改完再逐筆比對 `identical` 找出變動，改一個分類顏色也要掃過全部紀錄。
- 寫入佇列、草稿、收據、隱藏金額、行情、持股重播都在同一個類別裡，沒有一份狀態能獨立測試。

## 決策

1. **依主題拆成十個 Repository 與六個 Service**（領域驅動設計的 Repository 與 Domain Service）。Repository 擁有狀態：`EntryRepository`、`TrashRepository`、`AccountRepository`、`CategoryRepository`、`BudgetRepository`、`RecurringRepository`、`MarketDataRepository`、`HoldingRepository`、`DraftRepository`、`ReceiptRepository`。Service 不持有狀態：`BalanceService`、`StatementService`、`BudgetService`、`RecurringService`、`ReportService`、`EntryValidator`。成員分配見 [ledger.md](../ledger.md#成員分配)。
2. **Repository 只改自己的狀態。** 跨 Repository 的指令（合併分類、刪除帳戶、記一筆投資）由 `Ledger` 依序呼叫，把動到的紀錄登記到一個 `UnitOfWork`（Fowler 的 Unit of Work），成功後組成一個 `WriteBatch` 交給 `WriteQueue`；不再事後比對差異。
3. **Service 只讀。** 快取由 `QueryCache` 管：查詢執行時記下它讀了哪些 Repository，那些 Repository 變動就自動作廢，不再手寫 `on:`。
4. **變動主題與 Repository 一對一**：`Topic` 的每個值對應一個 Repository，畫面用 `watch` 訂閱的粒度不變。
5. **一個檔案一個類別，不用 `part`。** 各 Repository 放在 `repositories/`，彼此只透過建構子注入的介面溝通。
6. **`Ledger` 只剩接線**：組合 Repository 與 Service、開啟 `UnitOfWork`、通知畫面、持有 `WriteQueue`。直接留在 `Ledger` 的成員不超過 15 個（見 [ledger.md](../ledger.md#ledger-留下的成員)），其餘一律經由 Repository 或 Service，例如 `ledger.accounts.byId(id)`、`ledger.balanceService.balance(id)`。
7. **保留的外觀**：`today`、`newId`、`account(id)`、`category(name)`、`holding(code)` 呼叫了上百處，且是整個 App 的共同語彙，留在 `Ledger`。

## 依賴方向

```
models
  ↓
Entry  Trash  Account  Category  Budget  Recurring  MarketData  Draft  Receipt   （Repository，彼此不引用）
  ↓
Holding（讀 Entry、MarketData）        BalanceService（讀 Entry、Account、MarketData）
  ↓
StatementService  BudgetService  RecurringService  ReportService  EntryValidator   （只讀）
  ↓
Ledger（接線、UnitOfWork、通知、WriteQueue）
```

上層可以讀下層，下層不知道上層；同一層的 Repository 不互相引用，要一起動就由 `Ledger` 協調。

## 守住的方式

- `test/core/ledger_cache_consistency_test.dart`：隨機修改後，暖機的帳本與新建的帳本回答一致；拆分的每一步都要全綠。
- `layers_test` 新增：`core/ledger/` 內不得有 `part`；依上圖的邊檢查 import，多一條邊就失敗。
- 每個 Repository 各有單元測試：自己的不變式、失敗時不留下半個狀態。

## 後果

- 改一個 Repository 不會牽動其他 Repository；快取漏失效的整類問題由機制消除，不靠記憶。
- 記一筆的效能可以只更新 `EntryRepository` 的索引（增量），而不是全部重建。
- 分類改用 id 只會動到 `CategoryRepository` 與引用它的幾個 Repository。
- `ledger.accounts` 這類既有的清單成員改成 Repository（`ledger.accounts.all`），約 113 個檔要改呼叫；分析器會逐一指出，不會有靜默的遺漏。
