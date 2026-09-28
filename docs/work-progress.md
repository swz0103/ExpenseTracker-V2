# 逐項實作進度

## 2026-09-28 M1-05 歷史商家月報（主機驗證完成）

沿單一 `integration/v2-core` 候選線完成[商家月報](merchant-reports.md)：Ledger 月份查詢同次讀取保存的商家 ID，Reports 依報表原幣分組、逐幣別對上月收支，退款與撤銷保留原歸屬，轉帳費用與未指定商家另列。商家合併不改寫舊交易，畫面顯示原名稱與目前狀態，明細可查活動並沿用遮罩／鎖定。沒有新表、資料格式或持久投影。[本批證據](test-results/merchant-reports-host-2026-09-28.json)記錄 Reports **10**、Ledger **246**、App **173**、架構 **20** 項完整受影響主機檢查、靜態分析及 Android ARM64 debug 建置通過。手機經 ADB 檢查仍未偵測到，雲端 workflow 保持停用、無新 checks；不宣稱實機、雲端或 M1-05 全部通過。帳戶維度及後續 CORE 繼續開發，`main` 不合併。

## 2026-09-28 M1-05 現金／銀行資產摘要（主機驗證完成）

同一候選線接續[資產摘要](asset-summary.md)：逐幣別合計 Ledger 已重建帳戶餘額，納入狀態沿用帳戶設定；首頁註明目前沒有跨幣、投資或完整淨資產估值，金額仍可遮罩。沒有新增持久資料或備份格式。[本批證據](test-results/asset-summary-host-2026-09-28.json)記錄 Reports 全包 **9**、架構 **20** 項及 App 靜態分析、ARM64 debug 建置通過。App 完整首輪 **172 通過／1 失敗**：商家測試把「記一筆」捲至頂欄下方，點擊失效；僅調整測試可見位置後該項定向重驗通過，正式程式不變，**未將首輪全量誤稱為最後全量零失敗**。雲端未執行、手機未偵測到；商家／帳戶維度與整體 M1-05 gate 未完成。

## 2026-09-28 M1-05 分類月報（主機驗證完成）

在 `integration/v2-core` 接續[分類月報](monthly-reports.md)：Ledger 月份讀取一次取回有效事件及歷史分攤，Reports 套件依事件正負影響逐幣別、逐分類合計，未分類與轉帳費用另列；分類更名不重分配。畫面可展開分類份額、查活動，並沿用金額遮罩與背景鎖定。沒有新表、schema 或備份格式。[本批證據](test-results/category-reports-host-2026-09-28.json)包含 Reports 全包 6、Ledger 舊格式／分攤／還原 2、5,000 事件整合 1、App 畫面 2、架構 20 項，以及靜態分析與 ARM64 debug APK 建置；本批未重跑完整 Ledger／App 清單，不能把前批全量結果稱為本版全量通過。雲端 checks 未執行，手機目前未接入；商家、帳戶、資產摘要與 M1-05 gate 未完成。

## 2026-09-28 M1-05 逐幣別月收支（主機驗證完成）

在單一候選線 `integration/v2-core` 接續[月度收支](monthly-reports.md)：Reports 套件根據 Ledger 權威的正負報表影響值逐幣別彙總，首頁顯示當月收入與淨支出，明細可換月並追查活動。期初與轉帳本金不列收支，手續費、跨月退款與撤銷沿用原事件報表歸屬；刪除標記退出有效集合。無新增權威資料表或備份格式。Ledger generation 全量 **245**、App 修正後逐檔全量 **171**、Reports **4**、架構 **20** 及工作區掃描通過；其後針對空月份仍可開啟歷史月報的小修，最後版本的定向畫面 **2** 項、分析及 ARM64 debug APK 封裝通過，App 全量未因該小修重跑。首輪 App 全量的 7 個首頁位置失敗及修正後定向／全量重驗均保留於[本機證據](test-results/monthly-reports-host-2026-09-28.json)。電腦目前未偵測到 Android 裝置，月報實機待驗；Actions 仍停用，main 未合併。M1-05 的分類／商家／帳戶與資產摘要還未完成。

## 2026-09-28 M1-05 交易搜尋與整合候選

接續已上傳的架構邊界 [PR #65](https://github.com/swz0103/ExpenseTracker-V2/pull/65) head `ab72700ae362272e6f0a27947dc1488d64773095`，在 `feat/transaction-search` 完成[唯讀交易搜尋](transaction-search.md)：版本化 AND 條件包含日期、任一帳戶、分類、標籤、商家、幣別、交易類型、原幣本金絕對金額及最新備註；查詢由 Ledger session 讀取正式事件，刪除標記排除，沒有新資料格式或衍生索引。首頁搜尋畫面沿用金額／備註遮罩，離頁與鎖定清掉條件及結果。

Ledger Domain 全量 **27**、Ledger generation 全量 **243**、額外 **5,000 筆**查詢與完整分頁、App 逐檔全量 **170**、架構工具 **20** 及工作區掃描均通過；詳細來源雜湊與首輪並行測試失敗及修復見[本機證據](test-results/transaction-search-host-2026-09-28.json)。首輪 App 並行全量有一個因新入口使既有商家列離開可見區的斷言失敗，以及一個重負載逾時；修正測試捲動後逐檔全量通過，沒有放寬逾時。兩個 Actions workflow 持續停用。這批手機搜尋測試未執行：當下 `adb devices -l` 未偵測到手機；先前 schema 12 的[實機初驗](test-results/device-smoke-2026-09-28.json)不能代替搜尋驗收。M1-05 的月收支及分類／資產報表仍待完成，main 未合併。

分支收斂依使用者最新授權進行：搜尋已在私人 V2 [PR #66](https://github.com/swz0103/ExpenseTracker-V2/pull/66) 交付，本機、遠端與 PR head 均為 `bddcb135a33cd4b51f08caea1aa7cfbf15d53ae5`。同一提交作為 `integration/v2-core` 的起點，建立對 main 的 [Draft PR #67](https://github.com/swz0103/ExpenseTracker-V2/pull/67)。40 個當時開放 PR 的 head 均已確認為候選線祖先；完整[收斂紀錄](branch-consolidation.md#2026-09-28單一整合候選線)保留舊 PR 的提交與依賴。#66／#67 均無雲端 checks，所需 gate、差異及審查核對前不關閉／刪除被涵蓋的舊 PR／遠端分支，不向 main 自行合併或移動舊 PR base 造成自動關閉。

## 2026-09-28 執行時架構邊界與實機初驗（進行中）

接續已上傳的 [Tombstone PR #64](https://github.com/swz0103/ExpenseTracker-V2/pull/64) head `ef5f3b4ddcd78fc10c905510e8a3375d23c35233` 另開 `fix/runtime-boundary-policy`。依[架構核對](architecture-audit-2026-09-28.md#接續執行時模組依賴邊界)把正式 App 和它依賴的 prototype 明列於檢查規則，禁止未核准的本機依賴、錯誤來源、反向依賴與循環；Domain 既有規則不放寬。架構工具靜態分析、20 個單元案例及全工作區掃描通過。只改檢查器、政策、測試與文件，未動財務運算或資料格式；雲端 workflow 保持停用，待提交後才算 GitHub 交付。

使用者已接入並授權測試 Android 實機。主使用者空間原先沒有 V2 App；安裝獨立 ID `dev.expensetracker.preview` 的本機 ARM64 debug APK 後，以**合成帳本**完成首次設定、TWD 1,000.00 期初與 125.50 支出，餘額 874.50；鎖定及程序重啟後仍需密碼，解鎖後資料保持。加密備份經系統文件選取器儲存並讀回核對；再記 10.00 支出後，錯誤備份密碼被拒且餘額保持 864.50，密碼及救援文字兩條實際還原各回到 874.50，重啟後仍保持。完整範圍與未測項見[實機證據](test-results/device-smoke-2026-09-28.json)。本機合成救援文字放在 Git 忽略檔，測試備份留在手機；沒有讀取舊 App。**這是 schema 12 流程的單一 Android 16 實機驗證，不是 M1/M2/M3 或 schema 13／14 的完整實機 gate。** 新更正與 Tombstone 仍是測試入口，尚未在預設 App 開放。

## 2026-09-28 一般交易 Tombstone（進行中）

從已上傳的[更正 PR #63](https://github.com/swz0103/ExpenseTracker-V2/pull/63) head 建立 `feat/transaction-tombstones`，保留 #63 → #62 的審查依賴。[刪除契約](transaction-tombstones.md)固定只有無退款、撤銷、更正等後續依賴的一般正式收支／轉帳可進入 tombstone；原事件留在歷史，但退出有效餘額及列表，不能同時再用反向事件抵銷造成雙扣。凍結原事件的 Domain 命令與不合法種類、workspace、operation、原因拒絕已實作，Ledger Domain 全量 24 項及靜態分析通過。schema 14 保存層原子 marker／收據／audit 與失敗回滾、可攜 snapshot format 13、加密 generation 容量及有效讀取、雙憑證乾淨還原、安全備份及 13→14 故障後保留來源已接通。[保存檢查點](test-results/tombstone-storage-host-2026-09-28.json)：保存層 **60**、還原 **106**、加密 generation **240**、SQLCipher **34** 項和分析、邊界檢查通過。回查修正安全備份讀取器漏傳近期 schema 旗標，避免新版被錯誤拒絕。

App 的 schema 14 測試入口、安全升級、凍結加密草稿、提交後回覆遺失的精確恢復、刪除確認與已刪除歷史已接通；預設 App 仍使用 schema 12，未開放新功能。本機草稿套件 **28** 項、App 完整 **169** 項與最後畫面定向回歸、相關靜態分析通過；四處真實程序退出後均只留下單次刪除與可查活動，[結果](test-results/tombstone-process-2026-09-28.json)已保存。[5,000 筆合成資料](test-results/tombstone-scale-2026-09-28.json)在中斷後重新開啟同一持久帳本，核對 2,499 刪除標記、兩組分頁、兩個獨立幣別餘額、容量拒絕後快照不變，以及移除原 DB／金鑰後密碼與救援各自乾淨還原。該筆資料的全量開啟、快照及兩條還原耗時偏高，詳見[架構審查量測](architecture-audit-2026-09-28.md#後續實測大量帳本的開啟驗證成本)，不宣稱 100k+ 效能 gate 通過。ARM64 debug APK 本機封裝通過，V2 App ID 仍為 `dev.expensetracker.preview`；[本機證據](test-results/tombstone-app-host-2026-09-28.json)記錄範圍與產物雜湊。已由依賴 #63 的 [PR #64](https://github.com/swz0103/ExpenseTracker-V2/pull/64) 交付私人 V2；本機／遠端／PR 初次提交 SHA 均為 `fc7dc0ba399419263d108c81725536ba4a7953c7`，沒有未上傳的本機提交。雲端與實機 gate 仍未執行；M1-04 和整體 CORE 尚未完成。

## 2026-09-28 財務更正加密保存與升級（進行中）

schema 13 更正鏈已從明文保存／可攜 snapshot 接到加密 Ledger session：原交易完整沖回與替代事件同一筆資料庫交易提交，兩筆收據綁定相同關聯；重送須匹配整組結果。加密備份由密碼、救援金鑰各自從空白目的端還原且可重送；12 → 13 staged upgrade 先保存並分別驗證兩種憑證的安全副本，中途故障保留舊資料與金鑰，再試可完成。Ledger session 加入更正的雙事件及關聯容量預檢。

本機受影響套件：保存層 55、可攜還原 103、Ledger generation 237、SQLCipher 儲存 34、App 舊 schema 完整 161 項通過；相關靜態分析與格式檢查通過。這是未完成的功能檢查點：App 預設 schema 12，尚未接更正草稿／畫面，還缺大量資料與完整程序中斷驗證。兩個 GitHub Actions workflow 維持停用，沒有雲端通過證據；實機未操作、`main` 未合併，不宣稱 M1-04 或安全 gate 完成。詳見[更正契約](transaction-corrections.md)。

接續 App schema 13 建立／驗證及 12 → 13 升級路由。新增故障後舊版可讀、可備份及重試升級案例；它找出 Ledger session 對新關聯表快照漏傳能力旗標，已修正並新增 session／store 快照相等斷言。App 定向案例與 Ledger 更正 session 兩項通過，靜態分析通過；App 預設仍是 schema 12，正式更正草稿和畫面還沒接入。

再接更正草稿與測試畫面：凍結後保存原／沖回／替代三事件及兩個 operation，重啟僅在整組提交精確匹配時清除；收支與跨幣轉帳可填替代日期、雙本金及費用。320px 大字體／遮罩／取消確認／實際單次入帳的畫面案例通過；草稿套件完整 24 項及 App 四項定向案例通過。App 全量回歸執行中，尚缺更正 Activity 完整鏈結、容量邊界與大量資料，預設版本沒有改為 13。

固定來源的 App 全量 165 項通過。隨後修正更正 Activity：原事件、沖回及替代事件可沿根事件與穩定游標查閱，連續兩次更正也不斷鏈；交易列表以「已更正」區別一般撤銷。新／舊活動的 Ledger 5 項及 App 3 項定向回歸通過，靜態分析通過。這次 Activity 改動後的 App 全量與大量資料、容量及程序退出驗證仍待執行，App 預設仍為 schema 12。

本批最新驗證：Activity 修正後的 App 全量 **165 項**、Ledger generation 全量 **238 項**、草稿套件 **25 項**通過；排版後定向 App 7 項及架構邊界檢查亦通過。5,000 筆事件／1,666 組更正的大量測試包含 833 組跨幣轉帳；整組重送、事件容量拒絕後快照不變，以及刪除來源 DB／金鑰後的密碼與救援兩路乾淨還原均通過。四個真正程序退出點重開後只留下精確的原交易、沖回、替代事件及餘額；最大拆分、標籤與原因的凍結草稿亦可在 16 KiB 加密槽限制內往返。見[主機結果](test-results/corrections-host-2026-09-28.json)、[大量資料結果](test-results/corrections-scale-2026-09-28.json)、[行程中斷結果](test-results/corrections-process-2026-09-28.json)及[更正契約](transaction-corrections.md)。預設 schema 12，雲端與實機未驗證，`main` 未合併；M1-04 的 tombstone、搜尋報表與後續 M2／M3 仍待開發。

## 2026-09-28 架構審查第一批：集中 App 能力門檻

依使用者提供的[審查清單](architecture-audit-2026-09-28.md)逐項對照程式，確認畫面與草稿流程原本直接比較資料庫版本、既有架構檢查尚未涵蓋執行時 prototype 依賴；未發現需全面重寫的錯誤字串分派。本批將 schema 3～12 的功能門檻收斂到 `PreviewCapabilities`，供畫面、草稿、複製、App 儲存建立與測試 fixture 使用，原有可用功能與資料格式不變。大型首頁狀態及異步次序仍需以具體案例繼續檢驗。

本機 App 靜態分析與完整 161 項案例通過；架構工具 15 項案例及實際儲存庫檢查通過。未重跑未變更的底層套件；雲端 Actions 停用、實機未驗證，`main` 未合併。本批由依賴備註的 [PR #62](https://github.com/swz0103/ExpenseTracker-V2/pull/62) 交付；接入進行中的財務更正分支後續作 M1-04，不能因本次檢查而宣稱地基、M1～M3 或 Architecture Freeze 完成。

## 2026-09-28 下一批：財務更正（進行中）

由已上傳的 [備註 PR #61](https://github.com/swz0103/ExpenseTracker-V2/pull/61) 建立 `feat/transaction-corrections`；[操作契約](transaction-corrections.md)固定原交易完整反向、替代事件及兩者原子提交／追溯。Ledger 更正提案已實作身分與 operation 衝突拒絕、原日期精確沖回，含跨幣轉帳與手續費；該套件分析與 22 案例本機通過。接入架構修正 [PR #62](https://github.com/swz0103/ExpenseTracker-V2/pull/62) 後，新增未啟用的 schema 13 保存層：兩筆金融操作與唯一更正關聯原子提交，收據綁定完整三事件與各自角色，完整匹配才接受重送；可攜 snapshot 明確拒絕缺漏或錯誤關聯。保存層 55 項、可攜還原套件 103 項、既有上層 Ledger session 235 項及最後受影響的備註／撤銷 session 10 項本機案例通過。加密雙憑證安全備份、V2 staged upgrade、容量、加密草稿與 UI 尚未完成；目前沒有此功能 PR，也未開放入口。下一步接 Application 與安全資料演進，不把保存層 checkpoint 當作功能完成。

## 2026-09-28 本批：交易備註修訂與安全恢復

由已核對上傳的 [PR #60](https://github.com/swz0103/ExpenseTracker-V2/pull/60)（完整 head 56743aa150cb33dd7054a87327e008c3498dd19c）建立 feat/transaction-notes，完成[純文字備註與修訂](transaction-notes.md)：每筆交易可保存／清空備註、預期版本衝突拒絕、完整修訂活動、加密草稿及提交後中斷恢復。文字修改不改金融事件與餘額；隱私模式遮蔽列表／活動備註，鎖定清除編輯畫面。

回查修正原始入帳收據辨識：精確匹配財務 kind，避免備註 audit 被誤認成金融收據。草稿、operation transaction、staged upgrade 沿用既有流程；相鄰升級測試共用 fixture。schema 12／snapshot 11 保存完整修訂鏈，11→12 先以密碼與救援文字各自驗證安全副本，再切換並保留舊 DB／key。

固定來源的**完整 18 套件、869 個獨立主機案例**通過，新增 23 個；[主機證據](test-results/notes-host-2026-09-28.json)保存逐套件結果、來源雜湊及開發期修正。含 11 處真實升級程序退出、ACID 逐點回滾、超長／無效 Unicode、衝突與重試、竄改／缺漏還原拒絕、320px 大字體與鎖定 UI。

[5,000 筆交易＋5,000 次備註修訂](test-results/notes-scale-2026-09-28.json)及 9,999 次重播通過；snapshot 8,635,238 bytes、35,002 rows，獨立核對餘額、上限拒絕、完整交易／活動分頁，刪除合成來源 DB／keys 後密碼與救援各自乾淨還原。[四處草稿程序退出](test-results/notes-process-2026-09-28.json)亦通過。[0.16.0+20 開發包](installable-preview.md)僅留本機，未安裝／發布。

以依賴 #60 的功能 PR 交付私人 V2；兩個 workflow 維持停用，無新雲端測試。提交後另核對本機／遠端／PR 完整 SHA 與所有本機提交涵蓋；未合併 main，未清理待雲端 gate 的分支。

**下一流程**：M1-04 財務更正／替代與 tombstone，保留已有退款／撤銷依賴限制，再接搜尋報表、CSV／JSON、M2、M3。備註修訂不代表完整財務更正或 M1 gate 已完成；實機 gate 保留，沒有需使用者先處理的主機開發阻礙。

## 2026-09-28 接續：完整反向撤銷與安全升級

由已核對上傳的 [PR #59](https://github.com/swz0103/ExpenseTracker-V2/pull/59)（完整 head 0b8ba69471d156f93c1be6931b9eb6db931a8401）建立 feat/financial-reversals，完成[正式撤銷](financial-reversals.md)：收入、支出、同幣／跨幣轉帳與原手續費逐項抵銷，保留原交易及歷史歸屬，活動串接兩筆。已有退款／撤銷的來源互斥拒絕，重試不重複入帳；提供金額影響、日期／原因、確認與可恢復加密草稿。

回查另修正最大 16 分類／16 標籤／商家與 256 字原因的撤銷收據容量，寫入及還原共用限制；最大組合保存、重試與還原通過，原交易容量不變。

回查遵循既定契約：reversal 同時保留原與反向事件，不能又排除原交易一次。schema 11／snapshot 10 增加唯一來源關聯及完整還原驗證；10 → 11 先完成雙憑證安全備份再發布，原 DB／key 保留。來源財務事實與分類／Tag／Merchant 版本在同一 transaction 重驗，沒有加入通用級聯撤銷。

**完整 18 套件／846 個獨立主機案例**通過，新增 31 個；[證據](test-results/reversals-host-2026-09-28.json)保存兩段固定來源雜湊、每組結果、容量修正及測試等待修正。14 個底層套件完成後未變更，容量修正影響的 4 個上層套件重新驗證；中斷的部分測試不計入。含 11 處升級退出、各反向寫入階段回滾、競爭命令、封存歸屬、篡改還原、窄螢幕／大字／遮罩／確認途中鎖定。

[5,000 混合事件](test-results/reversals-scale-2026-09-28.json)含 2,498 組撤銷、1,249 組跨幣與費用、既有部分退款及 4,996 重送；獨立核對財務淨額、容量拒絕、全部分頁，以及刪除來源 DB／keys 後兩種憑證各自乾淨還原。[四處草稿程序退出](test-results/reversals-process-2026-09-28.json)亦通過。[0.15.0+19 開發包](installable-preview.md)只留本機，未安裝或發布。

以依賴 #59 的功能 PR 交付私人 V2；兩個 workflow 持續停用，無新雲端測試。推送後另核對完整 SHA 與所有本機提交涵蓋；不合併 main，不清理需雲端 gate 的分支。

**下一流程**：M1-04 一般欄位 revision、正式財務更正與替代、tombstone 及活動歷史；已有退款與撤銷依賴不可被更正／刪除繞過。後續報表、CSV／JSON、M2、M3 仍未全部完成，實機 gate 保留。沒有需使用者先處理的主機開發阻礙。

## 2026-09-28 接續：交易活動查閱

已先上傳 [退款 PR #58](https://github.com/swz0103/ExpenseTracker-V2/pull/58)，本機／遠端／PR 完整 SHA `d7b63bf3b7b5b7bb1ba2cc459a92dac9230962cc` 相符，所有本機分支無未上傳提交。由此建立 `feat/transaction-activity`，完成[交易活動查閱](transaction-activity.md)：所有已支援交易的入口、原支出與相關退款、記錄時間／交易日期分列、每頁 30 筆及安全游標、既有金額遮罩與背景鎖定。

回查時間表示，UTC 可用不同小數精度；排序先正規化為 6 位，不直接比較原字串或經毫秒／浮點轉換。相同 instant 再以事件 ID 穩定排序，游標綁定工作區與原交易。查閱沿用既有 audit／退款關聯，不新增表或另一套財務權威，schema 10／snapshot 9 不變。

**受影響 3 套件／54 個獨立主機案例**通過，新增 5 個；[證據](test-results/transaction-activity-host-2026-09-28.json)逐一列出各組。65 事件／7 筆分頁驗證時間精度與重試去重、還原前後 snapshot 不變；兩個 App 案例刪除來源 DB／vault 金鑰後各以密碼／救援乾淨還原，保留實際記錄時間。32 事件在 320px、雙倍字體下分頁與鎖定隱私通過，另回歸複製、退款、雙幣轉帳與一般記帳畫面。最初 widget 因捲動未完成就點擊而失敗，修正測試等待後通過，沒有改鬆功能斷言。

本批不重跑未改動的持久化／升級／大量寫入；#58 的完整 18 套件／810 案例、5,000 事件與中斷證據保留，不算作本批新跑。0.14.0+18 ARM64 本機封裝核對通過，未安裝、未發布。以依賴 #58 的功能 PR 交付，兩個 workflow 仍停用，main 與待雲端 gate 的分支不變。

**下一流程**：M1-04 一般編輯 revision、正式 reversal、tombstone 及對應活動；先定有效版本與原支出／退款的依賴規則，再接原子保存、備份還原、草稿與簡潔 UI。現有活動列表尚不含分類改名或完整更正歷史，不宣稱 M1-04、M1 gate、M2／M3 完成。沒有需使用者先處理的主機開發阻礙。

## 2026-09-28 接續：部分／全額退款與原支出追溯

`feat/refund-postings` 由 [PR #57](https://github.com/swz0103/ExpenseTracker-V2/pull/57) 的 `fabe6b83f8aee0e7aaa4f8e0341ab336de37e61a` 接續。[退款流程](refunds.md)涵蓋同幣／跨幣實收、原支出與每分類累計限額、繼承歷史分類／Tag／Merchant、獨立負支出事件、可恢復草稿、凍結重試、簡潔入口與原交易查閱。

schema 10／snapshot 9 新增退款關聯與 reader 能力，9 → 10 先雙憑證驗證安全備份再發布新世代，保留原 DB／key。回查大量部分退款的限額讀取，改以同交易內精確整數彙總，避免每次重建所有歷史退款物件；沒有改成浮點或快取權威餘額。相同主機／邏輯資料的一次優化前後比較：寫入階段 259195 → 196085 ms，減少 24.3%；這不是手機效能承諾。

固定來源的 **18 套件／810 個獨立主機案例**通過，新增 31 個，包括最大 Money、競爭退款、每個寫入階段回滾、竄改還原、窄畫面雙倍字體／隱私及 11 個真正升級程序退出。[主機證據](test-results/refunds-host-2026-09-28.json)保留來源指紋及開發期間修正，早期重跑未重複計數。

[5,000 事件](test-results/refunds-scale-2026-09-28.json)含 4,996 筆退款、2,498 筆跨幣退款及 4,996 次重送；9,525,313 bytes／32,500 rows。獨立計算現金、零退款收入、負支出與分類減項；滿額拒絕、V2 9 → 10、刪除來源 DB／keys 後的密碼與救援各自乾淨還原、完整 bytes 與 5,000 筆分頁均通過。另[四處退款草稿程序退出](test-results/refunds-process-2026-09-28.json)通過。

[0.13.0+17 本機 ARM64 開發包](installable-preview.md)完成封裝核對。程式、文件、測試與證據透過依賴 #57 的功能 PR 交付；本機／遠端／PR head 於推送後另核對。兩個雲端 workflow 保持停用；沒有操作手機、正式發布、合併 main 或刪除待雲端 gate 的分支。

**下一流程**：M1-04 更正／撤銷／刪除與活動歷史，先確保原支出及既有退款相依不會被更正或刪除破壞，再接版本化保存、還原、草稿與 UI。消費報表、CSV／JSON、M2、M3 仍未完成；信用卡跨期退款及分期重算不屬本批。沒有需使用者先處理的主機開發阻礙。

## 2026-09-28 接續：平均、百分比與固定比例拆分

同次執行先上傳 [PR #56](https://github.com/swz0103/ExpenseTracker-V2/pull/56)，本機／遠端／PR 完整 SHA `d6c1a24fed4e6cfd5116bd1253e8a183214916f1` 相符，所有本機分支提交均已上傳。回查 [FV-016](full-vision-baseline.md#fv-016) 發現基本拆分還需平均／百分比／固定比例，因此先以 `feat/split-allocation-assist` 補齊[分配確認流程](split-allocation-assist.md)，再接退款。

使用既有 Money 整數分配與最後一項尾差政策；百分比必須精確合計 100%，每項皆須為正且至少一個最小貨幣單位。預覽、取消、修改後重算及確認套用分開，套用只更新同一加密草稿的實際金額。背景鎖定及已排隊的確認都不能跨 session 寫回。沿用 schema 9／snapshot 8／既有草稿格式。

**3 套件／177 個獨立主機案例**通過，含完整 App 146 個、amount_input 16 個及架構 15 個；新增 15 個。比例案例含 3,000 組獨立整數 oracle，未另充作 3,000 個案例。先跑的 8 個新 App 案例不重複計數。三種模式都驗證草稿重啟、提交回覆遺失不重複入帳、刪除來源 DB／keys 後的密碼與救援各自還原、重開及完整 bytes 比對。[證據](test-results/split-allocation-assist-host-2026-09-28.json)明列本次範圍與來源指紋。

未變更的持久化、升級及還原底層沿用 #56 五千事件及四處程序退出證據，未宣稱本批新跑。0.12.0+16 本機 ARM64 包已封裝核對；雲端及實機未執行。分支依賴 #56，main 未合併、需雲端 gate 的分支保留；M1-04 與整體 CORE 仍未完成。

**下一流程**：部分／全額退款，追溯原消費與拆分歸屬、限制累計退款、在退款期記消費減項，連同版本化保存、凍結送出、還原及簡潔入口一起完成；更正與刪除不得繞過退款依賴。沒有需使用者先處理的主機開發阻礙。

## 2026-09-28 接續：多分類拆分、草稿與隱私明細

`feat/split-entry-drafts` 由 [PR #55](https://github.com/swz0103/ExpenseTracker-V2/pull/55) 的 `596fd4bad7fec6c0397173bc959374c37bb72cbc` 接續，完成[拆分收支流程](split-entry-drafts.md)：2～16 個分類、正額與精確合計、部分文字加密草稿、凍結送出／重試、各項明細與隱私遮罩。複製時保留分類結構、重新填寫所有金額與日期。沿用 schema 9／snapshot 8，沒有為表單新增資料表。

回查修正有分類交易仍使用 1,024 bytes 收據上限的問題，與既有 Tag／Merchant 收據同用 4,096 bytes，寫入和還原一致。舊超限測試改用確實超過新上限的合計正確資料，保留反覆失敗回滾與容量狀態檢查。受影響 **8 套件／515 個獨立主機案例**經原批次與修正後回歸通過，新增 10 個；[證據](test-results/split-entry-host-2026-09-28.json)明列各次執行和來源指紋。未重跑不受影響的其他套件，不冒稱新一輪完整 18 套件驗證。

[5,000 事件](test-results/split-entry-scale-2026-09-28.json)包含 4,999 筆拆分、50 筆 16 項拆分及 4,998 次重送；8,805,906 bytes／30,828 rows。核對獨立餘額、收支、每個分類總額、金融 leg 與事件數相等；第 5,001 筆拒絕且快照不變。待處理拆分阻擋 schema 8 → 9 升級，處理完成後保留歸屬；刪除來源 DB／keys，再以密碼、救援各自乾淨還原、重開、比對完整 bytes 與 5,000 筆分頁均通過。[4 處真正草稿程序退出](test-results/split-entry-process-2026-09-28.json)也通過。

[0.11.0+15 本機 ARM64 開發包](installable-preview.md)完成封裝核對，未安裝、未發布。以依賴 #55 的功能 PR 交付；兩個 workflow 維持停用，雲端未執行，main 未合併。M1-04 退款、更正、撤銷、刪除及活動歷史仍待完成，M1／M2／M3 並未全部完成。

**當時的下一流程（已先由上方分配輔助補齊 FV-016）**：接續 `feat/refund-postings`，先把退款作為可追溯原消費的獨立事件，處理部分／全額與超額拒絕、退款期消費減項、分類歸屬、原子提交、版本化保存／還原和簡潔入口；更正／刪除不得繞過退款依賴。沒有需使用者先處理的主機開發阻礙。

## 2026-09-28 接續：跨幣實際本金與換算 context

同次執行先完成並上傳 [PR #54](https://github.com/swz0103/ExpenseTracker-V2/pull/54)，本機、遠端與 PR 完整 SHA `ffdb8a14c7434bcf0da41a079bf699bc6c8851ec` 相符，所有本機分支無未上傳提交。接著由該版本建立 `feat/cross-currency-transfers`，完成[跨幣轉帳](cross-currency-transfers.md)：雙本金、來源費用、精確實際比例、版本化收據／snapshot、可恢復草稿及列表。schema 9／snapshot 8 明確 8 → 9 先驗證雙憑證安全備份再發布；不讀取舊 App。

回查補上還原時的本金加費用範圍，並移除 App 每筆轉帳三次不適用的分類／Tag／商家查詢。完整 **18 套件／754 個獨立本機案例**通過，新增 31 項；全量後僅列表優化，相關 **10 個 UI 案例**和分析通過，不重複計數。[證據](test-results/cross-currency-transfers-host-2026-09-28.json)保留兩階段來源指紋及適用驗證，未把最終 UI 調整冒稱再次全量。

[5,000 事件](test-results/cross-currency-transfers-scale-2026-09-28.json)含 4,997 跨幣轉帳、4,998 次重送；10,932,466 bytes／33,745 rows，滿額拒絕不改資料。TWD／JPY 餘額與分幣費用符合獨立計算；刪除來源 DB／全部 key 後，兩條憑證各自乾淨還原、重開、完整 bytes 和 5,000 筆分頁核對通過。另 [4 處草稿程序退出](test-results/cross-currency-transfers-process-2026-09-28.json)通過；11 處升級退出已列入全量案例。

[0.10.0+14 ARM64 開發包](installable-preview.md)已封裝核對，不安裝、不發布。這批以依賴 #54 的 PR 交付；兩個 workflow 仍停用，雲端未執行。main 和需雲端 gate 的舊分支維持原狀。外部 FX、其他費用組合、基準幣報表與 M1／M2／M3 其餘 CORE 尚未全部完成。

**當時的下一項（現已由上方拆分批次接續）**：從此分支接 `feat/split-entry-drafts`，沿用已有 Allocation／歷史保存與驗證，完成多分類拆分的輸入、金額合計、草稿恢復、凍結送出與明細，再依 M1-04 接退款／更正／刪除。保持有效回歸、備份與升級檢查；沒有需要使用者先處理的主機開發阻礙。

## 2026-09-28 接續：同幣轉帳、來源手續費與雙帳戶明細

`feat/same-currency-transfers` 從已上傳的 [PR #53](https://github.com/swz0103/ExpenseTracker-V2/pull/53)（`b541b54cc4f3ee2b127f8e7b924f3d06bcb0139f`）接續，完成[同幣轉帳流程](same-currency-transfers.md)：原子保存雙方本金與來源費用、可重啟草稿、凍結送出／重試、列表呈現兩帳戶與費用，並沿用日期、計算器、隱私及背景鎖定。

回查修正原先只接受一個 leg 的容量與列表假設；每頁單一查詢讀出目的帳戶，沒有新增逐筆查詢。schema 8／snapshot 7 宣告新的 reader 能力，讓舊 App 拒讀；明確 schema 7 → 8 路線先驗證雙憑證備份再發布，保留來源 DB／key，舊草稿先處理再升級。未選目的帳戶或費用不合法時，訊息清楚指出限制且保留草稿。

完整 **18 套件／723 個獨立本機案例**全數通過，新增 26 項；包含 11 處真正升級程序退出。全量後修改提示，再跑相關 **13 項**通過；[主機證據](test-results/same-currency-transfers-host-2026-09-28.json)明列 257 檔受測指紋與四個後續修改檔案，不將重跑重複計數，也不冒稱最後 UI 文案再次跑完所有套件。初期測試 fixture／SemanticsHandle 清理問題已修正並保留紀錄。

額外[5,000 事件](test-results/same-currency-transfers-scale-2026-09-28.json)包含 4,997 同幣轉帳、4,998 次重送，snapshot 8,331,009 bytes／28,748 rows；滿額拒絕不改資料。來源／目的餘額 10,203／3,003、費用 7,494 最小單位與獨立計算相符。刪除來源 DB 與全部原 key 後，密碼及救援分別還原、重開、逐頁讀回完整 5,000 筆並比對全部 snapshot；另[4 處草稿真正程序退出](test-results/same-currency-transfers-process-2026-09-28.json)通過。

[0.9.0+13 ARM64 開發包](installable-preview.md)已建置並核對 App 身份、簽章與備份禁用；只留在本機，不安裝、不發版。此批以依賴 #53 的獨立功能 PR 交付；兩個 workflow 保持停用，本批雲端未執行。main 與需雲端 gate 的舊分支維持原狀，不擅自合併或收斂。

**當時的下一項（現已由上方跨幣批次接續）**：由此分支接 M1-03 跨幣轉帳：保存兩邊實際原幣本金、來源費用與可追溯轉換 context；優先實際成交數字，明確區分推算比率與外部報價。基礎 FxRate 已存在，但 Posting／收據／snapshot／草稿／列表當時仍限制同幣，必須一起延伸並完成對應升級和還原，不直接解開 Currency 驗證。M1-03 其餘部分及 M1-04 之後、M2、M3 CORE 尚未完成；目前沒有需使用者先處理的主機開發阻礙。



## 2026-09-27 接續：共用日期、繁體中文月曆與可見錯誤

[PR #52：背景鎖定](https://github.com/swz0103/ExpenseTracker-V2/pull/52) 已完整上傳，SHA `448e4093c138eafbd373330a1ea287e7ae8774ff`。本批 `feat/business-date-input` 從此版本接續；[共用日期輸入](business-date-input.md)已接入起始日期與日常收支，保留手動文字及加密草稿，確認月曆才套用。日期運算不經時區轉換，閏日與 0001～9999 年保留；鎖定後的月曆與排隊結果取消。共用日期／計算器及 App 名稱接入繁體中文 ARB，尚非全 App 語系化。

回查修正 320 × 740、文字 3.2 倍時的月曆標題溢出，以及無效表單送出後提示留在畫面外。現在操作失敗回到可見提示、保留輸入，舊 session 的錯誤不能跨鎖定出現。新日期測試改為等實際草稿保存完成再讀取；重複點擊測試確認兩次命中，不放寬忙碌或去重規則。

**131 個獨立本機案例已驗證，新增 9 個。** 完整 App 執行先得到 114 通過／2 失敗，修正後所有 29 個畫面／呈現／日曆案例再通過；加上未改動的 87 個 App 案例與 15 個架構案例計算，重跑沒有累加。完整 App 保留舊版升級、中斷、草稿、商家／Tag 歷史、隱私與雙路加密還原；新日期案例另在刪除合成來源 DB 與 vault keys 後核對密碼／救援獨立還原及完整 snapshot bytes。[證據](test-results/business-date-host-2026-09-27.json)列出每段執行與來源指紋。

0.8.0+12 ARM64 debug 封裝核對通過，資訊見[安裝包紀錄](installable-preview.md)。Schema 7／snapshot 6／manual-entry-v1 未改；未重跑相同核心五千筆或十八套件，沿用已完成證據。Actions 未啟用、手機未操作、main 未合併；需雲端 gate 的分支暫不收斂。完整時間／時區、全 App 語系化與其他 CORE 仍未完成。

下一完整流程接 M1-03 同幣轉帳。已回查 Domain 有規則，但 session、容量限制、單 leg 清單與草稿仍需同步接入；須處理雙帳戶原子提交、費用、可重啟的凍結命令、資料相容及還原驗證，不能只打開 UI。跨幣與實際匯率依既定順序接續。

## 2026-09-27 接續：背景鎖定與浮層取消

[PR #51：金額計算器](https://github.com/swz0103/ExpenseTracker-V2/pull/51) 已提交並上傳，完整 SHA `fe1f96df808a2de9622541181235c299c12fc230`；本機、遠端、PR 相符，所有本機分支無未上傳提交。接著從此版本建立 `fix/lock-transient-routes`，完成同次執行的第二項流程。

回查並重現確認窗、帳戶下拉及標籤選單在鎖定後殘留，以及已排隊確認仍捨棄草稿。現在[鎖定時隱藏並取消浮層](lock-transient-routes.md)，包括正在退場的內容；草稿確認必須符合當前 view epoch，舊回呼不能跨鎖定執行。已接受寫入仍按原規則完成，正式帳本不受影響。

新增 4 個有效生命週期案例修正前均可重現失敗，修正後全部通過；再完整回歸原有 17 個 UI／呈現案例，合計 **21 個獨立相關案例**通過。格式、靜態分析、實際架構掃描及 0.7.1+11 ARM64 封裝核對通過。[證據](test-results/lock-routes-host-2026-09-27.json)保留失敗重現、測試序列修正與最終來源指紋。

本批沒有修改金額、Ledger、加密、schema 7／snapshot 6 或容量；沿用 PR #51 的完整 18 套件及五千筆證據，不冒充再次執行。兩個 workflow 仍停用，雲端未執行；未操作手機、未合併 main、未正式發版。需雲端 gate 的分支不收斂。

下一項依 M1-02 接日期輸入、共用表單及 i18n；M1-03 之後的轉帳／多幣別等既定 CORE 與 M2、M3 繼續保留。實際 Android 生命週期、Recent Apps 與平台安全／還原 gate 仍待使用者回來。

## 2026-09-27 接續：金額計算器與完整本機回歸

上一批 [PR #50：金額遮罩](https://github.com/swz0103/ExpenseTracker-V2/pull/50) 已上傳，完整 SHA `35de4aae1df0adb1192314e117ce5c87dcc8a408`；本批 `feat/amount-calculator` 從該提交接續。

[金額欄計算器](amount-calculator.md)完成期初與收支的四則／括號／百分比、精確計算、結果提示及明確套用。原算式可作加密草稿並在鎖定後恢復；計算不自行入帳，套用仍沿既有驗證及唯一性流程。回查將 Money 與 FX 的重複取位演算法統一，嚴格手動輸入規則不變。

完整 **18 套件／684 個獨立本機案例**通過，新增 15 個；格式、分析、架構掃描、五個原生 worker 建置均通過。[主機證據](test-results/amount-calculator-host-2026-09-27.json)列出每套件及新舊驗證範圍，沒有重複計數。全量後修正 UI 超長貼上截短，重跑相關 18 項先得 17 通過、1 個舊分類選單定位失敗；補上捲動排版等待與命中斷言後，該案例單獨通過。

額外 **5,000 事件／4,999 筆計算／1,667 筆明示取位**，各 256 個分類／Tag／Merchant、歷史與滿額重送通過；先刪來源合成 DB／key，再以密碼與救援分別在乾淨 profile 還原，核對完整 bytes、獨立餘額及重開。[原始結果](test-results/amount-calculator-scale-2026-09-27.json)保留大小與耗時，不把主機耗時當實機效能保證。

0.7.0+10 ARM64 debug APK 已完成封裝核對，詳見[開發包](installable-preview.md)。Schema 7、snapshot 6、草稿格式與容量不變。兩個 workflow 保持停用，本批雲端未執行；手機未操作、main 未合併，需雲端 gate 的舊分支不收斂。

M1-02 尚未全部完成。下一步先驗證鎖定時仍開啟的確認窗／選單能否安全取消，再接共用表單、日期與 i18n；M1 其餘日常功能、M2、M3 仍依既定順序接續。

## 2026-09-27 接續：金額遮罩與基本無障礙

上一個完整流程 [PR #49：手動收支草稿](https://github.com/swz0103/ExpenseTracker-V2/pull/49) 已提交並上傳，完整 SHA `16aba28d15a819a5c24b5249e3d853064151f87b`；本機、遠端、PR 相符，所有本機分支無未上傳提交。接著從該版本建立 `feat/privacy-presentation`，在同次執行完成第二個使用流程。

[金額遮罩](privacy-presentation.md) 統一帳戶／交易金額及朗讀標籤；偏好依 profile 保存，顯示前讀回驗證，失敗時維持本次使用期間的隱藏。目的帳本還原保留目的裝置偏好，財務 snapshot 不變。帳戶／交易列表支援窄螢幕及較大文字，錯誤回饋加入朗讀提示。回查將重複的金額字串規則收斂到既有 Money.majorText。

本機 **114 個獨立案例**有通過結果（架構 15、App 99，新增 9）。完整 App 首輪 97 通過、2 個舊畫面定位失敗；改好捲動與 lazy widget 定位後，全部 14 個受影響 UI／呈現案例分批通過，原財務、備份 gate 與去重斷言均保留。[證據](test-results/privacy-presentation-host-2026-09-27.json) 列出各輪結果及最終來源指紋，不把重跑重複計數。程式格式、分析、最終架構掃描與 0.6.1+9 ARM64 封裝核對通過。

這一批不改 Ledger、schema 7、snapshot 6、加密或容量；原 5,000 筆與獨立程序中斷證據沿用，不宣稱本批重跑全部 17 套件。Actions 兩個 workflow 仍停用，沒有本批雲端 checks；手機未操作、main 未合併，需雲端 gate 的舊分支保持不收斂。

M1-02、RC-02、RC-15 仍有未完成部分。下一個完整流程接 [Q025 金額欄內建計算器](full-vision-baseline.md#q025)：明確計算後再套用金額、精確計算、輸入邊界／四則／括號／百分比、草稿與重試整合；接著收斂共用表單與 i18n，並繼續既定 M1 其餘、M2、M3。實機 TalkBack、Recent Apps 與裝置驗收仍等使用者回來。

使用者於 2026-09-26 授權：逐項實作，每項完成後開下一分支，直到回來驗收或完成所有既定階段。採依賴分支與堆疊 PR，驗證完成後才推進；不自行合併 main。自動接續仍遵守 Android、加密、還原與 migration 等 gate，遇到阻礙先做不受影響的項目。

## 最新接續指示

2026-09-27 使用者明確要求開始動工、打開排程並邊做邊回報。已恢復原有排程為啟用，保留當時實際設定的每 20 分鐘接續；本輪直接開發，不等待下一次排程。不操作手機、不啟動 Actions、不合併 main，仍依 CORE 範圍逐項完成。

2026-09-27 前次核對上傳與隔離：已唯讀確認 V2 為獨立私人 repository、origin 只指向 V2，舊版與 V2 的 Android 身份不同；同步遠端後，當時最新功能 `1424c58`／PR #43 及所有本機分支提交皆已被遠端涵蓋。完整規則見[交付與效率文件](github-delivery-policy.md)。前次讀到排程為暫停、每 50 分鐘，當時未自行更動；本輪已依最新明確授權恢復，並保留最新設定的每 20 分鐘，以上方紀錄為準。

使用者要求不以試用版為停止點，繼續完整 CORE 直到其回來，屆時再安排實機。每項開發同時回查既有模組並做相關回歸；逐批收斂已涵蓋且驗證的 GitHub 分支，main 不自行合併。自動接續已恢復。[分支收斂紀錄](branch-consolidation.md)保存 exact SHA 與原 PR 對照。

## 分支與交付

2026-09-27 本批 feat/manual-entry-drafts 接續安全複製 PR #48（a6ef5c834e0156c815bf3777dd5942bd2e69f427），完成[手動收支草稿與恢復](manual-entry-drafts.md)：逐次加密保存、重新開啟／鎖定後繼續、明確捨棄、提交前固定同一命令及提交後中斷防重複。未完成草稿不影響正式餘額；目前備份、還原及升級前須先處理草稿。schema 7／snapshot 6 未變；完整 Financial Inbox 與通用表單狀態框架未宣稱完成。

本機 **5 個受影響套件、162 項不重複案例**通過，新增 28 項，含完整 App 回歸及最後保存提示修正後的畫面回歸；另有 **4 個真正程序退出**後的重開驗證通過。首輪完整 App 揭露的升級 publishing 接續回歸已修正，回查另重現並修正保存中提示未即時刷新；失敗／重試、備份還原與三個還原鎖定時機均覆蓋。[驗證清單](test-results/manual-entry-drafts-host-2026-09-27.json)明列受測檔案指紋、重驗與沿用證據，不將未跑的其餘套件或雲端當作通過。

0.6.0+8 ARM64 開發包已建置並核對身份、簽章及備份禁用，詳見[安裝包紀錄](installable-preview.md)。本批以獨立 PR 依賴 feat/safe-posting-copy；Actions 維持停用、不操作手機、不合併 main，未通過雲端 gate 的舊分支不刪除。接續 M1-02 隱私遮罩／基本無障礙與其餘日常表單能力；其他 M1、M2、M3 CORE 仍未完成。


商家批次上傳已核對：本機／遠端／[PR #47](https://github.com/swz0103/ExpenseTracker-V2/pull/47) 為 `053b476342b0929f974d1541cc52f1b77e30d128`，所有本機分支未上傳提交為 0，main 仍為 `d0d39e1de32774aca319b8fed0cc9ee288cbb94a`。PR 已改為可審查，未合併；只寫入私人 V2。

同輪已接續 `feat/safe-posting-copy`，完成[安全複製收入／支出](safe-posting-copy.md)：只沿用目前可用的欄位，金額日期重填，封存／合併須重新選擇。73 項相關回歸（Ledger 7／完整 App 66）、格式、分析及架構掃描通過，新增 6 項；多帳戶與新舊金融事件皆核對。[本批證據](test-results/safe-posting-copy-host-2026-09-27.json)區分重驗及沿用資料。`0.5.1+7` ARM64 debug APK 建置及身份、簽章、備份禁用核對通過，[安裝包紀錄](installable-preview.md)保存 hash。以獨立 PR 依賴 #47；接下來處理表單持久草稿與恢復，以及 M1-02 其餘操作／隱私／無障礙，不能把安全複製當成完整 M1-02。沒有修改商家批次已驗證的保存、schema、備份或還原程式。

2026-09-27 商家／別名完整流程（本機驗證完成）：沿 `feat/transaction-merchants`／[PR #47](https://github.com/swz0103/ExpenseTracker-V2/pull/47) 接續 #46。保留 Domain 起始提交 `d17dec5177db67bab8bc5daf57431f01c660dfa4`，同一 PR 完成商家管理、別名增刪、候選手動確認、交易選取與原始歷史引用；新增／改名／封存／合併不改原交易金額。[完整接口](transaction-merchants.md)。

新帳本 schema 7／snapshot 6；舊 V2 schema 3／4／5／6 經明確確認，沿雙憑證安全備份與暫存驗證逐步升級。分類、Tag、商家與金額同一交易提交；未選商家的既有 receipt bytes 不變。新資料納入原有 50,000 列／16 MiB 限制，工作階段另限 256 商家／1,024 次商家異動。回查把損壞來源的重複商家身份納入拒絕驗證。

完整 **16 套件、626 項獨有本機案例**通過，相對 #46 新增 64 項（含起始提交的 Domain 15 項）；本次接續新增 49 項。格式、分析、實際依賴掃描、五個原生 worker 重建、11 處真正程序中斷、4 處 App 升級例外、360×740 畫面操作及乾淨還原均涵蓋。[清單](test-results/transaction-merchants-host-2026-09-27.json)保留一項既有 Tag 還原在並行測試時逾時的失敗；相同版本單獨重跑通過，未延長 timeout、未改斷言，不重複計數。

兩組獨立五千筆[新帳本](test-results/transaction-merchants-scale-2026-09-27.json)／[已滿舊帳本升級](test-results/transaction-merchants-upgrade-scale-2026-09-27.json)通過。新帳本 4,999 個商家及 4,999 個 Tag 引用；舊帳本逐表保留原引用，升級後不冒充已為原交易補商家。各案 256 商家／1,024 次變更、5,004 次重送，刪除合成來源 DB 與 vault keys 後的密碼及救援各自還原、完整 bytes／獨立餘額／歷史版本／重開核對通過。

雲端未執行、手機未操作、main 未合併，待雲端 gate 的分支不收斂刪除。M1-02 其餘日常錄入及其他 M1／M2／M3 CORE 仍未完成；`0.5.0+6` ARM64 開發包建置、身份、簽章及備份禁用核對通過，[安裝包紀錄](installable-preview.md)保留雜湊。完成上傳核對後，下一分支接「再記一筆類似交易」安全複製，再續表單草稿與其餘既定項目。

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
