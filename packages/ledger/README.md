# Ledger — 基本入帳 Domain

依據 [RC-03／04](../../docs/architecture-baseline-v1.0-rc1.md#rc-03)、[LED 驗收案例](../../docs/foundation-acceptance.md)。套件只依賴 foundation_values，不引用 Accounts 內部狀態或資料庫。

目前完成的 Posting 是不可變的入帳提案，建立物件本身沒有財務效果；Application 驗證並 commit 後才入正式有效集合。

- 期初餘額影響資金，不列一般收入或消費，允許負值。
- 收入／支出要求正輸入，分別產生正／負本金 leg。
- 同幣轉帳本金成對、手續費另有 fee leg；費用只扣一次，報表只將費用列消費。
- 支出分類分攤必須加總正確、不可重複 category ID，不另產生資金 leg。沒有分類時視為尚未指定，正式 UI 與分類驗證另批接入。
- rebuildBalance 從傳入的有效已提交集合重算，使用寬整數中間值，最終金額仍檢查保存範圍；拒絕跨帳本與重複 event ID。

Application 必須以 PostingAccount 的公開 ID／workspace／expectedVersion 取得當下 Accounts 規則；不能把這份提案當成帳戶仍有效的證據。分類的存在與 workspace 關聯由 Categories 參與驗證。正式 adapter 還要守住期初事件唯一性、operation receipt、Audit 與同一 transaction；本 Domain 不假裝已完成這些持久條件。

```sh
dart pub get --enforce-lockfile
dart analyze
dart test --reporter expanded
```

8 項本機測試涵蓋 LED-01／02／03／05 的計算語意、輸入拒絕與餘額重建。跨幣、退款、revision／reversal／tombstone、匯入、正式 schema、加密、備份與 UI 仍待實作。呼叫方若把 draft 或 superseded history 傳入重建函式，就不符合契約；正式查詢必須提供正確有效集合。
