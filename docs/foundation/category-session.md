# 分類工作階段與備份容量

此批延續 [Ledger 分類升級](ledger-category-upgrade.md)，在 `categoryAware: true` 的加密帳本提供分類公開操作與讀取。仍是主機整合能力；後續[分類引用工作階段](ledger-reference-upgrade.md)已接分攤與 schema 5，Tag／Merchant、正式 App 升級引導與 UI 尚未完成。

## 操作邊界

`LedgerStore.withSession` 的 `CategorySession` 接口接受業務 ID、名稱、類型及預期版本，提供新增、改名、移動、封存／重新啟用、合併及讀取。UI 不取得資料庫或 data adapter。分類與金融操作共用生命週期排他權、序列佇列、SQLite transaction、operation namespace、receipt 與 Audit。

沿用 Categories Domain 的雙層、類型、版本及歷史轉向規則；不另外實作一套表單規則。讀取回傳不可變的 `CategoryCatalog`。callback 結束或失敗後，已接受的命令執行完畢，工作階段便失效；不能保留它繞過關閉後的生命週期。舊 schema 3 工作階段明確拒絕分類入口。

回查並修正兩項既有問題：工作階段 snapshot 依實際 schema 選擇格式，schema 4 可匯出分類與歷史；帳本身份查詢同時涵蓋帳戶與分類，只有分類而沒有帳戶的 workspace 不再消失。

## 有界工作階段的容量保護

目前工作階段仍限於期初與單腿收支。全 store 共用上限為 32 帳戶、5,000 筆金融事件、256 分類及 1,024 次分類變更。分類封存／合併不回收 ID 或歷史額度，跨 workspace 也不能繞過全域上限。這是限定整合的保守容量，**不是最終 M3 容量或正式產品限制**。大規模驗收繼續區分真實新增與重試，不將不同帳本或重試混算為單一帳本容量。

容量同時限制 UTF-8 JSON 編碼後的每列大小，而非僅檢查字數或資料筆數：帳戶與建帳 receipt 各 4,096 bytes；其他 receipt、分類狀態及分類歷史各 1,024 bytes；其餘金融與 Audit 列各 512 bytes。序列化包含巢狀 JSON、跳脫字元及中文，所以不會漏算名稱在可攜備份中的實際成本。

上一批 schema 4 以各表最大列數與每列 bytes 推算，最多 23,392 列、空 snapshot 標頭加 15,952,736 bytes。接入 schema 5 分攤後已改為[實際增量容量](ledger-reference-upgrade.md)：第一次驗證完整 snapshot，此後按新增與替換列計算 bytes／列數，所有模式共用全域 50,000 列／16 MiB 保護，任何超額寫入在 commit 前回滾。原估算保留為歷史設計紀錄，現行程式不再以這個最壞值拒絕所有新格式。

每次工作階段的第一個新操作，在排他權及 transaction 內驗證既有 snapshot 是否符合目前可支援範圍；通過後只檢查新增數量及此次異動列，任何超標都在外層 commit 前回滾。工作階段內沒有外露 DB handle，所有公開寫入走相同佇列，避免每筆交易重掃全部歷史。備份／還原仍保留獨立完整語意驗證，容量檢查不代替它。

已有 receipt 的操作先交給原本的精確輸入比對，已完成操作可重送，輸入不同仍回報 conflict，不被容量錯誤掩蓋。有效但超過工作階段容量的外來資料仍可讀取及匯出（前提是仍符合底層備份格式限制），新操作拒絕；不刪除歷史，也不截斷備份。

既有 App 的匯入檢查改共用 `validateSessionCapacity`，另保留 App 單一 workspace 限制及原本錯誤映射。低層 adapter／`LedgerStore.post` 不受這個限定 session 政策管理，不能把此保證推廣到所有內部寫入入口；接續交易分類、轉帳或其他新指令時，必須同步更新容量政策、每列檢查與還原驗收。

## 驗證與限制

新增工作階段案例涵蓋全部分類命令、歷史不變、僅分類 workspace、舊格式拒絕、20 次同時重送、錯誤後佇列繼續、版本／類型錯誤完整回滾、關閉後讀寫拒絕、跨 workspace 隔離及金融／分類 operation 衝突。

填滿 256 分類及 1,024 次歷史後核對拒絕新分類操作、保留既有 replay／conflict、仍能依金融額度新增帳戶、完整 snapshot 及救援還原。另驗證 100 個引號、反斜線、中文字與 50 個 emoji 的名稱在密碼／救援獨立還原後不變；有效但含大量空白的外來 receipt 仍可匯出，新寫入拒絕。

既有 5,000 事件升級測試擴充為同一帳本再填滿分類及歷史額度，保留舊世代、金融餘額、完整 bytes 比對、兩條備份還原及重送驗證。[原始結果](../test-results/2026-09-27/category-session-scale-2026-09-27.json)顯示完整 snapshot 為 6,060,117 bytes、案例約 216.08 秒；當時另有本機套件回歸並行，不能當作隔離效能承諾。

本輪新增 8 項案例，連同 Ledger 92、還原 38、App 19 及架構 15，共 164 項獨有案例通過，格式、靜態分析、兩個原生 worker 重建與架構掃描通過。[驗證清單](../test-results/2026-09-27/category-session-host-2026-09-27.json)保留實際範圍，其餘十個套件未在此批重跑。這不是 Android 實機、真實斷電或磁碟滿證據。

本批依 [CI 額度政策](../delivery/ci-budget-policy.md)在本機驗證，雲端未執行，手機未操作。分類 UI、正式 BackupProfile 及平台升級 gate 不因本機接口完成而提前開放。
