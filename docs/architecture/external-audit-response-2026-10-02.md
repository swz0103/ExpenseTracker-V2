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

### R02 P1：自動備份缺少獨立執行入口 — 成立

schedule、retry、持久工作與 runner 已存在，但目前 `maintainRuntime` 仍由雲端備份頁的 reload、建立與重新連結流程觸發。使用者只停留首頁、跨過 dueAt 或重新開啟 App 時，不保證自動建立並上傳快照。

改善原則：

- 先在成功解鎖及 App 冷啟動恢復後，由單一 application runner 檢查到期排程與既有待傳工作。
- 建立快照需要帳本已安全解鎖；不新增背景主密碼落地或繞過鎖定。
- 已加密且已持久化的待傳 artifact，才可交給後續 Android background worker。
- 保存 `scheduledFor`、`capturedAt`、最後成功時間、下一次到期時間與逾期狀態。
- 若第一版只能「開啟並解鎖後補做」，UI 與文件必須明說，不能承諾關閉 App 仍準時建立新備份。

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

### R04 P1：5,000 事件容量線不適合長期正式版 — 成立

限制是刻意 fail-closed，而不是隱藏漏洞；但正式長期記帳不能只靠備份封存舊帳。必須先完成分階段量測、追加寫入與分塊／串流備份設計，才可提高上限。不能只修改常數。

### R03 P2：帳戶活動從首頁已載入 30 筆篩選 — 成立

帳戶頁應改以 account ID 獨立查詢及 keyset 分頁，並包含 transfer destination。需要分離 loading、error、真正 empty 與 hasMore，且以 request epoch 防止跨帳戶切換或鎖定後的晚到結果混頁。

### R05 P2：系統返回未共用安全離頁流程 — 成立

畫面內返回命令會處理草稿、匯入／匯出、清理與鎖定，但 Android Back 仍可落到單一 root 的預設行為。應由 PopScope 或 router 共用同一安全離頁命令；modal 先關閉、草稿保存失敗阻止離頁，只有首頁才離開 App。

### R10 P2：雲端待傳工作未綁定穩定帳號 principal — 成立

工作目前以 provider ID 分類，換 Google 帳號後可能用新 token 繼續舊目的地工作。需保存 provider + Google stable subject ID，重新授權同帳號可續跑；不同帳號預設暫停，只有使用者明確選擇後才重建 reservation／目的地。

### R12 P2：XIRR 取樣可能漏掉根，卻把結果呈現為唯一 — 成立

固定 log-rate 網格無法證明所有根都被隔離。短期應在找到多根或無法證明唯一時回報「可能多解／不可用」，並加入報告提供的三根反例、近根、重根、邊界根與同日抵銷。若未來要完整支援多解，需要具可論證區間涵蓋的 root isolation，而不是單純增加取樣數。

### R11 P2：帳戶生命週期 domain 尚未完整接 App — 成立

domain 已有 rename、archive、close、reactivate 與摘要設定規則，但 App 主要只有建立與查閱。需補 service、持久化交易、UI 與版本衝突；有交易的帳戶不能任意改幣別／起始日，非零餘額或未結項目不能關閉，封存不能被描述成釋放 32 帳戶容量。

### R06 P2：前景資料庫與重複投影缺少裝置量測 — 成立，部分改善

`cf00196` 已移除 recovery 後第一次容量 admission 的重複 snapshot scan。2026-10-02 Windows host 的單帳本 5,000 筆 App engine 基準通過全部一致性檢查：

- 5,000 新交易及 5,000 次冪等重送：189,590 ms。
- 完整 keyset 分頁：21,713 ms。
- 5,226,616-byte plaintext payload 的加密備份：24,855 ms。
- 乾淨密碼還原：36,495 ms。
- 重新解鎖：8,607 ms。
- 完整流程：327,995 ms。

這是 Windows host 單次樣本，不是 Android p95。它證明資料正確，也證明不能直接把上限改成 100,000。後續需分離量測 SQLCipher transaction、UI isolate、首頁投影、報表、備份、還原與記憶體峰值。

### R07 P2：大型 shared-library UI 狀態提高維護成本 — 成立

這是維護與回歸隔離風險，不是單靠行數可證明的功能錯誤。順序應是先固定行為測試，再依使用案例抽出記帳、還原、投資、信用卡 controller/service 與 lock/busy/epoch 狀態；避免一次全面改寫 UI。

## 執行順序

### 第一階段：資料不可恢復風險

1. R09 清理保留競態與 recoverable trash。
2. R01 投資 intent 核對、完成與安全捨棄。
3. R02 解鎖／啟動後的獨立備份 runner，之後才接 Android 已加密工作。

退出條件：所有失敗注入都有可恢復結果；被關閉的功能文案與實際行為一致；沒有清理路徑能默默留下零份遠端備份。

### 第二階段：使用者可直接碰到的缺口

1. R03 帳戶活動獨立查詢與分頁。
2. R05 Android Back 共用安全離頁。
3. R11 帳戶 rename/archive/close/reactivate/summary 設定。

退出條件：活動不漏筆、不混頁；返回不能繞過草稿或鎖定；domain 已有能力都有可操作且受版本保護的 App 入口。

### 第三階段：身分與數學語意

1. R10 雲端工作與穩定 principal 綁定、帳號切換遷移。
2. R12 XIRR 多根辨識與保守呈現。

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
