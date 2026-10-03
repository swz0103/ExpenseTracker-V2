# 狀態

最後更新：2026-10-03（階段 2 完成）

## 目前階段：階段 3 領域移植

全專案健檢（189 項問題，P0 3 項）後決定：保留 `packages/` 的值物件與領域規則，重建儲存層、應用層與 UI。完整說明見 [ADR-0001](adr/0001-target-architecture.md)。

**功能凍結**：重建完成前不加新功能，只修正錯誤。新程式碼不得新增對 `prototypes/` 的依賴。

## 階段 0 已完成

- 寫入中被強制關閉後，SQLite 留下的 journal 不再被當成竄改；改由 SQLite 自行回滾（`storage_generation`）。
- 更正有標籤或商家的交易後，備份不再失敗（`modular_persistence` 標籤與商家驗證器）。
- 信用卡交易加備註後，卡片驗證、帳單與 17→18 升級不再失敗。
- 預覽版改用固定簽章金鑰，之後可直接覆蓋安裝。
- 預覽版與正式版發佈前，必須先通過同一 commit 的完整驗證；只有發佈步驟持有寫入權限。
- 移除未使用的 `transaction_boundary` 原型、兩條手動 workflow、未使用的 Twelve Data 憑證畫面，以及過期文件。

## 階段 3 進行中

- [x] 3a 帳戶與收支：`packages/bookkeeping`（開戶含期初餘額、改名、封存／重新啟用、收入、支出、跨幣別轉帳含手續費、沖銷）＋ `infrastructure/ledger_sqlcipher`（帳戶、分錄、餘額、月報投影表，與事件同交易更新）。300 筆亂數指令的對照測試：投影餘額＝domain `rebuildBalance`，月報＝分錄加總，重開後仍一致。`storage_sqlcipher` 支援模組各自的 migration。
- [x] 3b 分類、標籤、商家：建立、改名、封存、合併（合併後報表歸到目標分類）、商家別名；收支可帶分類分攤、標籤、商家，沖銷沿用原分錄的分攤與標籤；分類月報投影。
- [x] 3c 信用卡：帳單日設定、授權（pending）、入帳（同一筆授權只算一次）、繳款（轉帳，不是支出）、帳單 read model、分期預估；卡片分錄不能用一般沖銷，要在卡片上更正。
- [x] 3d 投資：券商、投資帳戶、商品登錄；買進、賣出（FIFO／平均成本）、股利；持股批次一律由交易紀錄重播得出；交易分錄不能直接沖銷。
- [x] 3e 市場資料：四個 HTTP transport 移到 `infrastructure/market_adapters`，`market_data` 不再有 `dart:io` 例外，gateway 一律注入 transport。
- [ ] 3f 退款、結清帳戶（需未結項目查詢）。

## 階段 2 已完成

- [x] 2a `packages/app_core`：指令依序執行（不因忙碌失敗）、操作日誌與業務寫入同交易、交易性 outbox、型別化錯誤、可注入時鐘，以及 `MemoryStore` 參考實作。
- [x] 2b `infrastructure/storage_sqlcipher`：單一 SQLCipher 資料庫（WAL、`synchronous=FULL`）、只能新增的事件日誌、不可改的操作日誌與 outbox，實作 `app_core` 介面並通過同一組行為測試；錯誤金鑰、未加密函式庫、較新 schema 都會拒絕開啟。
- [x] 2c-1 SIGKILL 行程終止測試進 CI（固定亂數種子，8 輪，驗證完整性與「事件數＝操作數」）。
- [x] 2c-2 10 萬筆事件基準測試（寫入、單一指令 p95、尾頁讀取、重開、完整性檢查都有上限）；投影表隨領域模組遷入時再加。
- [x] 2d `infrastructure/backup_security`：主金鑰包裝資料庫金鑰與備份金鑰 epoch；密碼（NFC＋Argon2id）、救援碼、裝置三種 slot；改密碼、換救援碼、備份金鑰輪替。

## 階段 1 已完成

- 分攤改為最大餘數法（`largest-remainder-v1`）：10.00 依 1:2:3 分成 1.67／3.33／5.00；分期的尾差從第一期開始分配。
- 新增 ISO 4217 幣別登錄表 `Currency.iso`，移除程式中寫死的 `JPY ? 0 : 2`。
- 新增嚴格的 `parseMinorUnits`，取代解碼器中的 `BigInt.parse`（拒絕 `+`、空白、十六進位與 `-0`）。
- Domain 套件預設禁止 `dart:io`；`market_data` 暫列例外，網路程式在階段 3 移出。
- 修正兩個因真實時鐘而時好時壞的轉帳畫面測試。
- 待辦：Domain 套件加 lint 設定、禁止未說明的 `throwsA(anything)`（需先清掉既有違規）。

## 階段 0 待辦

- [ ] 建立預覽簽章金鑰並設定 GitHub Secrets（見下方）。
- [ ] 把預覽金鑰的 SHA-1 加入 Google Cloud 的 Android OAuth 用戶端。
- [ ] 安裝第一個固定簽章版本前，先匯出備份（簽章改變的這一次仍需解除安裝）。
- [ ] 加一個「在 posting 交易中殺掉行程後重開」的行程終止測試。

## 預覽簽章 Secrets

| 名稱 | 內容 |
| --- | --- |
| `ANDROID_PREVIEW_KEYSTORE_BASE64` | 預覽用 `.jks` 的 base64 |
| `ANDROID_PREVIEW_STORE_PASSWORD` | keystore 密碼 |
| `ANDROID_PREVIEW_KEY_ALIAS` | 金鑰別名 |
| `ANDROID_PREVIEW_KEY_PASSWORD` | 金鑰密碼 |

## 後續階段

| 階段 | 內容 | 粗估 |
| --- | --- | --- |
| 1 地基整理 | 幣別登錄表、最大餘數分配、嚴格數字解析、Domain 禁止 `dart:io`、lint | 第 2–3 週 |
| 2 新儲存與應用核心 | 事件日誌加投影、操作日誌、outbox、金鑰階層、行程終止測試進 CI | 第 4–7 週 |
| 3 領域移植 | 帳戶與收支、catalog、信用卡、投資、市場資料 | 第 6–12 週 |
| 4 UI 重建 | 拆掉 `main.dart`、金額指令狀態機、l10n、懶載入 | 第 10–15 週 |
| 5 備份 v2 與雲端 | 串流分塊格式、可續傳上傳、舊備份匯入 | 第 12–15 週 |
| 6 上線驗證 | 實機測試、並行記帳對帳、正式簽章版 | 第 15–17 週 |
