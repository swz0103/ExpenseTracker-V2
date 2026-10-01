# 升級控制紀錄與原子發布

本批完成[資料演進契約](data-evolution-contract.md)的儲存控制部分：加密 catalog 的版本化升級紀錄、來源核對、同鎖準備與發布、失敗保留和重試。它是後續 Ledger schema 3→4 協調器的依賴；尚未將分類升級接入 App，也不代表完整 EVOL gate 通過。

## 版本與資料主責

`GenerationStore(upgradeAware: true)` 必須搭配 `CatalogProtection`，不能把升級摘要寫進舊明文 fixture。新建控制資料使用 catalog schema **3**；原 schema 1／2 的預設行為保留，舊 reader 拒絕 schema 3。

schema 3 保留 attempts、active、catalog_identity，新增：

- `upgrade_intents`：一次升級的不可變請求，包含 operation ID、來源 generation、**目前資料**摘要、具名 route、來源／目標版本及 backup ID。
- `upgrades`：每次嘗試的目標 generation 與備份密文摘要；連回 intent 及既有 attempt。失敗重試建立新世代，原 aborted attempt、舊檔與 key slot 保留。

這些是本機控制紀錄，不是可攜財務權威資料，不把舊裝置的 generation 或 key slot 匯入新裝置。只有不透明身份、版本與摘要，不保存密碼、救援文字或資料原文。

## 準備、格式變更及發布

整段流程持有既有生命週期排他鎖。先驗證控制資料及目前 payload、處理未發布嘗試，再比對來源 generation 和 live snapshot 摘要。installation fingerprint 只代表最初安裝輸入，不拿它代替日後已新增交易的來源摘要。

可信 payload adapter 的 `prepare` 必須完成已登錄路徑的語意檢查、持久加密安全備份及雙路讀回驗證，再回傳目標資料與備份摘要。準備失敗時不建立新 slot、世代或 catalog 表。不存在已發布 catalog 的升級請求也拒絕，不偷偷建立空帳本。

對已知加密 catalog 2，只有 `prepare` 成功後，才在**同一 SQLite transaction** 新增兩表、設定 catalog 3 並保存第一次 intent／attempt。普通開啟或讀取 catalog 2 不自動升級。DDL／紀錄保存中止時回滾成完整 catalog 2；其後暫存失敗可留下完整 catalog 3 配舊財務世代，新的 reader 可以接續，舊 reader 則拒絕降級。

新世代及 slot 的建立、重開驗證、單一發布點直接共用原安裝流程，沒有複製另一套切換狀態機。`upgrades` 本身不另存一個可能失步的 success 欄位；完成與否由所連 attempt 的 status 決定。將 attempt 改為 committed 與切換 active 的同一 COMMIT，同時決定升級結果與目前資料。

## 重試與衝突

同 ID／同請求重試已提交升級，回傳原結果，跳過準備；即使後來已發布其他世代，也不重新啟用較舊世代。

改來源、route、版本或 backup ID 一律衝突。同一未完成 intent 的目標資料摘要或備份摘要也不能在重試時改變；adapter 必須重新驗證並沿用同一安全備份，不能悄悄覆寫它。若來源資料已變動，先重新評估並建立新的操作身份與備份身份。

一般 install／restore 與 upgrade 共用操作 ID 空間，但有明確種類：已登錄升級 ID 不可當還原操作，既有還原 ID 不可當升級操作，即使目標 bytes 碰巧相同也拒絕。

## 驗證與限制

後續 [Ledger adapter 整合](ledger-category-upgrade.md)已接上真實雙憑證安全備份與 schema 4 帳本，不改以下控制原型 fixture 的原始證據。升級規劃另可透過 `current(requireExistingCatalog: true)` 拒絕隱式初始化缺失來源，沿用鎖內原有防護。

`prototypes/storage_generation/test/upgrade_test.dart` 包含來源比對、準備失敗、相同請求／衝突、同鎖排他、加密要求、未知版本拒絕、舊 reader 拒絕、資料保留與十個獨立程序中止位置：upgradePrepared、upgradeCatalogWriting、upgradeRecording、reserved、keySaved、databaseWriting、staged、validated、publishing、published。發布前保持舊資料，發布後保持新資料；重試僅一個 committed 結果。既有儲存與 Ledger 的還原／安全備份回歸一起驗證。

此批 worker 的 payload 是明列的固定文字 fixture，`prepare` 的備份摘要也只是合成測試值；它驗證**控制機制及呼叫順序**，沒有冒充真的財務安全備份。實際加密 envelope、保存後雙憑證讀回及 schema 4 財務核對，須由下一批 Ledger adapter 接上既有[持久安全備份](verified-safety-backup.md)與[分類快照](categories-persistence.md)能力。`PreparedUpgrade` 是內部可信 adapter 邊界，不是能自行證明備份存在的密碼學證明。

2026-09-27 本機結果：新增 23 項全部通過；與原有 72 項儲存及 54 項 Ledger 回歸合計 149 項，格式、靜態分析與實際套件邊界檢查通過。完整 repository CI 預期為 391 項，以本 PR checks 為準。測試退出程序不等於真實斷電。

沒有 Android／斷電／真實磁碟滿驗收，也未啟用 App 自動升級、正式 BackupProfile 或任意 route 下載執行。既有 App／LedgerStore 預設仍使用 catalog 2、財務 schema 3。
