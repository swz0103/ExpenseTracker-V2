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

### C2：可串流快照格式（下一個儲存里程碑）

- 新格式以 manifest 固定 schema、workspace、表清單、總列數／bytes、每塊範圍與 digest。
- 每張表依穩定主鍵輸出 bounded chunks；每塊獨立驗證順序、列數、bytes 與 digest，最後核對 manifest root。
- 還原寫入全新 generation，逐塊驗證並提交；任何未知表、缺塊、重塊、順序錯誤或 digest 不符都拒絕，舊 generation 保留。
- 密碼與救援文字仍只解出同一資料金鑰；先設計可中止、可清理的暫存與 authenticated streaming，再決定 envelope 版本。
- 舊 snapshot 維持唯讀匯入；新格式不得讓舊 App 誤認可讀。升級／回退與 interrupted restore 必須有固定測試。

### C3：追加寫入與容量 admission

- 保留 SQLCipher Ledger 作權威，不以 UI cache 取代。
- 容量計數持久化為可驗證 projection；交易內同步更新，開啟時抽樣／完整重建可核對，碰撞或不一致 fail closed。
- 將每筆寫入需要的全量檢查拆成局部 constraint、索引查詢與週期性完整驗證；不能移除 receipt、audit、版本或財務重播。

### C4：20k 及設計目標驗證

- 只有 C2/C3 具備完整雙憑證乾淨還原後，才建立 20,000 筆合法資料集，再決定下一級上限。
- host 保存 100／1k／5k／20k 的冷熱樣本；Android profile 保存最低與現行 API 的互動 p50/p95、frame、RSS peak、備份／還原、process death 與磁碟不足。
- 門檻必須由至少三次基線與產品可接受時間核定，不在設計文件虛構毫秒 SLA。

## 發布限制

在 C2/C3 完成且 20k 雙憑證還原通過前，維持 5,000 events、50,000 authority rows 與 16 MiB payload 的 fail-closed gate。索引改善不代表容量上限已提高，也不替代 R08 Android 候選版驗收。
