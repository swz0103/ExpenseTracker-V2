# 逐項實作進度

使用者於 2026-09-26 授權：逐項實作，每項完成後開下一分支，直到回來驗收或完成所有既定階段。採依賴分支與堆疊 PR，驗證完成後才推進；不自行合併 main。自動接續仍遵守 Android、加密、還原與 migration 等 gate，遇到阻礙先做不受影響的項目。

## 最新接續指示

2026-09-27 使用者明確要求開始動工、打開排程並邊做邊回報。已恢復原有排程為啟用，保留當時實際設定的每 20 分鐘接續；本輪直接開發，不等待下一次排程。不操作手機、不啟動 Actions、不合併 main，仍依 CORE 範圍逐項完成。

2026-09-27 前次核對上傳與隔離：已唯讀確認 V2 為獨立私人 repository、origin 只指向 V2，舊版與 V2 的 Android 身份不同；同步遠端後，當時最新功能 `1424c58`／PR #43 及所有本機分支提交皆已被遠端涵蓋。完整規則見[交付與效率文件](github-delivery-policy.md)。前次讀到排程為暫停、每 50 分鐘，當時未自行更動；本輪已依最新明確授權恢復，並保留最新設定的每 20 分鐘，以上方紀錄為準。

使用者要求不以試用版為停止點，繼續完整 CORE 直到其回來，屆時再安排實機。每項開發同時回查既有模組並做相關回歸；逐批收斂已涵蓋且驗證的 GitHub 分支，main 不自行合併。自動接續已恢復。[分支收斂紀錄](branch-consolidation.md)保存 exact SHA 與原 PR 對照。

## 分支與交付

2026-09-27 商家／別名接續開發中：已從 [Tag PR #46](https://github.com/swz0103/ExpenseTracker-V2/pull/46)（`10a49ba7ad67ee7d0dbca2a4c0e8a4000e3f3b9b`）建立 `feat/transaction-merchants`，開始同一商家全流程工作單位。目前完成獨立 Merchant Domain 的身份、別名增刪／候選、封存／啟用、明確合併與歷史解析；15 項新業務案例、15 項既有架構測試、格式／分析及實際依賴掃描通過。[本批證據](test-results/merchant-domain-host-2026-09-27.json)／[完整接續工作](transaction-merchants.md)。目前沒有商家資料表、Ledger 商家引用、schema 7、migration 或 UI，不將 Domain 通過稱為 M1-02 完成；繼續同一功能分支及草稿 PR，完整流程完成前不再切另一商家子功能 PR。

Tag 批次上傳已核對：本機／遠端／PR #46 全部為上述完整 SHA，工作目錄當時乾淨、所有本機分支未上傳提交為 0。main 仍為 `d0d39e1de32774aca319b8fed0cc9ee288cbb94a`。這次核對在新增商家 Domain 之前完成，商家後續提交另行核對。

2026-09-27 交易標籤完整流程（本機驗證完成）：`feat/transaction-tags` 依賴 [PR #45](https://github.com/swz0103/ExpenseTracker-V2/pull/45)（`2ad7c9c4f5e89e5ccaddc7e1ff5b5434d43a0d57`）。新增獨立 Tags 業務，App 可新增／改名／封存／啟用／明確合併，收支可複選最多 16 個標籤；金額、分類、標籤引用及 receipt／Audit 同一提交。歷史保留原 ID、版本及 metadata 序號，改名合併不改金額或舊引用；新交易清空選取。[操作與格式](transaction-tags.md)。

新帳本 schema 6／snapshot 5，舊 V2 schema 3／4／5 沿明確路線逐步安全升級。升級前核對密碼與救援備份，來源 DB／key 保留；所有新資料納入既有 50,000 列／16 MiB 容量保護。回查發現來源表失去唯一限制時，分類／Tag 的重複 ID 可取代另一列而逃過原驗證；兩個失敗案例已重現，修正並納入完整回歸。

完整 **15 套件、562 項獨有本機測試** 通過，新增 54 項；含格式、靜態分析、實際依賴掃描、五個原生 worker 重建、11 處升級程序中止、4 處 App 升級例外及適用 UI。[完整清單](test-results/transaction-tags-host-2026-09-27.json)區分完整回歸與額外文案回歸，沒有重複累加數字。

兩組獨立大量資料均通過：[新帳本](test-results/transaction-tags-scale-2026-09-27.json)保留 5,000 筆事件、9,998 個 Tag 引用；[已滿舊帳本升級](test-results/transaction-tags-upgrade-scale-2026-09-27.json)逐表確認原有 5,000 筆事件及分類資料不變，事件容量已滿所以沒有額外新增 Tag 引用。各含 256 個 Tag／1,024 次異動、5,003 次重送，並在刪除合成來源 DB 與 vault keys 後，分別以密碼／救援還原、重開、比對完整 bytes 及獨立餘額。兩次耗時 308.382／297.825 秒，不能相加當成單帳本容量或 Android 效能。

`0.4.0+5` ARM64 debug APK 建置及封裝核對通過，hash 與身份見[安裝包紀錄](installable-preview.md)。本批雲端未執行、手機未操作、main 未合併；待雲端 gate 的分支仍保留。Tag 搜尋／報表／預算應用及 Merchant／alias 尚未交付，不宣稱 M1-02 或全部 CORE 完成。提交並核對上傳後，下一分支接 Merchant／alias 的完整流程。

2026-09-27 分類搬移與合併（本機驗證完成）：`feat/category-management` 基於 #44 的 `f0bd94e6137692eee24092732d50204961a0ba19`。同一輪接續完成 App 公開接口與明確確認的搬移／合併畫面，保留原分類引用、版本與目前合併去向；取消編輯清除不同收支類型的父分類／目標選擇。資料表、schema、底層計算、加密與備份格式未變更。App 格式、分析、實際架構掃描與 **36 項 App 完整回歸**通過，新增 2 項涵蓋版本衝突、跨帳本拒絕、重送、歷史引用、備份還原與操作確認。底層沿用前批 506 項及四組大量資料證據，沒有宣稱本批再跑全部套件。

`0.3.1+4` ARM64 debug APK 建置成功，身份、APK v2 簽章與 `allowBackup=false` 核對通過；[驗證清單](test-results/category-management-host-2026-09-27.json)及[安裝包資訊](installable-preview.md)保留 hash。雲端未執行、手機未操作、main 未合併；有歷史子分類的父分類仍不能直接合併。此批以獨立 PR 依賴 #44，完成上傳後從本分支接交易 Tag 的業務、保存與歷史引用，接著 Merchant；M1-02 及整體 CORE 尚未全部完成。

2026-09-27 App 分類接入（本機驗證完成）：沿用 `feat/app-category-upgrade`／[PR #44](https://github.com/swz0103/ExpenseTracker-V2/pull/44)，基於 #43。已接上新帳本 schema 5、舊 V2 帳本明確確認後 3 → 4 → 5 安全升級／中斷接續，以及雙層分類新增、改名、封存／重新啟用、分類記帳與歷史顯示。[接口與使用範圍](app-categories.md)。

完整 14 套件共 **506 項獨有本機案例**通過，新增 App 引擎 13 項／畫面 2 項；格式、分析、五個原生 worker 重建與最終實際架構掃描通過。[驗證清單](test-results/app-category-host-2026-09-27.json)保留範圍及重跑原因。App 共 34 項：第一輪 32 項通過，兩條乾淨還原案例因 Windows 路徑分隔符的測試清理核對而停止；改成解析實際絕對路徑後，兩條完整通過。沒有弱化清理邊界、財務斷言或正式程式。

App [大量資料](test-results/app-category-scale-2026-09-27.json)完成 5,000 事件／4,999 分攤／256 分類／768 次變更／5,002 次重送，完整 bytes 與獨立餘額、清除來源 DB／key 後密碼及救援各自還原、滿額拒絕與重新解鎖通過，約 374.28 秒。此 App 案例先升級一筆期初再建立大量資料；另完整回歸三組獨立 5,000 筆資料集的[加密還原](test-results/app-category-encryption-regression-2026-09-27.json)、[引用／容量](test-results/app-category-reference-regression-2026-09-27.json)與[舊格式升級](test-results/app-category-legacy-regression-2026-09-27.json)，不合併宣稱單帳本容量。

`0.3.0+3` ARM64 debug APK 已建置並核對身份、簽章及 `allowBackup=false`，[安裝包資訊](installable-preview.md)保留 SHA-256。未操作手機、未啟動雲端、未正式發版或合併 main；需雲端 gate 的分支收斂仍保留。M1-02 未全部完成，接下來補分類搬移／合併的完整操作，再接 Tag／Merchant；M1 其他日常功能、M2／M3 與平台 gate 均繼續保留。

2026-09-27 分類引用世代升級與工作階段：`feat/ledger-reference-upgrade` 基於 PR #42（`4cd097f4e94704ae3a830eff1925ac5c6353f805`）。完成 schema 4 → 5 的同鎖安全備份、已知格式轉換與原子發布，保留舊 DB／key；新舊升級路線共用程式並核對目標模式，避免 request 宣告與實際格式不同。接上 `LedgerSession.post` 分攤、不可變歷史讀取與一般／持久備份，分類改動後的舊引用及 replay 保留。

容量改按實際 UTF-8 bytes／跨表列數逐筆計算，分類更新扣除原狀態再加入新狀態；資料與容量計數一起提交或回滾。維持 32 帳戶、5,000 事件、256 分類、1,024 次變更及每列限制，分攤納入全域 16 MiB／50,000 列；不以最壞假設一律拒絕新格式，也不讓失敗寫入耗掉額度。[完整接口與限制](ledger-reference-upgrade.md)。

受影響套件共 **170 項獨有本機測試**通過（Ledger 119、Android 主機 17、App 19、架構 15），新增 27 項；格式、靜態分析、Ledger worker 重建及實際架構掃描通過。含 11 處獨立程序中止、4 條刪除來源 DB／key 後的單憑證還原，以及容量拒絕後繼續合法寫入。[驗證清單](test-results/ledger-reference-upgrade-host-2026-09-27.json)區分先行測試及完整回歸，其餘十個套件本批未重跑。

同一新帳本 **5,000 事件／7,497 分攤／256 分類／1,024 次歷史／4,998 次重送**通過，完整 snapshot 8,610,791 bytes、餘額 2,511,000 minor units、密碼及救援各自還原、合併／封存後滿額重送皆正確；[原始結果](test-results/ledger-reference-upgrade-scale-2026-09-27.json)約 382.14 秒。同時完整回歸[既有 schema 3 → 4 大量升級](test-results/ledger-reference-upgrade-legacy-regression-2026-09-27.json)，snapshot 6,060,123 bytes、案例約 311.25 秒；兩者是不同帳本，耗時不是隔離效能或實機保證。

雲端未執行，兩個 workflow 維持停用；手機未操作、main 未合併，需雲端 gate 的分支收斂暫緩。下一分支接 App 的既有備份憑證、已知升級規劃／恢復與容量准入，再接簡潔分類錄入；App 畫面、平台升級 gate、Tag／Merchant 與其他 M1／M2／M3 CORE 均未宣稱完成。

2026-09-27 交易分類引用：`feat/ledger-category-references` 基於 PR #41（`095d81f09638e84d4676d2edaa42381b1c5ed654`）。完成收入／支出精確分攤、分類預期版本及入帳時 metadata 序號、同一交易保存與版本化 receipt。schema 5／snapshot 4／ledger module 3 為明確 opt-in；舊模式及無分攤 receipt 保持相容，分類之後改名／合併／封存仍可驗證歷史交易與重送。回查並修正來源表失去唯一限制時，備份漏檢重複分攤的問題；共用合成 fixture 改用正式套件入口，未放寬架構邊界。

完整 14 套件共 **464 項獨有本機測試**通過，其中新增 35 項。先完成當時 463 項清單，最後補上重複分攤案例後，再全量重跑快照 57 項及加密 34 項；格式、靜態分析、五個原生 worker 建置與實際架構掃描通過，兩個受影響 worker 於最後修正後再建置。[驗證清單](test-results/category-references-host-2026-09-27.json)明列範圍，沒有將重跑重複計數。

新加密帳本 **5,000 事件／7,498 分攤／4,999 次重送**、分類合併／封存後的密碼與救援雙路完整還原通過；snapshot 7,751,582 bytes，獨立計算餘額 2,511,000 minor units。[大量資料原始結果](test-results/category-references-scale-2026-09-27.json)約 173.73 秒，非隔離效能或實機保證。另完整回歸既有 **5,000 事件＋256 分類＋1,024 次 metadata 變更**的升級、同鎖安全備份及雙路還原，6,060,129 bytes；[舊路徑原始結果](test-results/category-references-legacy-regression-2026-09-27.json)與新引用案例為不同帳本，不混算容量。

雲端未執行，兩個 workflow 保持 `disabled_manually`；手機未操作，main 未合併。這批完成的是底層保存及暫存還原，`LedgerStore`／`LedgerSession` 的 schema 4 → 5 安全升級、正式世代發布、分攤讀寫與容量預檢，以及 App／UI 仍待接入，M1-02 未完成。[接口、格式與限制](ledger-category-references.md)。下一功能分支接續這些世代／工作階段能力；需雲端 gate 的分支收斂持續暫緩。

2026-09-27 分類工作階段：`feat/category-session` 基於 PR #40（`80a588f`）。接上新增／改名／移動／封存及啟用／合併／讀取公開接口，共用金融佇列、原子交易與 operation namespace。修正 schema 4 工作階段匯出格式及僅分類 workspace 的發現；將原 App 匯入與 session 寫入容量檢查統一，納入分類歷史、receipt／Audit 和 UTF-8 每列 bytes，上限拒絕不破壞已完成操作的 replay／conflict。

8 項新增整合案例及受影響回歸共 **164 項本機測試**通過（Ledger 92、還原 38、App 19、架構 15），包含格式、靜態分析、兩個 worker 重建與實際架構掃描；未把重複跑的新案例重複計數，也未宣稱本輪全 14 套件重跑。[驗證清單](test-results/category-session-host-2026-09-27.json)。同一帳本的 **5,000 金融事件＋256 分類＋1,024 次分類變更**，完整 6,060,117 bytes snapshot、獨立餘額、密碼／救援各自還原與金融／分類重送皆通過；[大量資料原始結果](test-results/category-session-scale-2026-09-27.json)約 216.08 秒，非隔離效能或實機保證。[接口、容量與限制](category-session.md)。

雲端未執行，兩個 workflow 維持 `disabled_manually`；手機未操作，main 未合併。分類仍未接交易引用／正式 App 升級／UI，M1-02 及整體 gate 未完成。下一分支接交易分類引用及版本、歷史還原驗證，之後再串產品升級與畫面；需雲端 gate 的分支收斂暫緩。

2026-09-27 額度調整：使用者回報 Actions 本月剩 190、每月 2,000；官方單位為執行分鐘。兩個 workflow 已在 GitHub 暫停，確認無執行中／排隊工作；`ci/actions-budget` 基於 PR #38，後續分支改手動觸發設定，日常與整合主機驗證移至本機，雲端額度保留給重要驗收。新入口的架構／原生程序／Flutter 三條路徑共 43 項本機測試及相關分析通過，兩份 YAML 與完整 14 套件清單核對通過；本次雲端未執行。[完整政策與本機入口](ci-budget-policy.md)已同步到原有每 30 分鐘開發排程；不因缺少 checks 宣稱雲端通過，不改 branch protection 或自行合併 main。

PR #38（`7298ca413514c67d344c5ba5cdb97de3f9c78cb2`）在本次預算調整前已完成 14 個雲端工作，完整主機清單 391 項通過。額度調整另以 PR #39（`b298c6c`）交付，其後 `feat/ledger-category-upgrade` 的限定主機串接已完成下列驗證。

2026-09-27 Ledger 分類升級：基於 #39，串接來源 live snapshot 預檢、雙憑證持久安全備份、已知 schema 3 → 4 轉換與原子世代發布。沿用同一保存與發布程式；補強實際檔案 bytes 摘要、缺少來源時不初始化 catalog／key。新增 30 項案例，包括 11 個獨立程序中止及四條刪除來源 DB／key 後的密碼／救援乾淨還原；14 套件完整主機清單共 421 項通過，格式、靜態分析、五個 worker 建置及實際架構掃描通過。Ledger 先跑全量 83 項，再對最後來源預檢補強重建 worker、執行成功路徑與新拒絕案例，獨有案例共 84；其餘套件 337 項。[驗證清單](test-results/ledger-category-upgrade-host-2026-09-27.json)保留範圍，不以重複執行增加總數。

5,000 筆事件／4,997 筆新增／4,997 次重送的升級、完整 snapshot、獨立餘額、雙路備份與還原、重試和容量保護通過，[原始結果](test-results/ledger-category-upgrade-2026-09-27.json)已保存。雲端未執行，手機未操作，App 預設仍是 schema 3；正式 BackupProfile／升級引導、分類交易引用、容量預檢及 UI 未完成。[完整路徑及限制](ledger-category-upgrade.md)。下一項在後續分支接分類公開操作／讀取接口與必要容量保護，不提前開放 UI，也不因本機通過就略過待實機 gate。

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

2026-09-27 本輪補記：Categories 保存 PR #36（`948571f`）完整 368 項主機測試／14 個 CI 工作全部通過，包含新 23 項及既有金融、加密、程序回歸與 App 測試。第二批 #13～#27 已收斂到 #32，整合 head `b141392` 的 303 項／12 個工作通過；#28 改接前後 patch 相同，15 個舊遠端分支移除且提交保留。#13 由 GitHub 辨識為已合入整合分支，其餘已取代 PR 關閉，main 未變。[完整收斂紀錄](branch-consolidation.md)。接續補升級紀錄、備份到發布的同鎖流程及中止復原，再接分類交易引用與 UI。

## 尚未完成的 gate

2026-09-27 接續：PR #37（`cd2a349`）的 368 項／14 個 CI 工作全部通過。新分支 `feat/storage-upgrade-receipts` 基於 #37，新增加密 catalog 3 的升級 intent／每次嘗試紀錄、來源目前內容摘要比對、同鎖準備與原子發布，復用既有發布程式；一般還原／升級 ID 不可混用，重試不得變更目標或備份摘要。23 項新案例包含十處獨立程序中止；連同儲存與 Ledger 共 149 項本機回歸通過，完整 CI 清單為 391 項，以本 PR checks 為準。[接口、版本與限制](storage-upgrade-receipts.md)明列此批為控制機制，Ledger 真實安全備份／schema 4 轉換尚未串接，App 未啟用升級。

整體階段 0／1 尚未完成，Architecture Baseline 仍 rc1。Android 已有可用測試手機，指定加密／secure storage／雙路乾淨還原與程序重開已有實機證據；完整 migration 故障、OS 重開機、正式備份憑證延續與 provider 路線仍未全部結案。M1／M2／M3 未完成。目前另交付具實際輸入流程的最小試用 App，其新平台流程仍待實機驗收；不可將此有限試用版視為完整日常版本或 gate 全部通過。

詳細順序見[實作計畫](implementation-plan.md)，財務契約見[工程規格](foundation-contracts.md)，驗收案例見[案例清單](foundation-acceptance.md)。
