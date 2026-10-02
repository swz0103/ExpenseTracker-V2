# 外部程式碼稽核回應與改善計畫（2026-10-02）

## 審查基準與判讀方式

外部報告以 `main` 的 `25ae084d32904292c6320d0462208d72076c526e` 為固定基準。本回應逐頁核對報告所列程式路徑，再以目前 `main` 判斷；報告中的建議不是執行指令，只有可由現行程式、測試或裝置證據支持的項目才納入工作。

目前 `main` 已多出 `cf00196`：Ledger session 會沿用 generation recovery 已檢查的 snapshot，避免開啟後第一次寫入立刻再次掃描整個 SQLCipher 資料庫。這只部分改善 R06，不提高 5,000 events、50,000 authority rows 或 16 MiB portable payload 上限。

## 發現核對

### R01 P1：投資交易拒絕後缺少安全恢復出口 — 已完成第一批修正

買入、賣出、股息與拆股現在都保留原本的相同 intent 重試，並新增明確的「核對結果或捨棄」出口。核對會讀取整個 workspace 的權威投資事實，而不是只看原帳戶／標的，避免身分碰撞被誤判為未提交。

現行保護：

- 使用者必須先通過二次確認；畫面不提供未核對的直接刪除。
- 若 workspace 內找到完全相同的 operation／event／payload，將 intent 標成 committed，不重新入帳。
- 若找到多筆、識別碰撞或內容不符，核對 fail closed，intent 原樣保留。
- 只有權威事實完全不存在時才刪除 vault intent，並在刪除後 read-back；刪除失敗時 intent 保留。
- 結果未知仍可沿用相同 operation ID／event ID 重試，不建立新交易。

主機驗證已通過買入、賣出、股息、拆股的提交後回覆遺失與重啟核對、確定拒絕後安全捨棄、vault 刪除失敗保留、加密備份雙憑證還原，以及畫面二次確認。詳細證據見 [R01 主機驗證](../test-results/2026-10-02/investment-intent-resolution-host-2026-10-02.md)。實機 process death 仍列入 R08 候選版 gate，不以本批主機測試取代。

### R02 P1：自動備份缺少獨立執行入口 — 已完成前景 runner

App 現在有獨立於雲端備份頁的 application runner。冷啟動在帳本仍鎖定時只 reconcile／續傳已經加密並持久化的 artifact；密碼、救援文字與未加密帳本內容不會交給這條路徑。成功解鎖（密碼、裝置解鎖或 PIN）後才檢查到期排程、建立新的雙憑證驗證快照並執行 bounded upload pump。

現行保護與限制：

- 冷啟動續傳與解鎖後排程共用序列化 application runner，不能同時操作同一工作庫。
- 建立快照需要帳本已安全解鎖；沒有新增背景主密碼落地或繞過鎖定。
- 工作 schema 3 分開保存 `scheduledFor`、實際 `capturedAt` 與工作 `updatedAt`；runtime 顯示最後成功上傳時間，排程庫保存 `nextDueAt`。
- 畫面明示逾期、下次預定時間，以及「關閉 App 時不建立新快照；下次開啟並解鎖後補做」。
- 失敗 provider 不阻止其他 provider 維護；既有持久失敗仍在雲端備份頁顯示並可重新連結。
- 本批不是 Android OS 背景喚醒：App 完全關閉時不保證準時建立新快照。後續若接 worker，只能處理已加密 artifact，不能持有帳本密碼。

主機已通過雲端核心 41/41、App runner／畫面／首頁接線／engine 整合 12/12、架構 22/22與靜態分析。詳見 [R02 主機驗證](../test-results/2026-10-02/cloud-backup-application-runner-host-2026-10-02.md)。

### R09 P1：雲端清理沒有保護預計保留集合 — 已完成第一批修正

原本 apply 只重新核對 delete 項目；預覽後若 keep 被另一裝置移除，舊 delete 仍可能通過。現行修正：

- apply 先驗證 plan provider、keep 非空、所有 object ID 唯一且 keep/delete 不重疊。
- 每一個清理動作前後都重新讀取完整 history，核對所有 keep 與剩餘 delete 的 metadata。
- keep 消失、內容改變或遠端數量不足時立即 fail closed，不再繼續下一個清理。
- Google Drive 不再永久 DELETE；改用可復原的 trashed 狀態，之後 GET read-back 核對 object 與 metadata。
- 既有已 trashed 且 metadata 相同的重試視為冪等完成。

這仍不是跨多物件的伺服器原子交易；真正同時由兩個裝置清理時，Drive trash 的可恢復性是最後保護。正式實機需再做兩裝置／兩帳本並行演練。

### R08 P1：缺少完整 App 的 Android 候選版裝置驗收 — 成立，需外部條件

host CI、ARM64 debug build 與手動簽署 workflow 都是正面證據，但不能替代正式 APK/AAB 的乾淨安裝、升級、還原與平台生命週期。需要 Android 實機、正式 OAuth client、正式 signing secrets 與候選產物才能關閉。

### R04 P1：5,000 事件容量線不適合長期正式版 — 基線與第一項查詢修正完成

限制是刻意 fail-closed，而不是隱藏漏洞；但正式長期記帳不能只靠備份封存舊帳。現行 schema 24 已建立 100／1,000／5,000 筆分階段工具與基線。基線找出 keyset 時間軸缺少複合索引；補上可重建的 `(workspace,business_date DESC,id DESC)` 後，5,000 筆全分頁從 20,540 ms 降為 2,361 ms，首頁首批從 160 ms 降為 9 ms，持久層完整 111/111 及同 schema 補建測試通過。

這不提高容量：5,000 筆已有 5,206,422-byte payload 與 20,002 權威列，備份／還原仍約 25／46 秒。20,000 筆在現行 5,000／50,000／16 MiB gate 下無法成為合法帳本。下一個儲存里程碑必須先完成 bounded chunk manifest、authenticated streaming、全新 generation 還原與舊格式唯讀匯入，之後才可建立 20k gate。詳見[容量演進計畫](capacity-evolution-plan.md)與[主機證據](../test-results/2026-10-02/current-schema-capacity-profile-windows-2026-10-02.json)。

### R03 P2：帳戶活動從首頁已載入 30 筆篩選 — 已完成第一批修正

帳戶明細現在直接以 account ID 查詢 Ledger 權威資料，不再重用首頁的 30 筆快取。查詢使用穩定 keyset 游標；來源帳戶及 transfer destination 的腿都會納入，轉入列顯示實際 received 金額。

獨立 sheet 已分開首次 loading、後續 loading、error／retry、真正 empty 與 hasMore；request epoch、mounted 與帳本解鎖狀態會阻止關閉或鎖定後的晚到結果寫回。結果若含無關帳戶或重複 keyset row 會 fail closed，既有分類摘要也保持顯示。主機已通過獨立 30+3 分頁、無重疊、轉入腿與畫面 31 筆分頁入口，另有活動／搜尋關聯回歸，共 7/7；架構 22/22 與靜態分析通過。詳見 [R03 主機驗證](../test-results/2026-10-02/account-activity-pagination-host-2026-10-02.md)。

### R05 P2：系統返回未共用安全離頁流程 — 已完成第一批修正

root 現在使用 `PopScope` 接管系統返回，內頁與「返回帳本」按鈕共用同一個安全離頁命令。最上層 dialog／bottom sheet 仍由 Navigator 先關閉，不會同時觸發 root 退出；內頁返回會等待在途草稿寫入，寫入失敗時重試並留在原頁，匯入／匯出暫存也沿用既有 discard 流程。

首頁是解鎖狀態唯一會要求離開 App 的頁面；離開前先等待草稿尾端、鎖定 SQLCipher session、關閉敏感 popup，確認 lock barrier 完成後才呼叫平台退出。upgrade 頁的返回只鎖定，不嘗試繞過升級；尚未解鎖的 loading／setup／recovery／locked／blocked 才可直接退出。主機新增系統返回草稿保存、保存失敗阻擋、modal 優先及首頁先鎖後退出案例，與既有草稿／背景鎖定共 11/11；架構 22/22 與靜態分析通過。詳見 [R05 主機驗證](../test-results/2026-10-02/safe-back-navigation-host-2026-10-02.md)。Android predictive back／實體鍵仍需 R08 真機驗收。

### R10 P2：雲端待傳工作未綁定穩定帳號 principal — 已完成安全預設

雲端工作 schema 4 現在把 provider 與穩定 principal 一起保存；Google Drive 使用 Google Sign-In account ID，只保存識別值，不保存 token。排程、冷啟動續傳與人工重試都會先核對目前 principal；重新授權同一帳號可沿用原 backup ID 與 reservation，不同帳號則在任何檔案讀取或 provider 呼叫前以 authentication-required 終止，工作與加密 artifact 原樣保留。

schema 1–3 的既有工作升級後刻意保持 principal 未綁定，不會把歷史工作默默歸給下一個登入帳號。主機已通過雲端核心 43/43，其中包含不同帳號零次上傳、切回原帳號續傳及 schema 3 不得被接管；App 雲端 runner／畫面／入口 11/11、架構 22/22及兩個套件靜態分析通過。詳見 [R10 主機驗證](../test-results/2026-10-02/cloud-backup-principal-binding-host-2026-10-02.md)。

目前沒有提供「把舊工作改綁到另一帳號」的自動捷徑。若產品要支援遷移，下一批必須加入顯示來源／目前帳號、使用者明確確認、清除舊 remote reservation 並重新建立目的地的受測流程；在那之前安全行為是保持暫停。

### R12 P2：XIRR 取樣可能漏掉根，卻把結果呈現為唯一 — 已完成保守修正

XIRR 現在先計算依日期合併後的現金流符號變化。只有恰好一次符號變化時，才利用廣義 Descartes 規則把「至多一個實根」作為唯一性依據，並在既有有界 log-rate 搜尋找到根後顯示數值。多次符號變化若實際隔離到多根，回報多解；若固定網格只看到一根或完全沒看到，也回報「可能多解、無法證明唯一」，不再輸出任選的年化報酬率。

投資套件已加入三根、彼此接近而落在同一網格間隔的根對、偶數重根、搜尋上界根、同日／單一符號及極端範圍案例。套件完整 69/69、XIRR 11/11、投資績效／行情畫面 12/12、架構 22/22及相關靜態分析通過。詳見 [R12 主機驗證](../test-results/2026-10-02/xirr-uniqueness-host-2026-10-02.md)。

這是保守產品語意，不是完整多根求解器：多次符號變化但其實只有一根的資料也可能被標成「無法證明唯一」。若未來要列出所有解，仍需另建具可論證區間涵蓋的 root isolation，而不是只增加取樣數。

### R11 P2：帳戶生命週期 domain 尚未完整接 App — 已完成第一批修正

正式設定現在有「帳戶管理」入口，可操作改名、資產摘要納入／排除、封存、重新啟用與關閉。畫面不提供幣別或開戶日改寫；封存確認明示歷史保留且不會釋放 32 個帳戶上限。已關閉帳戶顯示關閉日、原因與接手帳戶，仍可重新啟用。

每個命令都使用固定 operation ID、expected version 與同一 SQLCipher transaction。重送相同輸入冪等，operation 內容碰撞或 stale version fail closed。關閉在同一交易讀取權威 Ledger 餘額與尚未解決的信用卡授權；非零餘額、待入帳授權、無效日期或接手帳戶狀態不符都拒絕，帳戶保持原狀。receipt／audit、容量模型及 portable snapshot 白名單已加入新命令；多次關閉只以最新 closure metadata 對照，但所有歷史 receipt 仍保留並驗證格式與版本。

主機已通過生命週期 session 2/2、正式畫面與帳戶／資產報表 4/4、validated restore 131/131、架構 22/22及相關靜態分析。詳見 [R11 主機驗證](../test-results/2026-10-02/account-lifecycle-host-2026-10-02.md)。真機、跨裝置版本衝突與候選版還原仍列 R08 gate。

### R06 P2：前景資料庫與重複投影缺少裝置量測 — host 分段基線與時間軸修正完成

`cf00196` 已移除 recovery 後第一次容量 admission 的重複 snapshot scan。2026-10-02 Windows host 的現行 schema 24 單帳本基準通過全部一致性檢查；加入時間軸索引後 5,000 筆結果為：

- 5,000 筆累積寫入：270,543 ms。
- 首頁首批：9 ms；完整 keyset 分頁：2,361 ms（基線 20,540 ms）。
- 月報：881 ms。
- 5,206,422-byte plaintext payload 的加密備份：24,791 ms。
- 乾淨密碼還原：46,369 ms；重新解鎖：10,360 ms。
- 完整流程：373,263 ms。

這是 Windows host 單次樣本，不是 Android p95。常駐記憶體只是整個 Dart 程序當下讀值，沒有當成 peak 或 App 專屬記憶體聲明。它證明索引可修正讀取成本，也證明全量備份／還原與容量格式仍不能靠調高常數解決；Android profile、UI frame 與 peak RSS 仍屬 R08／C4 gate。

### R07 P2：大型 shared-library UI 狀態提高維護成本 — 成立

這是維護與回歸隔離風險，不是單靠行數可證明的功能錯誤。順序應是先固定行為測試，再依使用案例抽出記帳、還原、投資、信用卡 controller/service 與 lock/busy/epoch 狀態；避免一次全面改寫 UI。

## 執行順序

### 第一階段：資料不可恢復風險

1. R09 清理保留競態與 recoverable trash。
2. R01 投資 intent 核對、完成與安全捨棄。
3. R02 解鎖／啟動後的獨立備份 runner，之後才接 Android 已加密工作。

退出條件：所有失敗注入都有可恢復結果；被關閉的功能文案與實際行為一致；沒有清理路徑能默默留下零份遠端備份。

### 第二階段：使用者可直接碰到的缺口

1. R03 帳戶活動獨立查詢與分頁（已完成第一批修正）。
2. R05 Android Back 共用安全離頁（已完成第一批修正）。
3. R11 帳戶 rename/archive/close/reactivate/summary 設定（已完成第一批修正）。

退出條件：活動不漏筆、不混頁；返回不能繞過草稿或鎖定；domain 已有能力都有可操作且受版本保護的 App 入口。

### 第三階段：身分與數學語意

1. R10 穩定 principal 綁定與不同帳號安全暫停已完成；明確帳號遷移 UI 尚待補齊。
2. R12 XIRR 唯一性證明與保守呈現已完成；完整列舉所有根不在本批範圍。

退出條件：換帳號不會默默改變上傳目的地；XIRR 在多根資料上不再宣稱唯一答案。

### 第四階段：容量、架構與候選版

1. R04/R06 建立 100、1,000、5,000、20,000 與設計目標容量的分階段 host／Android profile 基準。
2. 設計追加事件、分塊 snapshot、串流備份與升級／回退策略，再決定正式上限。
3. R07 以已固定的使用案例測試逐步抽 controller/service。
4. R08 以同一正式 SHA 完成簽署、最低與現行 API 實機、乾淨安裝、前版升級、雙憑證還原、通知、SAF、process death 與背景工作。

退出條件：正式候選產物 hash、簽章指紋、commit SHA、CI、裝置矩陣與還原證據可互相對應；任何失敗都能阻止發布。

## 不採取的捷徑

- 不直接把 5,000 改成 100,000。
- 不在背景保存主密碼或繞過解鎖來建立新備份。
- 不讓「捨棄 intent」刪除結果未知的交易身分。
- 不把 Google Drive 永久 DELETE 當成一般保留策略。
- 不把多解 XIRR 任選一根後標成唯一報酬率。
- 不把 host CI、debug APK 或模擬器結果當成正式裝置驗收。
- 不為了檔案變小而一次全面改寫 UI 狀態。

## 需要使用者或外部環境的最後 gate

- Google Cloud OAuth project、Android package、簽章 SHA、Web client ID 與測試帳號。
- 正式 Android application ID、keystore 與 GitHub protected environment secrets。
- 至少一台最低支援 API 與一台現行 API／OEM 的 Android 實機。
- 若要背景 1–5 分鐘價格提醒 SLA，需正式行情授權、後端排程與推播；Android WorkManager 不提供此保證。
- 若要上架 Play，還需 Play Console、商店素材、隱私政策、資料安全表單與正式發布權限。
