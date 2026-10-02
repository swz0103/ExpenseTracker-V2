# 容量演進計畫（R04／R06）

## 已建立的基線

`tool/current_capacity_profile.dart` 固定使用 App 現行 schema，依序量測 100、1,000、5,000 筆的寫入、首頁首批、帳戶摘要、月報、全分頁、加密備份、乾淨還原與重開。輸出為機器可讀 JSON；合成資料不接觸使用者檔案、平台憑證或網路。

2026-10-02 Windows 單次前後對照發現，時間軸缺少 `(workspace,business_date DESC,id DESC)` 索引，使 keyset 每頁重複排序。補上可重建、非權威索引後，5,000 筆完整分頁從 20,540 ms 降為 2,361 ms，首頁首批從 160 ms 降為 9 ms；備份與還原維持約 25／46 秒。完整數據見[主機證據](../test-results/2026-10-02/current-schema-capacity-profile-windows-2026-10-02.json)。

## 不直接放寬上限的原因

- 5,000 筆已產生約 5.21 MB 明文快照與 20,002 權威列；目前 16 MiB／50,000 列會早於 20,000 筆目標到達。
- 備份與還原仍需完整 materialize、驗證與加密；新增查詢索引不會降低這條路徑的記憶體峰值或中止成本。
- 逐筆寫入 5,000 筆累積約 4.5 分鐘；這是合成批次，不等於互動延遲 p95，但足以否定只改常數的做法。
- 20,000／100,000 筆不能在現有 fail-closed 上限下合法製造；為了跑 benchmark 暫時繞過上限，無法證明正式格式可備份與還原。

## 分階段實作

### C1：觀測與低風險查詢修正（本批完成）

- 現行 schema 分階段 profile 工具與機器可讀證據。
- 時間軸複合索引；新帳本建立，既有同 schema 帳本開啟時 `IF NOT EXISTS` 補建。
- 索引不屬於權威資料與 portable snapshot；補建前後財務 snapshot 相同。

### C2：可串流快照格式（容器、capture、stage、認證加密原型完成，正式接線待做）

- [x] 檔案容器原型以 manifest 固定 format／version／schema、表順序、總列數／bytes 與每塊 digest；manifest 另有 SHA-256 完整性 digest。
- [x] writer 接受 row stream，以 row／bytes 雙上限輸出 canonical NDJSON；暫存目錄完整驗證後才 rename，失敗不留目標。
- [x] `SnapshotCodec` 在同一 read transaction 內驗證 authority 與實際主鍵，依 stable tuple keyset cursor 把每張 SQLCipher 表串入 bounded chunks；這仍是原型入口，尚未取代正式 App 的單檔 capture。
- [x] 還原先完整驗證，再以單一 transaction 逐塊寫入全新 staged database；任何未知表、缺塊、重塊、順序錯誤、canonical row 或 digest 不符都拒絕。後段 chunk 中途損壞會回滾已寫列並刪除 stage／sidecars。
- [x] 密碼與救援文字各自包裝同一隨機 AES-256-GCM data key；Argon2id 每次開啟只執行一次。加密 manifest 與每個 chunk 使用獨立 nonce，並以固定 session header＋用途檔名作 AAD，拒絕竄改與 chunk 交換。SHA-256 僅保留為內層完整性，不冒充 authentication。
- [x] 還原端將 authenticated rows 直接串入單一 transaction 的新 database，不重建明文 chunk 目錄；後段 authentication failure 會回滾並清除 stage。
- [x] 備份端可由 SQL authority stable-key rows 直接產生認證密文，記憶體只保留單一 bounded chunk；manifest／chunks 均不以明文落地，完整自驗後才發布目標目錄。
- [x] `RestoreStore` 接回既有 promotion journal：密碼／救援雙路在新 stage 完整驗證後，沿用 `prepared → oldMoved → newMoved`；四點例外注入都恢復舊 current 並可重試，既有跨程序中止測試仍覆蓋同一 promotion helper。
- [x] 舊單檔與新分塊使用不同固定 format/version 與 `R1`／`R2` 救援碼前綴；雙向解析及跨格式救援碼皆拒絕，舊 `RestoreStore.restore` 保留作相容匯入。
- [ ] 下一步核定正式 envelope version 與 App／雲端切換策略。
- 舊 snapshot 維持唯讀匯入；新格式不得讓舊 App 誤認可讀。升級／回退與 interrupted restore 必須有固定測試。

容器／資料庫 capture／stage 定向 9/9、authenticated container 4/4、backup_envelope 20/20、restore／promotion 32/32、validated_restore 完整 147/147 及靜態分析通過；證據見[分塊容器原型](../test-results/2026-10-02/chunked-snapshot-container-prototype-host-2026-10-02.md)。它尚未切換正式 App，不提高現行上限。

### C3：追加寫入與容量 admission

- 保留 SQLCipher Ledger 作權威，不以 UI cache 取代。
- [x] C3a：首次 admission 不再 materialize 完整 portable snapshot；完整 authority 驗證後，按 stable primary-key keyset 分頁，逐列套用 byte／table count gate，計算結果與既有 canonical conservative usage 精確相等。完整 Ledger 301/301、還原 148/148 通過；[證據](../test-results/2026-10-02/streamed-capacity-admission-host-2026-10-02.md)。
- [ ] C3b：容量計數持久化為可驗證 projection；交易內同步更新，開啟時抽樣／完整重建可核對，碰撞或不一致 fail closed。
- 將每筆寫入需要的全量檢查拆成局部 constraint、索引查詢與週期性完整驗證；不能移除 receipt、audit、版本或財務重播。

### C4：20k 及設計目標驗證

- 只有 C2/C3 具備完整雙憑證乾淨還原後，才建立 20,000 筆合法資料集，再決定下一級上限。
- host 保存 100／1k／5k／20k 的冷熱樣本；Android profile 保存最低與現行 API 的互動 p50/p95、frame、RSS peak、備份／還原、process death 與磁碟不足。
- 門檻必須由至少三次基線與產品可接受時間核定，不在設計文件虛構毫秒 SLA。

## 發布限制

在 C2/C3 完成且 20k 雙憑證還原通過前，維持 5,000 events、50,000 authority rows 與 16 MiB payload 的 fail-closed gate。索引改善不代表容量上限已提高，也不替代 R08 Android 候選版驗收。
