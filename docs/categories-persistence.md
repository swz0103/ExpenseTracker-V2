# 分類保存、操作歷史與可攜格式

M1-02 的下一個子集：將 [Categories 規則](../packages/categories/README.md)接到共用 Drift／SQLite 交易及 SQLCipher 暫存還原。屬於 [RC-05](architecture-baseline-v1.0-rc1.md#rc-05)及[資料演進契約](data-evolution-contract.md)。本批沒有開放分類 UI，也沒有把完整 App 升級協調器標為完成。

## 主責與原子性

Categories 的資料 adapter 擁有 `categories(workspace,id,payload)` 目前狀態及 `category_changes(workspace,ordinal,operation_id,id,payload)` 完整變更後狀態。每個 workspace 的 ordinal 由 1 連續遞增，不以裝置時間排序業務依賴。

操作包括新增、改名、移動、封存／啟用及明確合併；`category-v1` input 保留原 ID、參數與必要的來源／目標版本。同一 SQLite transaction 保存目前狀態、歷史、共用 receipt 及 Audit，任何一步失敗均回滾。分類及金融操作使用同一 `(workspace, operation_id)` 去重空間；既有同 ID／同內容重送回傳原結果，不重寫之後的版本，不同內容則拒絕。

原 `FinancialWorkflows` 的交易與去重程式抽到 `OperationWriter`，行為保持相同；原 `workflows.dart` 保留舊公開型別 export，避免下游無必要換接口。沒有另建分類專用資料庫或另一套互不相通的 receipt。

## 格式與版本

- 原 schema 2／snapshot 1、schema 3／snapshot 2 的格式及預設行為保留。
- 明確 `categoryAware` 時使用財務 schema **4**、snapshot **3**，module manifest 加入 `categories: 1`，原 local identity 仍是 1。
- Categories 自己提供欄位清單與 schema 片段，備份組合引用同一份欄位契約；未知表、欄位、module 或版本仍拒絕，不默默忽略。
- `categoryAware` 必須有已指定的本機世代身份。可攜 snapshot 不攜入舊 generation／slot，目標重新給定配對。
- 舊 schema 的已知 snapshot 可轉為新格式，新增兩張空分類表；原金融、receipt 與 Audit 列保留。原型一直拒絕未驗證的 allocation，這次仍拒絕，不能憑空補分類名稱或猜測孤兒引用。

## 歷史驗證

還原及完整擷取會按 workspace／ordinal，透過相同 Domain 逐項重放分類命令。每一步都核對歷史 payload、receipt 結果 ID、Audit 類型，最後與目前分類列完整比較。僅有「最後的分類樹合法」不夠；缺歷史、版本跳號、偽造改名、錯誤 Audit、缺 receipt 或未知操作都拒絕。

金融事件的 receipt 基數只計金融操作，分類與金融實體即使在不同業務表使用相同 ID，也不互相增加事件入帳次數；各種 receipt 仍需各自的完整驗證。分類操作不產生金額、event 或 leg，不改變餘額。

CategoryCatalog 本身建立替代鏈索引是 O(n)，但完整歷史重放會依每一步 catalog 規模付出成本；沒有把它宣稱為任意歷史長度都線性。開放 UI 前仍須把各模組歷史列數和 bytes 納入統一容量預檢，避免寫入後才發現超出可備份範圍。16 MiB／50,000 權威列限制未放寬。

## 升級保護與目前限制

直接用 schema 4 reader 開啟 schema 3，會在任何新 DDL 前拒絕；不透過 Drift 自動就地升級。受控路徑先擷取舊來源、保存並雙路讀回驗證加密備份，再在新檔建立 schema 4 stage，核對金融與分類資料。失敗的 stage 留作診斷，不修改原來源。

本批驗證這個暫存轉換與備份原語；**正式升級協調器、生命週期排他鎖到發布的完整串接、版本化 upgrade receipt、schema 4 的 GenerationPayload／session、分類交易引用及 UI 尚未接入**。現有 App／LedgerStore 仍明確使用 schema 3，拒絕未知 schema，不自動開啟 schema 4。新版本的獨立程序中止與裝置驗收仍需後續補齊，不能用舊版本已通過案例代替。

## 本輪驗證

新增 13 項保存／並行／去重與回滾、6 項完整快照／相容性／篡改、4 項加密雙路還原及來源保護案例。受影響既有交易、還原、加密、Ledger 世代及 App 的回歸一同執行；exact CI 狀態以本分支 PR 為準。

另用真實 SQLCipher 測試 256 個分類、1,024 次 metadata 變更、1,024 次逆序舊操作重送及兩次還原後重送。按獨立預期值核對名稱、版本、父項與封存狀態，再比較全部可攜 bytes；來源與還原使用不同 keys／binding。這是同一 Windows 程序中的獨立目錄，不是手機或獨立程序驗收。

執行方式：在 `prototypes/encrypted_storage` 執行 `dart run bin/category_scale_probe.dart`。原始結果見[分類資料集紀錄](test-results/category-persistence-scale-2026-09-27.json)。目前完整擷取／歷史核對約 935 ms、密碼還原約 4,246 ms、救援還原約 3,040 ms；數據來自同一開發主機，非隔離效能保證。

因共用交易程式被抽取，另執行既有 App 的 5,000 筆新增帳務、5,001 次重送回歸，餘額、全部分頁、完整備份、還原及重開均通過。此輪 payload 為 5,226,566 bytes、20,002 權威列，還原約 8,428 ms；[原始金融回歸紀錄](test-results/category-financial-regression-2026-09-27.json)與分類 metadata 操作分開記錄，不混稱新增交易數。
