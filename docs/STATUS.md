# 狀態

最後更新：2026-10-04

## 現況

底層重建完成，介面正在重做。架構見 [ADR-0001](adr/0001-target-architecture.md)。逐項經過與細節請查 git 歷史（PR #74）。

已完成：

- **儲存**：單一 SQLCipher 資料庫；事件只新增，投影表（餘額、月報、帳單、持股、預算、定期交易）和事件同一交易更新；可從事件日誌完整重建。同一個檔案只能有一個連線開啟。
- **記帳**：開戶（含期初）、收入、支出、轉帳（跨幣、手續費可用任一幣別）、退款、沖銷、更正、刪除、備註；分類、標籤、商家（可合併）；外幣以入帳當下的台幣約當計入報表。
- **信用卡**：授權與入帳、帳單（前期結轉、分期當期、最低應繳、假日順延）、繳款、退款、作廢、發卡行費用與回饋、國外刷卡、結帳日變更與單期覆寫；分期尾差併入第一期。
- **投資**：買賣（FIFO／平均成本）、股利（補充保費、除息日）、分割、配股、減資、作廢；台股手續費、證交稅與 T+2 試算；複委託台幣交割。
- **預算、定期交易**：每月沿用的預算；定期交易每期確認一次，可改實際金額。
- **金鑰與備份**：密碼、救援碼、裝置金鑰三種解鎖；備份 v2（分塊加密、還原時重播驗證）；Drive 續傳上傳、分代保留、排程與健康狀態。
- **行情**：TWSE、TPEx 日終、ECB／CBC／Frankfurter 參考匯率；盤中來源只作選用（Yahoo 需使用者手動開啟，見 ADR-06）。
- **測試與 CI**：所有套件同一份嚴格 lint；記憶體版與 SQLCipher 版對照、重播、升級、強制結束、拒絕案例、完整備份來回、1 萬筆規模測試都在 CI。

## 程式碼審查（2026-10-04，外部審查 main@51c5255）後續

- [x] C-01 正式入口只走加密帳本；預覽另有入口，測試確保不混用。
- [x] C-02 還原先寫暫存資料庫，檢查後才換上，失敗不留半套。
- [x] H-02 Drive 分段下載，核對大小與 SHA-256。
- [x] 3.2 帳本的 workspace 存進資料庫，不再從事件推測。
- [x] 4.3 台股費稅、補充保費依交易或發放日期選費率。
- [x] M-04 App 的合計以台幣為準，無法估值的帳戶與筆數另列。
- [x] M-01 `LedgerStore`、`Bookkeeping` 依領域拆檔，對外 API 不變。
- [x] M-03 測試確保各套件 lockfile 的相同依賴版本一致（未改用 pub workspace：無法在不跑 pub 的情況下安全轉換）。
- [x] M-02 每週 OSV 弱點與授權掃描；Dependabot 每月分組更新。
- [x] P3 分攤、匯率組合、帳單週期的 property tests；規模與基準測試數字存成 CI artifact。
- 不做：C-03 舊資料匯入（使用者決定當新 App）；CodeQL（不支援 Dart）；mutation testing、完整 SBOM（個人 App 投入產出比低）。
- [ ] H-04 main 分支保護與 required checks（使用者在 GitHub 設定）。
- [ ] H-01、H-03、H-05 Android 平台、簽章發佈與真機失敗矩陣（併入下方「Android 與真機」）。

## 待辦

### 新 UI（介面重做時一起做）

- [ ] 4c 金額輸入、分類／標籤選擇、信用卡與投資畫面。
- [ ] 4d l10n（字串移到語系檔）、懶載入、清單分頁；App 不再寫死 TWD（G4-23、G4-22、G4-13）。
- [ ] 接上已寫好的模組：`amount_input`、`data_exchange`（CSV 匯入匯出）、`market_data`／`market_adapters`、`investments` 的績效與 XIRR、`reports` 的 MonthlyReport／AssetReport、`ledger` 的搜尋；備份排程的定時器。

### Android 與真機（最後做）

- [ ] 4b-2 Android 平台設定、Keystore 裝置金鑰、解鎖流程、背景喚醒（G9-01、G3-21）。
- [ ] Google 登入與 Drive 真機驗收（見 [Google Drive 設定](delivery/google-drive-setup.md)）。
- [ ] 固定簽章：建立簽章金鑰並設定 GitHub Secrets（下表）；把 SHA-1 加到 Google Cloud 的 Android OAuth 用戶端。
- [ ] 實機效能數據（G5-13）、真實行情資料（G2-18）。

## 簽章 Secrets（4b-2 時設定）

| 名稱 | 內容 |
| --- | --- |
| `ANDROID_PREVIEW_KEYSTORE_BASE64` | `.jks` 的 base64 |
| `ANDROID_PREVIEW_STORE_PASSWORD` | keystore 密碼 |
| `ANDROID_PREVIEW_KEY_ALIAS` | 金鑰別名 |
| `ANDROID_PREVIEW_KEY_PASSWORD` | 金鑰密碼 |
