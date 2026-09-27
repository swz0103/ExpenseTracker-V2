# 資料版本與升級前備份契約

狀態：階段 0 工程契約；描述正式接入所需行為，尚未實作完整升級協調器。既有 host 原型只提供文末明列的部分證據。

追溯：[工程規格第 7 節](foundation-contracts.md#7-migration-與備份契約)、[RC-14](architecture-baseline-v1.0-rc1.md#rc-14)、[RC-22](architecture-baseline-v1.0-rc1.md#rc-22)、[Full Vision Q118](full-vision-baseline.md#q118)、[Q119](full-vision-baseline.md#q119)、[Q120](full-vision-baseline.md#q120)。延續按業務拆分、共用 SQLite transaction，以及密碼／文字救援兩條還原路徑，不引入通用 migration 工作流引擎。

## 1. 每種版本各自負責什麼

- App build／套件版本：辨識程式成品，不用來猜 DB 是否相容。
- 財務 DB schema：同一 SQLite 檔案的實際整體結構。只由 persistence 協調升級，業務不能各自開檔自動改表。
- Module data version：某業務擁有的持久資料語意與結構版本；同一發布必須列出完整、經測試的版本組合。
- Snapshot format：可攜資料的結構與型別，包括金額字串、權威資料、必要去重紀錄；不是 DB 檔案複製格式。
- Envelope version：加密容器、KDF 與解鎖欄位的規格，與 snapshot 分開判斷；成功解密不代表內容相容。
- Catalog／本機身份版本：描述目前世代與 key slot 的本機配對；不等同財務資料版本，不攜帶來源裝置的 key。

對既有資料，這些數字沒有「取最大的就能開」的規則。必須比對已登錄的完整來源組合、目標組合與遷移路徑；未知 module、欄位、view、trigger 或版本停止處理，不以猜測的空值補齊。

## 2. 現有原型的精確對照

[ProbeDatabase](../prototypes/modular_persistence/lib/database.dart) 有固定 schema 1 fixture；schema 2 新增 events.source_context 與帳戶查詢索引；schema 3 增加 storage_identity，要求可信呼叫者提供本機配對。現有 1→2、1→3、2→3 只代表指定原型路徑。

[SnapshotCodec](../prototypes/validated_restore/lib/snapshot.dart) 的 format 1 對應 schema 2，固定 modules 為 accounts=1、ledger=2、operations=1；format 2 對應 schema 3，另加 local_identity=1。兩者攜帶相同七張帳務權威表：accounts、events、legs、openings、allocations、receipts、audit。

format 2 驗證來源 storage_identity，但不輸出來源世代／slot 列；目標必須新建身份。`local_identity=1` 表示已知來源結構，不授權還原端沿用來源 key。generation-aware codec 可讀 format 1／2，legacy codec 不接受 format 2。

後續[分類保存](categories-persistence.md)新增明確選用的 schema 4／snapshot format 3；沿用原七張表及本機身份，新增 categories、category_changes 權威表與 categories=1 manifest。category-aware codec 可讀已知 format 1／2／3；舊格式的新增分類表為空，既有權威資料保留。schema 4 只建立在新 stage，拒絕就地升級；現有 App／LedgerStore 仍是 schema 3，完整發布協調器尚未接入。

控制 catalog 的 schema 1 是明文 fixture，schema 2 是獨立 key 的加密模式；這兩個數字與財務 schema 1／2 毫無大小關係。目前沒有 catalog 明文→加密的自動升級，不能在正式接入時順便改寫。

後續[升級控制紀錄](storage-upgrade-receipts.md)新增明確選用的加密 catalog 3，保存升級 intent 與每次目標／備份摘要。已知 catalog 2 僅在可信 adapter 準備完成後，於同一 transaction 升為 3 並保存第一次嘗試；普通開檔不自動改表。這是控制機制，尚未完成 Ledger 3→4 的財務備份／轉換接線，也不改 envelope 規格。

這些均為原型資料協定，未標定為首個正式產品 schema。轉入正式版本時須留下明確的 fixture 匯入或拒絕路徑，不把 `user_version` 改號當成完成遷移。

## 3. 按業務主責保存與新增資料

目前 Accounts 擁有 accounts；Ledger 擁有 events、legs、openings、allocations；Categories 在明確啟用的 schema 4 擁有 categories、category_changes；共用操作紀錄擁有 receipts、audit；Persistence／Security 擁有本機配對與 catalog。各業務提供自己的 schema 片段與 validator，persistence 組合一次遷移並掌握 commit，不反向掌管財務公式。

後續新增 Tags／Merchants，應新增其資料主責及版本，Ledger 透過 workspace-scoped 公開 ID 連結。新增 Card 時，帳單／應繳安排由 Card 保存，資金 legs 仍歸 Ledger；新增 Investment 時，lot／股數／成本由 Investment 保存，不能只備份現金 legs。這些未建立的模組現在不預建空表或虛構版本號。

每個新增持久實體要同時列出：主責模組、權威或可重建、本機或可攜、workspace 範圍、跨模組引用、backup 欄位、來源／目標版本與 fixture。未列入備份的權威表必須讓備份失敗，不能默默遺漏。

Capability 的 UI 開關與資料相容性分開。關閉投資 UI 仍需能讀、保留、遷移和備份既有投資權威資料；缺少能理解該資料版本的模組時拒絕寫入／還原。OPTIONAL 資源可重新下載，但不能把使用者的投資 lot、OCR 確認後的交易或匯入 receipts 歸為可丟棄資源。

## 4. 升級入口與排他範圍

正式升級在業務 session 開放前，由唯一 StorageCoordinator 執行。先取得生命週期排他權，處理未結切換，再用不觸發 DDL 的檢查入口判斷來源身份、schema 與版本組合。不得先建立會自動 migration 的 Drift 連線，再補做備份。

升級期間停止所有帳務、jobs、匯入與報表 DB 工作，等待已開 session 釋放；備份擷取到發布期間保持同一排他範圍。若未來為大型資料釋放鎖，必須加入經驗證的來源修訂核對／重試策略，不能直接沿用過期 snapshot。

尚未取得排他權時可依[等待契約](storage-lock-wait.md)取消／逾時；取得後不得把程序已提交但回覆遺失說成「取消成功」。遇到不認識的來源版本，在任何 migration DDL 或新正式參照寫入前停止。

## 5. 升級前安全備份

第一個正式版本對每次持久 schema／資料語意變更均先建立已驗證的加密安全備份；暫不設「小升級所以可跳過」例外。單純 cache／projection 重建若確實不改權威資料，另走可重建資料契約。

1. 由理解來源版本的 reader 擷取同一時點的完整權威 snapshot，保存 workspace、module versions、歷史、Audit 及去重資料。不能先升級來源再稱它為升級前備份。
2. 使用已驗證 envelope 封裝，持久保存到 App 私有備份區；檔名由本機操作身份導出，不接受 snapshot 指定路徑，不產生明文落地暫存檔。
3. 關閉並重讀實際保存的 envelope，驗證密文完整性；兩種憑證均可用時，各自解鎖並核對來源 snapshot。只有記憶體中產生成功或回傳檔名，不算安全備份完成。
4. 將備份身份、來源世代、來源／目標版本、內容摘要及 upgrade operation ID 記入受保護的升級紀錄。摘要不是加密驗證的替代，內容或解鎖秘密不得寫入日誌。
5. 備份寫入、重讀、驗證或必要憑證取得失敗，停止升級，原正式 DB／key／參照不變。沒有空間不能藉刪除唯一備份或舊世代繼續。

目前 EnvelopeCodec 每次 create 會回傳該備份的 recovery key；不能假設過去抄下的另一份救援文字能解鎖新檔。正式 BackupProfile 如何延續使用者已保存的救援憑證，仍須另實作與驗證。第一個限定 host 升級原型只能由測試呼叫者明確提供密碼、持有新回傳的救援 key，並驗證兩條路徑；不宣稱已完成自動、無互動的產品升級。

如果正式自動升級尚無可用且已驗證的解鎖配置，必須在修改資料前要求使用者完成備份準備；不能改存明文或只保留裝置 key 卻宣稱可攜備份。這是未來產品流程要求，本文件不觸發目前使用者的密碼／授權操作。

## 6. 暫存升級與唯一發布點

後續已補[明確沿用救援憑證](backup-profile-contract.md)的底層能力；未提供參數時仍維持每份新 key。這不代表正式 BackupProfile 已持久保存，也不能自動略過上一節的備份準備及雙路驗證。

採用既定[世代切換協定](storage-lifecycle-contract.md)：保留原世代與 key，建立新 slot 及目標加密世代，在目標執行已登錄遷移。來源可透過已驗證邏輯轉換匯入，或經驗證的 SQLite 相容方式建立一致副本；不得直接複製仍使用中的 DB 主檔而漏掉 WAL／journal。首個限定原型選已知 snapshot 轉換路徑。

跨模組 schema／資料轉換與目標 manifest 更新在同一 SQLite transaction。各模組先核對共同來源版本，再依固定順序轉換；任一步失敗整個目標回滾，不各自 commit。外部網路／下載不在此 transaction 內，也不能決定歷史財務數字。

目標完成後驗證完整性、引用、權威資料及財務不變條件，再重建必要 projection。關閉目標、重新取得 key 並開檔核對身份與版本。升級不能重算已保存交易的歷史匯率／四捨五入結果；每 workspace／account／currency 的餘額與有效財務語意保持一致，必要語意調整須有明確轉換證據。

以加密 catalog 的單一 transaction 一起提交 upgrade 結果與目前 generation／slot 參照，作為唯一發布點。catalog 需要新操作類型或格式時另做版本化；現有 restore attempt 不可直接冒充已支援 upgrade。財務 schema 升級、catalog 格式升級及 envelope 規格更新分開驗證，不能在一次未驗證開檔中連續猜測升級。

發布前中止：只在確定仍指向舊世代且身份一致時恢復舊可用組合，未發布目標保留待處理。發布後中止：核對新組合並回報既有升級結果，不自動回退到舊世代丟棄後續寫入。參照／紀錄不一致則保留並停止；修復不得依檔案時間猜版本。

upgrade operation ID 只識別一次升級，與財務 receipts 分開。相同 ID／相同來源身份及目標版本重試取得既有結果；不同輸入拒絕。使用者後來更新 App 或選擇另一個來源備份時是新操作，不重新啟用先前退役世代。

## 7. 必須補上的故障驗收

以下補充 [DATA-01 與 BACKUP-01～04](foundation-acceptance.md#資料演進與保護)，目前均未宣稱完整通過。

- **EVOL-01 前置不寫入**：未知 schema／module version、相容路徑缺漏、錯 key 或未釋放 session 時，不執行 migration DDL、不改目前參照。
- **EVOL-02 真正升級前備份**：在第一處 DDL 前，已持久保存的 envelope 可被新程序分別以密碼／救援 key 解鎖；內容是舊 schema 對應的完整來源資料。
- **EVOL-03 備份故障**：在保存、重讀、驗證及空間不足處注入失敗；原 DB 版本、權威列與 key 保持，不能出現成功的 upgrade receipt。
- **EVOL-04 多模組全有全無**：兩個參與模組每一轉換邊界中止；未發布目標不可被正常業務讀寫，重試不留下混合版本。
- **EVOL-05 發布邊界與去重**：發布前／後子程序中止，各自回到完整舊或已提交新組合；相同 ID 重試不重作財務轉換，不重複發布。
- **EVOL-06 資料守恆**：包括歷史、退款／反轉、跨幣原額、receipt、停用 UI 模組的固定來源 fixture；升級後完整權威資料依明列規則相等，餘額與語意一致。未實作模組不以空 fixture 宣稱通過。
- **EVOL-07 乾淨還原與版本拒絕**：僅升級前 envelope／其中一種憑證可在新目標恢復；舊 App 遇新 schema 拒絕寫入，不能降級覆寫。
- **EVOL-08 保留及平台**：目前、未結和唯一可恢復組合不可清理；另驗證 Android 重啟、secure storage 及真實容量故障，host 中止不代表裝置斷電通過。

## 8. 實作順序與現有證據

2026-09-27 接續：[Ledger 分類升級](ledger-category-upgrade.md)已串接已知 schema 3 → 4 的來源、真實安全備份與 catalog 3 升級結果；該頁明列本機故障／還原驗證及未開放的 App gate。不將此單一路徑延伸宣稱為全部 EVOL 或通用模組升級完成。

現有原型已驗證固定 1→2／3 transaction 回滾、指定程序中止、SQLITE_FULL、雙憑證乾淨 host 還原，以及 generation 發布去重；目前另串接限定 3→4 的「來源預檢→安全備份→目標升級→發布」。進度見[逐項紀錄](work-progress.md)。尚無通用 module migration registry、正式 BackupProfile 或完整 Android 升級 gate。

既定的分階段順序是先以已知財務 fixture 補來源預檢、持久安全備份與雙路新程序還原，再接目標升級及版本化 upgrade receipt；此限定路徑已接上。正式模組逐功能接入時仍須擴增 manifest／fixture，不先建立未使用的動態插件管理或任意遷移腳本下載能力。
