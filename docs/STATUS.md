# 狀態

最後更新：2026-10-03（階段 0 已合併）

## 目前階段：階段 1 地基整理

全專案健檢（189 項問題，P0 3 項）後決定：保留 `packages/` 的值物件與領域規則，重建儲存層、應用層與 UI。完整說明見 [ADR-0001](adr/0001-target-architecture.md)。

**功能凍結**：重建完成前不加新功能，只修正錯誤。新程式碼不得新增對 `prototypes/` 的依賴。

## 階段 0 已完成

- 寫入中被強制關閉後，SQLite 留下的 journal 不再被當成竄改；改由 SQLite 自行回滾（`storage_generation`）。
- 更正有標籤或商家的交易後，備份不再失敗（`modular_persistence` 標籤與商家驗證器）。
- 信用卡交易加備註後，卡片驗證、帳單與 17→18 升級不再失敗。
- 預覽版改用固定簽章金鑰，之後可直接覆蓋安裝。
- 預覽版與正式版發佈前，必須先通過同一 commit 的完整驗證；只有發佈步驟持有寫入權限。
- 移除未使用的 `transaction_boundary` 原型、兩條手動 workflow、未使用的 Twelve Data 憑證畫面，以及過期文件。

## 階段 1 進行中

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
