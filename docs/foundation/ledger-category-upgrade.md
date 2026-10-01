# Ledger schema 3 → 4：備份、轉換與世代發布

本批接續 [PR #38 升級控制紀錄](storage-upgrade-receipts.md)及[分類保存](categories-persistence.md)，把真實 Ledger、SQLCipher 與雙憑證安全備份串在同一生命週期鎖內。對應 [RC-05](../architecture/architecture-baseline-v1.0-rc1.md#rc-05)及[資料演進 EVOL-01～08](data-evolution-contract.md)，只支援具名 `ledger-3-to-4-v1` 路徑；App 預設仍是 schema 3，尚未開放自動升級或分類 UI。

## 來源與版本

- `LedgerStore(categoryAware: true)` 明確啟用新路徑，且必須提供加密控制紀錄。可讀取已知 catalog 2／3 與財務 schema 3／4；讀取先核對實體版本，以來源版本擷取 snapshot，不因新版 reader 開檔就原地改表。
- 目標財務 schema 4／snapshot 3 加上 `categories: 1` 及兩張分類表。舊七表完整列、金融 receipt、Audit 與餘額保留；新分類表初始為空，不猜測歷史分類或放寬既有 allocation 限制。
- `planCategoryUpgrade` 在鎖內擷取目前 generation 及完整 live snapshot 摘要，回傳含操作／備份身份的不可變請求。來源不存在時不建立 catalog 或 key；來源未知版本時也不產生備份。
- 這個請求需要由呼叫者保留以供重試；規劃函式本身不提供正式 App 的持久工作排程。規劃後若又新增交易，來源摘要改變，執行升級會拒絕，應重新規劃新操作。

## 執行順序

1. 取得生命週期鎖，核對控制紀錄、來源身份及目前內容摘要。
2. 呼叫共用安全備份保存程式，在 store 外的既有受控目錄，獨占建立指定 backup ID 的 envelope；明確提供密碼與已保留的救援文字。
3. flush 後重讀實際檔案，以兩種憑證分別解鎖，逐 bytes 核對完整來源 snapshot。新檔須與建立時密文一致；保存摘要直接計算檔案原始 bytes，避免 UTF-8 BOM 被解碼忽略。
4. 將已知舊 snapshot 轉成目標格式，再交由共用 GenerationStore 新建 slot、目標加密 DB 及本機身份。catalog 2 → 3 的新表與 intent／attempt 在備份驗證後才以同一 transaction 建立。
5. 匯入及驗證目標，關閉重開核對完整內容；以既有單一 COMMIT 同時提交升級結果與 active 參照。舊世代、金鑰與安全備份保留。

安全備份的一般入口與升級入口共用同一保存／雙路讀回程式；原 `createSafetyBackup` 仍拒絕任何既有檔案。只有升級重試能嘗試使用同 backup ID 的既有完整檔，且必須再次驗證密碼、救援 key、完整來源資料及已登錄的密文摘要。不另建一套發布或財務轉換狀態機。

## 故障與重試

- 剛建立空備份檔就中止：保留部分檔，重試拒絕覆寫；重新評估後用新的 operation ID 與 backup ID 再試。不能刪除部分檔就假裝原操作完成。
- 備份完整寫入後中止：同請求可用原有兩種憑證讀回並沿用**同一份密文**。已登錄 intent 後，即使換成相同明文的新 envelope，摘要不同也拒絕。
- catalog DDL 交易中止：回滾至 catalog 2。之後目標匯入中止：保留完整 catalog 3 與仍有效的 schema 3 來源，新 reader 可繼續恢復／升級；舊 reader 拒絕 catalog 3，不降級寫入。
- 發布前中止仍指向完整舊資料；發布後中止保留新資料。相同請求取得原 receipt；後續入帳或還原其他世代後重送升級，不重作轉換或重新啟用退役世代。
- 等待取消、錯誤憑證、錯誤目錄、損壞／來源不符備份與未知版本均停止並保留來源。原型錯誤去敏，不輸出路徑、密碼或救援文字。

## 本機驗證範圍

新增測試位於 `prototypes/ledger_generation/test/category_upgrade_test.dart`：

- 真實 live posting 進入安全備份；schema 3 原檔 bytes 保持、目標 schema 4、完整 snapshot、餘額及 receipt replay 一致；升級後可保存分類。
- 11 個獨立程序退出點：backup:created、backup:written、backup:verified、upgradeCatalogWriting、reserved、table:events、table:categories、table:category_changes、validated、publishing、published。重啟保持舊／新完整資料，重試只產生一個 committed 結果。
- schema 3 安全備份與含分類的 schema 4 備份，各自刪除來源 DB／key 後，以新程序、單一密碼或救援文字、新 key slots 還原；核對完整資料、115 餘額及原金融 receipt replay。
- 5,000 筆事件容量回歸：原 fixture 3 筆加 4,997 筆新增與 4,997 次重送；升級前後完整資料、獨立餘額計算、安全備份雙路、目標備份雙路還原、重送去重與容量保護。這是單一合成帳本的目前容量，不表示 100k 或任意資料量已通過。

執行時先重建 `ledger_worker`，再用[本機驗證入口](../delivery/ci-budget-policy.md)或套件 README 的命令。大量案例成功後輸出 `.dart_tool/category-upgrade-scale-result.json`；本輪[原始結果](../test-results/2026-09-27/ledger-category-upgrade-2026-09-27.json)記錄來源 5,194,347 bytes、目標 5,194,400 bytes，升級約 27.56 秒，全案例約 257.90 秒。這次同時執行其他套件回歸，數值不是隔離效能保證或 Android 承諾。雲端依額度政策維持停用；完整檢查範圍見[工作進度](../work-progress.md)。

2026-09-27 本機結果：新增 30 項升級案例通過，含上述 5,000 筆資料集；完整 14 套件主機清單共 421 項、格式、靜態分析、五個原生 worker 建置與實際依賴掃描通過。[驗證清單](../test-results/2026-09-27/ledger-category-upgrade-host-2026-09-27.json)明列最後預檢補強的針對性回歸，重複案例不重複計數。雲端與手機皆未執行。

## 仍保留的 gate

這是既有模組的單一路徑主機整合，不能代表所有未來模組／版本的通用 migration registry 已完成。正式 BackupProfile、升級請求的產品持久化與操作引導、分類交易引用／UI、跨模組容量預檢及失敗空間保留仍待接入。

未測 Android 升級、OS 重啟／斷電或真實磁碟滿；fixture key 檔不是正式平台 secure storage。原型來源不支援未知 hot journal 自動修復、清理舊世代、遺失控制紀錄救援或防整套舊資料回放。此批沒有開放新產品入口，M1／M2／M3 gate 不變。
