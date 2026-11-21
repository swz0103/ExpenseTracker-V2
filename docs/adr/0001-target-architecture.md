# ADR-0001：目標架構

- 狀態：採用（2026-10-03）；2026-10-19 修訂模組劃分，2026-10-21 改為單一模型；2026-11-21 改寫成現行名稱，拿掉已不存在的類別與路徑。Android 系統備份見 [ADR-0005](0005-backup-choices.md)，帳本內部見 [ADR-0008](0008-ledger-aggregates.md)，現況整理在 [architecture.md](../architecture.md)。
- 適用：整個專案

## 背景

2026-10-02 的健檢發現舊 App 約 79% 的程式碼在 `prototypes/`；跨筆規則分散在 SQL 與多個驗證器，已彼此矛盾；每次寫入都驗證整本帳，只好設 5,000 筆上限；24 個 schema 版本靠 21 個布林旗標串接。決定保留值物件、領域規則與備份加密，重建儲存、應用與 UI。舊 App 沒有資料要搬，已整個移除。

2026-10-21 前帳本還有兩套：畫面一套，加密帳本另一套（指令 → 事件日誌 → 二十張投影表），開帳本時兩邊核對；FIFO 進位、結帳日歷史遺失都是兩套不一致造成的，另外還有只為多人同步才需要的機制。個人單機記帳用不到，所以換成單一模型，少了約 1.4 萬行。

## 決策

### 1. 模組與依賴方向

| 模組 | 層 | 依賴 |
| --- | --- | --- |
| `packages/core` | 基礎：幣別、匯率、ID、日期、時鐘 | — |
| `packages/domain` | 計算規則：持股成本、台股費用、帳單週期、分期、貸款、CSV、電子發票；純 Dart，禁止 `dart:io` | core |
| `infrastructure/market` | 收盤價與牌告匯率 | core |
| `infrastructure/storage` | SQLCipher 加密檔，每筆資料一列 JSON | — |
| `infrastructure/vault` | 金鑰、帳本開啟、備份 | storage |
| `apps/expense_tracker` | App：畫面與唯一的帳本模型 | 以上全部 |

依賴方向由各 `pubspec.yaml` 決定；`tooling/architecture_checks` 檢查 core 與 domain 不引用平台函式庫、各 lockfile 版本一致。

### 2. 單一模型

帳本只有一份：App 的 `Ledger`（`lib/src/core/ledger/`）。它在記憶體裡持有全部資料，改動先在畫面生效，再經 `WriteQueue` 一次一個交易寫進資料庫；寫入失敗時重讀檔案，畫面回到實際存下的狀態。計算規則只寫一次：成本、配股減資、帳單週期、分期、台股費用呼叫 `packages/domain`，能不能記只由 `EntryValidator` 判斷。內部分工見 ADR-0008。

### 3. 儲存

單一 SQLCipher 檔、WAL、`synchronous=NORMAL`（量測與理由見 `infrastructure/storage/README.md`）；一個改動一個交易。資料表結構只有一版；每列紀錄帶版本號，讀取時逐版升級（ADR-0010）。1 萬筆紀錄約數 MB，整本讀進記憶體。刪除的紀錄移到垃圾桶保留 30 天；沒有事件歷史，復原靠「最近刪除」與備份。

### 4. 金鑰

每個帳本一把隨機資料金鑰，可由密碼（Argon2id，先做 Unicode 正規化）、需指紋的 Android Keystore 金鑰、救援碼分別包裝；也可不設密碼，此時金鑰存在 App 私有資料夾。

### 5. 備份

備份是全部資料的快照：分塊、gzip、AES-256-GCM，AAD 綁定標頭雜湊與塊的順序。還原時先寫暫存庫，完整性檢查後才換上。自動備份到 Google 雲端硬碟（Drive REST，`drive.file` 權限，不經自己的伺服器）或手機上選的資料夾，各留最新 5 份；Android 系統備份帶加密副本到新手機。

## 後果

- 每個模組一份嚴格 lint、一個 lockfile；CI 把純 Dart 模組放在同一個工作，App 另一個。
- 新功能改 `Ledger` 的 Commands；需要的計算規則放進 domain，不在畫面重寫。
- 記錄格式改變時寫升級步驟，舊版寫出的檔案由測試打開比對（ADR-0010）。
