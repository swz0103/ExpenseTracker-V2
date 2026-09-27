# 逐項實作進度

使用者於 2026-09-26 授權：逐項實作，每項完成後開下一分支，直到回來驗收或完成所有既定階段。採依賴分支與堆疊 PR，驗證完成後才推進；不自行合併 main。自動接續仍遵守 Android、加密、還原與 migration 等 gate，遇到阻礙先做不受影響的項目。

## 最新接續指示

使用者要求不以試用版為停止點，繼續完整 CORE 直到其回來，屆時再安排實機。每項開發同時回查既有模組並做相關回歸；逐批收斂已涵蓋且驗證的 GitHub 分支，main 不自行合併。自動接續已恢復。[分支收斂紀錄](branch-consolidation.md)保存 exact SHA 與原 PR 對照。

## 分支與交付

- 架構與 SQLite 原型：`docs/architecture-and-implementation-plan`，PR #1；11 項測試及 GitHub CI 已通過，基準提交 `3712cfe781e8ee2725594cb9ee52db8f58fccef3`。原型只驗證 host transaction 機制。
- 金額值型別：`feat/foundation-money`，PR #2，基於 PR #1，提交 `95b6f3a`。10 項新測試與 11 項既有原型測試在 GitHub 通過。Money／Currency、嚴格精度、整數溢位、版本化 JSON、量化與尾差分攤已完成。
- 身份與日期：`feat/foundation-identity-time`，PR #3，基於 PR #2，提交 `bacd122`。UUID v7、帳本／操作身份、嚴格日期與 UTC；17 項值型別與 11 項交易原型測試在 GitHub 通過。
- 帳戶 Domain：`feat/accounts-domain`，PR #4，基於 PR #3，提交 `3354a20`。cash／bank 身份、版本、封存、關閉與重新啟用、零餘額／未結檢查；9 項新測試與所有既有測試在 GitHub 通過。完整 capability 仍待資料層與 UI 接入。
- Ledger 基本入帳：`feat/ledger-posting-domain`，PR #5，基於 PR #4，提交 `8c67e04`。8 項新測試與既有測試在 GitHub 通過。期初／收支／同幣轉帳／fee／分類分攤及重建完成 Domain，仍非完整 Ledger。
- Drift 共用交易原型：`feat/modular-persistence-probe`，PR #6，基於 PR #5，提交 `bfc9ec7`。13 項整合與所有既有測試（合計 58 項）在 GitHub 通過；資料庫仍未加密，僅用 fixture。
- 固定舊版升級原型：`feat/persistence-migration-probe`，PR #7，基於 PR #6，提交 `ee1408a`。v1 → v2、兩處 DDL 回滾及未知版本拒絕在 GitHub 通過，全部回歸共 62 項；仍非完整 migration gate。
- 雙解鎖備份原型：`feat/encrypted-backup-probe`，PR #8，基於 PR #7，提交 `dbc66a2`。9 項新測試與既有測試合計 71 項在 GitHub 通過。AES-256-GCM／Argon2id envelope、密碼與文字救援金鑰獨立解鎖、AAD／長度／KDF 檢查、乾淨子程序 bytes 還原；尚非完整 ledger 還原 gate。
- Ledger 驗證還原原型：`feat/validated-restore-probe`，PR #9，基於 PR #8，提交 `2baa3f3`。固定七表 snapshot、版本／財務／receipt 驗證、保留舊檔的切換與 journal recovery；28 項新測試與既有測試共 99 項在 GitHub 通過。詳見[原型範圍與限制](../prototypes/validated_restore/README.md)。全新子程序的密碼／救援兩條路徑已核對全部列與防重複入帳，但仍非 Android 完整還原 gate。
- 加密儲存接入原型：`feat/encrypted-storage-probe`，PR #10，基於 PR #9，提交 `7cb871e`。沿用 sqlite3 3.6.0 的 SQLCipher 4.19.0 community source；12 項新測試與既有測試合計 111 項在 GitHub 通過。完成加密開檔／重開、錯誤金鑰／損壞拒絕、交易、加密暫存與新金鑰還原、WAL、migration 及切換回滾。[原型紀錄](../prototypes/encrypted_storage/README.md)列明範圍，仍非 Android 安全 gate。
- 獨立程序加密還原：`feat/encrypted-restore-process-probe`，PR #11，基於 PR #10，提交 `14c1903`。10 項新程序案例與既有測試共 121 項在 GitHub 通過。刪除來源 DB 後，僅備份／單一解鎖憑證／新目標 key 即可還原，另一程序核對完整 snapshot 與 replay；中止復原及無效備份保護已測。未把 fixture key 檔案視為正式 secure storage。
- 加密 migration 故障：`feat/encrypted-migration-failure-probe`，基於 PR #11。新增 4 項案例驗證加密 v1 的兩處程序中止、真實引擎 SQLITE_FULL 與未知版本保護；舊資料／schema 完整保留後可再試。另修正 snapshot 用 table_xinfo 檢查 generated／hidden 欄位，新增 1 項拒絕案例。本機加密 26 項、還原 29 項均通過；遠端以 PR checks 為準。頁數限制不冒充實際磁碟滿／斷電。
- Android 地基入口：`feat/android-foundation-probe`，PR #13，基於 PR #12，提交 `b4f2e4d`。新增固定帳務、secure storage、加密重開與雙路還原入口，以及 host CI。ARM64 debug APK 已建置成功並核對 SQLCipher 原生檔與 manifest；6 項新增 host 測試與既有 126 項測試的九個 CI 工作全部通過。平台驗收仍未通過，詳見[Android 原型](../prototypes/android_foundation/README.md)。
- 2026-09-27 確認先前 Android 建置失敗：JNI 相依套件需要 `android-35`，本機缺少該 SDK Platform。已安裝的 SDK 36／36.1 與 Build Tools 35 無法替代它；不得把此結果標為 Android build 通過。
- 2026-09-27 06:15（台北）接續：原有自動核准流程已恢復；重新查驗 PR #12 八項 CI 工作全部成功（提交 `222edeb`，126 項測試）。補齊 SDK Platform 35 revision 2 與 CMake 3.22.1 後，Android debug 建置成功。未購買額度或接受新授權；先前建置失敗保留為診斷歷程。
- 裝置 gate：仍沒有 Android 測試目標；即使 APK 建置通過，也須完成真實 secure storage／加密／還原驗證。未通過前不交付日常使用版本，也不推進依賴此 gate 的 M1 功能。
- 金鑰生命週期契約：`docs/storage-lifecycle-contract`，PR #14，基於 PR #13，提交 `738bc34`；補齊 DB 世代與獨立 key slot、單一目前參照、切換 commit point、啟動復原與 KEY-01～08 驗收。文件連結與差異檢查、全部既有 132 項測試的 CI 均通過；內容仍是工程契約草稿。
- DB／key 配對原型：`feat/storage-generation-probe`，PR #15，基於 PR #14，提交 `b9b5c52`。SQLite 控制紀錄一次提交發布配對、加密 DB 內身份核對、舊組合保留與安裝去重；26 項新 host 測試與所有既有測試（共 158 項）的十個 CI 工作全部通過。詳見[原型範圍](../prototypes/storage_generation/README.md)。fixture key 是明文暫存檔，不能當作平台 secure storage。
- Ledger／世代整合：`feat/ledger-generation-integration`，PR #16，基於 PR #15，提交 `3e0ee54`。明確版本化 schema 3 的本機身份與 format 2 可攜 snapshot；舊備份可匯入，全部權威列／receipt 保留，還原後可新增交易並再備份。23 項新 host 案例包括七處程序中止、新舊格式各兩條乾淨程序還原、未知版本／結構拒絕、加密 binding migration 回滾。本機受影響的既有 98 項回歸及遠端全部 181 項測試的十一個 CI 工作通過。詳見[整合範圍](../prototypes/ledger_generation/README.md)。
- Android 世代 key slot：`feat/android-generation-key-slots`，PR #17，基於 PR #16，提交 `5fcaacf`。新增 Android 安全儲存逐 slot adapter，寫後核對、既有欄位不可覆寫、錯誤去敏；原型雙路還原改用持久配對並核對完整資料與 receipt replay。新增 11 項 host 測試，與既有 6 項合計 17 項通過，靜態分析及更新 ARM64 debug APK 建置／封裝檢查通過；全部 192 項測試的十一個 CI 工作通過。未連接裝置，未宣稱平台測試通過。
- 控制紀錄加密：`feat/storage-control-protection`，PR #18，基於 PR #17，提交 `2d4da42`。明確選用獨立控制 key 與 SQLCipher catalog schema 2，保護去重摘要與參照，核對 store 身份；舊明文模式不自動升級／降級。18 項新增控制案例與 2 項 Ledger 雙路整合案例通過，連同受影響套件共 86 項本機測試及靜態分析通過。Android 已接平台 loader，新 APK 建置及封裝核對通過；全部 212 項測試的十一個 CI 工作通過。[邊界文件](storage-control-protection.md)記錄初始建表中止仍保留並停止，未宣稱自動復原或防整套舊資料回放。
- 排他權等待與取消：`feat/storage-lock-wait`，PR #19，基於 PR #18，提交 `fdde1e8`。預設 10 秒有界等待、零期限嘗試、等待階段取消，已接入 Ledger 讀寫與備份入口；11 項儲存新案例、2 項 Ledger 新案例，連同受影響套件 99 項本機測試及靜態分析通過。Android ARM64 debug APK 建置通過；全部 225 項測試的十一個 CI 工作通過。[契約](storage-lock-wait.md)明列取消不代表取得鎖後的操作回滾。
- 首次控制初始化復原：`feat/storage-catalog-initialization`，PR #20，基於 PR #19，提交 `93bf72c`。只在尚未發布的 stage 接續已知初始化，驗證後才發布空 catalog；既有不完整正式 catalog、未知 schema、缺 key 與資料衝突仍拒絕。新增 17 項儲存與 6 項 Ledger 案例，儲存 72、Ledger 33、Android host 17 項（共 122）及靜態分析通過；新 ARM64 debug APK 建置、SQLCipher／manifest 核對通過。全部 248 項測試的十一個 CI 工作通過。[初始化契約](storage-catalog-initialization.md)保留裝置耐久性與舊損壞資料復原限制。
- Provider 可行性：`docs/provider-feasibility`，PR #21，基於 PR #20，提交 `58afaf0`。核對官方文件及少量公開 GET，整理 Drive drive.file、TWSE／TPEx 盤後、Frankfurter 明確來源 FX 與 Alpha Vantage 日終候選；發現 CBC 查詢日與實際回覆日不同，已明列不可冒充當日匯率。全部 248 項測試的十一個 CI 工作通過；未申請 key／OAuth 或付費，ADR-06 保留未結案。[路線與限制](provider-feasibility.md)。
- 精確匯率地基：`feat/foundation-exact-fx`，PR #22，基於 PR #21，提交 `ca9ea2d`。FxRate 以正 BigInt ratio 保存十進位輸入，反向／交叉匯率不做中間量化；FxObservation 保留來源、實際日期與取得瞬間，預設拒絕過期日期。新增 18 項測試（含 11,552 組精確值誤差界線）與原有 17 項全部通過，靜態分析通過。全部 266 項測試的十一個 CI 工作通過。未接 provider／Ledger schema／UI，不宣稱 M1-03 完成。[計算契約](exact-fx-values.md)。
- 業務套件邊界檢查：`feat/architecture-boundary-checks`，PR #23，基於 PR #22，提交 `b9cc8b3`。新增固定政策與 AST 檢查，拒絕跨業務私有入口、Domain 平台／儲存依賴、循環與相對路徑繞過；15 項正常／負向案例、實際 repository 掃描及靜態分析通過，全部 281 項 host 測試的十二個 CI 工作通過。這是直接依賴 gate，不替代 SQL 資料主責或執行期驗證。[範圍](architecture-boundary-checks.md)。
- 資料演進契約：`docs/data-evolution-contract`，PR #24，基於 PR #23，提交 `3a8de9d`；十二個 CI 工作通過。核對實際 schema／snapshot／module／catalog 版本，明確業務資料主責、停用 UI 資料保留、升級前加密備份、唯一發布點與 EVOL-01～08。揭露現有 envelope 每份新建救援 key 的限制，正式 BackupProfile 延續與升級協調器仍未實作；不把設計當成 gate 通過。[完整契約](data-evolution-contract.md)。
- Android 實機接續：`feat/android-device-validation`，PR #25，基於 PR #24，提交 `cad06c8`。Samsung SM-A5660／Android 16：基本加密、平台 slot、密碼／救援金鑰分別清空 App 後還原及各自新程序重開通過；完整 snapshot／115 餘額／receipt replay 與前後 generation／slot 一致。另四項平台故障案例（缺 key／不可覆寫／兩處 migration 回滾再試）、17 項既有 host 與靜態分析通過。281 項 host 測試的十二個 CI 工作亦通過。詳細結果見[實機紀錄](android-device-validation.md)。
- 持久安全備份：`feat/verified-safety-backup`，PR #26，基於 PR #25，提交 `a137eb0`；294 項 host 測試的十二個 CI 工作通過。來源 schema 3 預檢、exclusive 新檔、flush 後重讀及密碼／救援 key 分別核對完整 snapshot；全程持有生命週期鎖，既有／部分輸出不覆寫。13 項新 host 案例與既有 Ledger 33 項及靜態分析通過；完整產品憑證延續及升級協調仍未完成。[原型範圍](verified-safety-backup.md)。
- 救援憑證沿用：`feat/reusable-recovery-credential`，PR #27，基於 PR #26，提交 `b141392`。Envelope／Ledger 一般與持久安全備份可明確沿用既有救援 key，格式及預設新建行為保留；每份資料 key／salt／nonce 仍獨立。7 項新 envelope、2 項 Ledger 整合，連同既有共 64 項本機測試及靜態分析通過。正式 profile 保存與啟用仍待實作。[契約與範圍](backup-profile-contract.md)。
- 最新使用者指示（2026-09-27）：暫不操作手機；持續到可安裝的最小 M1 試用 APK，且完成大規模測試，或使用者回來。依[本輪計畫](installable-preview-plan.md)調整優先順序。
- P1 工作階段／讀取：`feat/ledger-preview-session`，基於 PR #28。6 項新案例及受影響套件共 172 項本機回歸通過。[接口與限制](ledger-preview-session.md)。PR #27 的 303 項 host 測試及十二個 CI 工作已全部通過。下一項 P2 試用 App／備份設定／UI，再做 P3 大規模及 P4 APK 交付；完整 migration／平台 gate 保留，本輪不操作裝置。

- P2 可輸入的最小試用 App：`feat/installable-ledger-preview`，PR #30，基於 PR #29，提交 `6a4e0d0`。324 項 host 測試的十三個 CI 工作全部通過；獨立 App 身份、設定／鎖定、帳戶／收支／分頁、加密檔案備份與雙路還原、可取回的還原前副本已接入。[範圍](../prototypes/expense_preview/README.md)。
- P3／P4 大規模驗證及 APK 交付：`test/preview-large-scale`，PR #31，基於 PR #30。修正完整還原驗證的重複掃描、加入容量與每列 bytes 保護；補強首次設定發布順序、既有帳本遺失拒絕及空帳本 workspace 一致性。受影響的 131 項本機回歸通過，完整 CI 清單 331 項，遠端以本 PR checks 為準。兩輪已完成的大規模紀錄共 55,000 筆新增／55,011 次重送，全部餘額、分頁、備份完整 bytes、還原與重開通過；每個帳本上限仍為 5,000 筆。最終 0.2.0+2 ARM64 debug APK 建置／簽章／SQLCipher 封裝及 hash 核對通過。[安裝與驗收](installable-preview.md)、[原始測試結果與限制](preview-validation-report.md)。本輪完全未操作裝置；此交付達到最新指示的試用停止點，完整 CI 通過後停止自動推進、等使用者驗收，不擴大後續里程碑或合併 main。
- Categories 業務規則：`feat/category-domain`，基於 PR #33。雙層收入／支出分類、新增／改名／移動／封存／啟用、明確合併與穩定歷史 ID、來源及目標版本檢查已完成；14 項新案例（含一萬筆合併歷史）及既有 15 項架構邊界案例、本機實際依賴掃描與靜態分析通過。回查原 Account 的 immutable／workspace／版本模式與 snapshot 重複掃描經驗：不抽取混合業務基底，採一次驗證／迭代索引解析，移除重複檢查。完整 CI 清單由 331 增至 345 項，以本分支 PR checks 為準。尚無分類資料表、migration、備份 manifest、交易引用驗證或 UI，不能標為 M1-02 完成。[行為與下一步](../packages/categories/README.md)。
- CI 快取回查：`ci/flutter-cache-owner`，PR #35，基於 #34，提交 `4ddc9de`。#34 與 #35 的 345 項／14 個 CI 工作均通過；兩個 Flutter App 原先爭用相同 cache，改為只由 expense_preview 保存。實際 run 確認沒有第二份重複保存；測試與 SDK 版本維持相同。[證據與代價](ci-cache-review.md)。
- Categories 保存與可攜格式：`feat/category-persistence`，基於 PR #35。分類目前狀態／完整變更歷史與金融操作共用 transaction、receipt／Audit，抽取既有去重程式供兩者使用；schema 4／snapshot 3 明確帶 categories=1，拒絕就地升級。新增 23 項案例，本機受影響套件共 171 項通過；完整 CI 清單增為 368 項，以本 PR checks 為準。真實 SQLCipher 的 256 分類／1,024 次變更／1,026 次重送與密碼、救援雙路還原通過；既有 App 的 5,000 筆新增／5,001 次重送與完整還原回歸亦通過。正式升級協調器、schema 4 世代發布、交易引用、統一容量預檢及分類 UI 尚未完成，現有 App 保持 schema 3。[格式與原始測試證據](categories-persistence.md)。

## 尚未完成的 gate

整體階段 0／1 尚未完成，Architecture Baseline 仍 rc1。Android 已有可用測試手機，指定加密／secure storage／雙路乾淨還原與程序重開已有實機證據；完整 migration 故障、OS 重開機、正式備份憑證延續與 provider 路線仍未全部結案。M1／M2／M3 未完成。目前另交付具實際輸入流程的最小試用 App，其新平台流程仍待實機驗收；不可將此有限試用版視為完整日常版本或 gate 全部通過。

詳細順序見[實作計畫](implementation-plan.md)，財務契約見[工程規格](foundation-contracts.md)，驗收案例見[案例清單](foundation-acceptance.md)。
