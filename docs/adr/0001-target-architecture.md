# ADR-0001：目標架構

- 狀態：已採用（2026-10-03），2026-10-19 修訂模組劃分
- 適用：整個專案

## 背景

2026-10-02 的健檢發現舊 App 約 79% 的程式碼在 `prototypes/`；跨筆規則分散在 SQL 與多個驗證器，已彼此矛盾；每次寫入都驗證整本帳，只好設 5,000 筆上限；24 個 schema 版本靠 21 個布林旗標串接。決定保留值物件、領域規則與備份加密，重建儲存、應用與 UI。舊 App 沒有資料要搬（使用者決定當成新 App），已整個移除。

## 決策

### 1. 模組與依賴方向

| 模組 | 層 | 依賴 |
| --- | --- | --- |
| `packages/core` | 基礎：金額、日期、匯率、ID、指令執行器 | — |
| `packages/domain` | 規則：記帳、信用卡、投資、預算、定期交易、報表、CSV；純 Dart，禁止 `dart:io` | core |
| `infrastructure/market` | 執行層：收盤價與牌告匯率 | core、domain |
| `infrastructure/storage` | 執行層：SQLCipher 與帳本投影 | core、domain |
| `infrastructure/vault` | 執行層：金鑰、帳本開啟、備份、Drive | core、storage |
| `apps/expense_tracker` | App | 以上全部 |

依賴方向寫在 `architecture/boundaries.json`，由 `tooling/architecture_checks` 在 CI 檢查。模組內再依原本的子領域分資料夾（例如 `domain/lib/src/credit_cards/`），對外入口仍是 `package:domain/credit_cards.dart` 這類檔案。

2026-10-19 前是 23 個套件，每個只有幾百行，卻各有 pubspec、lockfile、lint 與 CI 項目；合併成 5 個後，邊界改由資料夾與入口檔守住，行為不變。

### 2. 儲存

單一 SQLCipher 資料庫、WAL。金錢事件只新增不修改；餘額、月報、帳單、持股、預算、定期交易等投影與事件在同一交易內更新。寫入只驗證受影響範圍，沒有筆數上限。投影可從事件完整重建。

### 3. 更正與冪等

所有金錢事件都用「反向事件加替代事件」更正；投資批次由事件重播得出。每個指令有 OperationKey，存在帳本內、跟著備份走。

### 4. 金鑰

每個帳本一把隨機資料金鑰，可由密碼（Argon2id，先做 Unicode 正規化）、需指紋的 Android Keystore 金鑰、救援碼分別包裝；也可不設密碼，此時金鑰存在 App 私有資料夾。

### 5. 備份

備份 v2 是分塊加密串流，manifest 驗證備份 ID、時間與帳本身分，還原時重播驗證，先寫暫存庫，檢查後才換上。App 每週在手機留備份，Android 自動備份帶到新手機；Drive 傳輸（續傳、分代保留）已完成，待接 Google 登入。

### 6. App

畫面用自己的 `Ledger` 模型（`model/`），先即時套用改動，再由 `VaultJournal`（`book/`）轉成 domain 指令存進加密帳本；自帶 id 的改動存完不重讀整本帳。分層由 `test/layers_test.dart` 守住。

## 後果

- 每個模組一份嚴格 lint、一個 lockfile；CI 依模組分成 architecture、domain、storage、flutter-host 四組。
- 新功能先放進所屬模組的子資料夾；要跨模組的公開型別或改變記帳語意，先修訂本文件。
