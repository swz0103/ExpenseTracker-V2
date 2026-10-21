# ADR-0001：目標架構

- 狀態：已採用（2026-10-03），2026-10-19 修訂模組劃分，2026-10-21 改為單一模型
- 適用：整個專案

## 背景

2026-10-02 的健檢發現舊 App 約 79% 的程式碼在 `prototypes/`；跨筆規則分散在 SQL 與多個驗證器，已彼此矛盾；每次寫入都驗證整本帳，只好設 5,000 筆上限；24 個 schema 版本靠 21 個布林旗標串接。決定保留值物件、領域規則與備份加密，重建儲存、應用與 UI。舊 App 沒有資料要搬（使用者決## 決策

### 1. 模組與依賴方向

| 模組 | 層 | 依賴 |
| --- | --- | --- |
| `packages/core` | 基礎：金額、日期、匯率、ID、時鐘 | — |
| `packages/domain` | 計算規則：持股成本、配股減資、台股費用、帳單週期、分期、CSV、電子發票；純 Dart，禁止 `dart:io` | core |
| `infrastructure/market` | 執行層：收盤價與牌告匯率 | core |
| `infrastructure/storage` | 執行層：SQLCipher 加密檔，每筆資料一列 JSON | — |
| `infrastructure/vault` | 執行層：金鑰、帳本開啟、備份 | storage |
| `apps/expense_tracker` | App：畫面與唯一的帳本模型 | 以上全部 |

依賴方向由各 `pubspec.yaml` 決定；`tooling/architecture_checks` 在 CI 檢查 core 與 domain 不引用平台函式庫、測試寫明預期的失敗、各 lockfile 版本一致。

### 2. 單一模型

帳本只有一份：App 的 `Ledger`（`model/`）。它在記憶體裡持有帳戶、分類、紀錄、預算、定期交易，算出餘額、持股、帳單與報表。每個改動先在畫面上生效，再交給 `Journal` 一個 `Batch`：這次放上的資料和拿掉的鍵。`TableJournal`（`book/`）把每筆資料寫成 `RowStore` 裡的一列 JSON（`account`、`category`、`entry`、`budget`、`recurring`、`trash`、`receipt`、`market` 各一架），一個改動一個交易。寫入失敗時回報並重讀檔案，畫面回到實際存下的狀態。

計算規則不在畫面模型另寫：賣出成本、配股減資與分割呼叫 domain 的 `lot_math.dart`；帳單週期、結帳日變更前的舊週期、單期調整、分期入帳月份與每期金額呼叫 domain 的 `CardSchedule` 與分期函式；台股手續費、證交稅、補充保費呼叫 `taiwan.dart`。能不能記（`checks.dart`）也只有一處。

分層由 `test/layers_test.dart` 守住：model 不碰畫面與儲存、compose 與 look 不碰 pages、範例帳本只在網頁預覽。

2026-10-21 前是兩套：畫面一套、加密帳本另一套（domain 指令 → 事件日誌 → 二十張投影表），兩邊各算一次再於開帳本時核對；FIFO 進位、結帳日歷史遺失都是兩套不一致造成的。兩套之間還有只為多人同步才需要的 OperationKey、workspace、版本號與事件重播。個人單機記帳用不到，又沒有舊帳本要相容，所以整套換掉，少了約 1.4 萬行。

### 3. 儲存

單一 SQLCipher 檔、WAL、`synchronous=FULL`；一個改動一個交易，崩潰時 SQLite 自己回滾。一筆資料改內容時保留第一次寫入的順序，讀回的紀錄順序和畫面一致。結構只有一版，沒有 migration。帳本規模（1 萬筆紀錄約數 MB）整本讀進記憶體即可。

更正就是覆蓋那一筆；刪除的紀錄移到 `trash` 架保留 30 天。沒有事件歷史，復原靠「最近刪除」與備份。

### 4. 金鑰

每個帳本一把隨機資料金鑰，可由密碼（Argon2id，先做 Unicode 正規化）、需指紋的 Android Keystore 金鑰、救援碼分別包裝；也可不設密碼，此時金鑰存在 App 私有資料夾。

### 5. 備份

備份 v3 是全部資料的快照：分塊、gzip、AES-256-GCM，AAD 綁定標頭雜湊與塊的順序。還原時每一筆先用 App 的讀取器檢查，先寫暫存庫，完整性檢查後才換上。App 每週在手機留備份（帳本 `revision` 沒變就不備），Android 自動備份帶到新手機；匯出的備份附收據照片。

 有別的理由要升版時再一起評估。

## 後果

- 每個模組一份嚴格 lint、一個 lockfile；CI 依模組分成 architecture、domain、storage、flutter-host 四組。
- 新功能改 `Ledger` 與它的 `Batch`；需要的計算規則放進 domain 並由 `Ledger` 呼叫，不在畫面重寫。
- 記錄格式改變時，讀取器要能讀舊格式（缺的欄位給預設值），不另寫 migration。
