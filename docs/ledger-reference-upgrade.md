# 分類引用世代升級與工作階段

本批延續[交易分類引用](ledger-category-references.md)，將已驗證的 schema 5／snapshot 4／ledger module 3 接入 Ledger 世代管理、工作階段、一般備份及持久安全備份。對應[實作安排 M1-02](implementation-plan.md)的分類資料接入；仍未開放 App 分類畫面，也不代表全部 M1 或平台 gate 通過。

## 已知版本升級

`LedgerStore(categoryReferences: true)` 同時啟用 Categories 及受保護的升級控制紀錄。新帳本直接建立 schema 5；已有 schema 3／4 可以唯讀檢查、匯出，但不能藉新模式開檔就偷偷升級或寫入。未知版本仍拒絕。

新增 `planCategoryReferenceUpgrade`／`upgradeCategoryReferences`，明確限定 **schema 4 → 5**，路線為 `ledger-4-to-5-v1`。既有 3 → 4 與新路線共用安全備份及發布程式；來源版本、目標模式及路線必須吻合，不允許以 3 → 4 的 request 實際發布 schema 5。schema 3 來源仍須依既有路線先升至 4，每步各有備份與 receipt。

規劃保存來源世代及當時完整 snapshot 摘要。真正執行時，在同一生命週期排他權內重新驗證來源、保存加密安全備份、flush 後重讀、分別以原密碼與救援金鑰驗證全部內容，再轉成新 snapshot、建立新 DB／key、驗證並原子發布。金融或分類改動使來源摘要不同時，舊計畫拒絕；不暗中改用新來源。

舊 DB／key 完整保留。已完成升級的重送回傳原 receipt，不替換其後的新交易或重新啟用舊世代。中止後重試沿用同一份已保存備份及實際檔案摘要；即使明文相同，換成另一份 envelope 也不能冒充已登記的備份。只有建立空檔就中止的備份保留原樣，使用新的操作及備份 ID 再試。

一般還原可將已知舊備份轉為 schema 5；這是明確的還原發布操作，與來源就地升級不同。新格式備份仍被舊 reader 拒絕。一般備份與 `createSafetyBackup` 都保留分攤版本及歷史位置。

## 公開讀寫

`LedgerSession.post` 接受收入／支出的版本化分攤，沿用 Domain 與持久化驗證，不讓 UI 取得 SQL 或 adapter。新增 `allocations(workspace, eventId)`，回傳不可變的分類 ID、Money、引用版本與歷史序號；原本沒有分攤的有效事件回傳空集合，事件不存在或 workspace 不符則拒絕。工作階段關閉後不得繼續讀取。

分類目前名稱及合併後的身份由既有 `categories()` 查詢提供；歷史引用不被改名／合併／封存改寫。分攤不增加資金 leg，不重複計算收入或消費。舊 receipt 保持精確重送身份。

## 容量與回滾

維持每個 store 的 32 帳戶、5,000 金融事件、256 分類及 1,024 次分類變更；跨 workspace 共用上限。每列 UTF-8 JSON bytes 限制沿用[分類工作階段](category-session.md)。新增分攤計入全域 **50,000 可攜列／16 MiB** 上限，不能僅按事件數接受寫入。

加入分攤後，若繼續把每種表的最大列數乘上最大列大小，會把可用資料集也一律拒絕。本批改成在工作階段第一次新操作時完整驗證 snapshot，取得實際列數及 bytes；之後只累加本次新增列、扣除被替換的分類狀態列，再加入新狀態、歷史、receipt 及 Audit。對每列額外保留一個逗號，因此最多保守多算九個 bytes，不低估備份大小。

資料及容量計數都在同一 transaction 結果下提交或回復。超過全域／每列限制時，整筆事件、分攤、receipt 及 Audit 回滾，後續合法命令仍可執行；不因失敗而耗掉容量。既有操作仍先處理 replay／conflict，不被滿額拒絕掩蓋。沒有每筆重掃完整帳本或重新重放所有分類歷史。

此政策只適用有界 `LedgerSession`；內部 adapter 及 `LedgerStore.post` 仍是既有低層入口，不能據此承諾所有內部寫入都受相同產品容量管理。App 接入時須走工作階段並明示無法接受的資料，不截斷匯入。

## 驗證與後續

新增驗證涵蓋安全備份及完整內容保留、來源 metadata 變動使計畫失效、錯誤路線／目標拒絕、已完成升級的重送、備份 bytes 與原憑證、11 處獨立程序中止重試，以及安全備份／含分攤新備份各以密碼和救援金鑰在刪除來源 DB／key 後還原。

工作階段案例驗證歷史引用、workspace 隔離、不可變／關閉後拒絕、20 次並行重送、receipt 過大時全量回滾並可接續操作、跳脫字元與中文字名稱更新，以及跨表容量准入。大量案例將同一帳本填至 5,000 事件、7,497 分攤、256 分類及 1,024 次歷史；合併／封存後再核對密碼／救援還原、獨立金額計算、完整 snapshot 及滿額時 replay。

[大量資料原始結果](test-results/ledger-reference-upgrade-scale-2026-09-27.json)記錄完整 snapshot 8,610,791 bytes、獨立計算餘額 2,511,000 minor units、案例約 382.14 秒；當時同時執行其他本機回歸，不能作為隔離效能或 Android 承諾。當次套件通過數以[工作進度](work-progress.md)及其驗證清單為準。依[CI 額度政策](ci-budget-policy.md)，本批雲端未執行，沒有操作手機。主機程序中止不是 Android OS kill、斷電或真實磁碟滿的證據。

下一批將既有 App 的備份憑證、升級規劃／恢復及容量准入接至上述已知路線，再提供簡潔的分類與錄入畫面。正式 BackupProfile 治理、平台升級驗收、Tag／Merchant 與其他 CORE 仍保留後續範圍。
