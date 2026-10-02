# 串流容量 admission 主機證據（2026-10-02）

## 已完成範圍

- `SnapshotCodec.inspectCapacity` 在同一 read transaction 先驗證 schema 與完整 authority，再依每張表的實際 stable primary key 做 keyset 分頁；只保留一頁資料，不建立完整 portable snapshot。
- rows／bytes 與既有 gate 保持相同語意：以空 canonical snapshot 為固定 overhead，每列加入 canonical JSON bytes＋一個保守逗號，因此精確等於既有 `canonical.length + nonemptyTableCount`。
- 每列仍套用既有 table-specific byte limit；各表 row count、全域 50,000 rows 與 16 MiB 上限維持 fail closed。
- Ledger 第一次沒有 recovery inspection 可沿用時改用串流 inspection；工作階段內後續命令仍使用既有 transaction-coupled delta，失敗時與 SQL transaction 一起回滾。

## 驗證

- 串流容量／分塊定向：10/10；包含 `pageSize=1` 且與 materialized canonical rows／bytes 精確相等。
- Ledger 容量、回滾與重送定向：6/6。
- `ledger_generation` 完整：301/301；包含 5,000 events＋完整分類歷史、搜尋 keyset、schema 升級、雙憑證還原及 native process-exit 矩陣。
- `validated_restore` 完整：148/148。
- 兩套靜態分析：零問題。

## 尚未完成

- 這是 bounded full scan，不是持久 capacity projection；新的工作階段若沒有已驗證 recovery inspection，仍需掃描所有 authority rows 一次。
- 下一步需設計 SQLCipher 內 transaction-coupled projection、版本與 checksum，並在開啟時抽樣／完整重建比對；任何缺列、版本不符或計數不一致都必須 fail closed 或重建後再使用。
- 尚未提高 5,000 events、50,000 rows 或 16 MiB gate。
