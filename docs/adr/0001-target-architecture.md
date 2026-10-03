# ADR-0001：目標架構

- 狀態：已採用
- 日期：2026-10-03

## 背景

2026-10-02 的全專案健檢發現：App 約 79% 的程式碼位於 `prototypes/`；帳本跨筆規則分散在原型 SQL 與多個驗證器，已開始彼此矛盾（3 個 P0 都屬此類）；每次寫入都驗證整本帳，因此必須設 5,000 筆事件上限；UI 是一個約 12,000 行的程式庫；24 個 schema 版本靠 21 個布林旗標串接。rc1 文件描述的 Riverpod、Use Case、Unit of Work 都沒有實作。

## 決策

保留 `packages/` 的值物件與領域規則，以及備份加密元件；重建儲存、應用與 UI。

1. **分層**：UI（`apps/expense_tracker`）→ Application（`packages/app_core`）→ Domain（純 Dart，禁止 `dart:io`）。Infrastructure（`storage_sqlcipher`、`backup_security`、`cloud_drive`、`market_adapters`）依賴 Domain 型別、實作 Application 定義的介面。
2. **儲存**：單一 SQLCipher 資料庫、WAL。金錢事件只新增不修改；餘額、月報、卡片帳單、持倉等投影表與事件在同一交易內更新並建索引。寫入只驗證受影響範圍，取消 5,000 筆上限。崩潰復原交給 SQLite。
3. **更正**：所有金錢事件都可用「反向事件加替代事件」修正，撤銷有自己的生效日；投資批次由事件重播得出。
4. **冪等**：單一操作日誌記錄每個指令的 OperationKey，存在帳本內、跟著備份走；另有交易性 outbox 給雲端備份與提醒。
5. **金鑰**：每個資料庫一把隨機 DEK，分別由主密碼（Argon2id）、需生物辨識的 Keystore 金鑰、救援金鑰包裝；備份金鑰可輪替；密碼先做 Unicode 正規化。
6. **備份 v2**：分塊串流格式，manifest 驗證備份 ID、時間與帳本身分；擷取永遠成功，驗證結果另成健康報告，只在還原時嚴格擋下；Drive 可續傳上傳。
7. **schema 歸零**：1.0 前把 24 個版本收斂成 v1 基準；舊格式只保留在 `legacy_import`，用來匯入現有帳本與舊備份。

## 後果

- 約 4–5 個月不加新功能，並需要撰寫舊資料匯入器。
- 搬遷期間舊 App 仍可使用，負責匯出資料；每搬一項功能，都用舊系統的結果作為對照測試。
