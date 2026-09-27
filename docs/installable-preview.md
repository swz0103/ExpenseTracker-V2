# 開發安裝包與歷史驗收紀錄

## 0.14.0 交易活動查閱

**2026-09-28 最新開發包**：0.14.0+18 接入[交易活動查閱](transaction-activity.md)；沿用 schema 10／snapshot 9。

- 本機檔案：`build/deliverables/ExpenseTracker-V2-development-0.14.0-arm64.apk`，94,622,535 bytes。
- SHA-256：`bdaac9f1eab1f457bddb50a6e8dda5f11a26b859ad9562f4c84b294e3463635d`。
- App ID `dev.expensetracker.preview`、versionCode 18／versionName 0.14.0、min API 24、target API 36、APK v2 簽章、`allowBackup=false`、ARM64 Flutter／SQLCipher 核對通過。
- [受影響 3 套件／54 個主機案例](test-results/transaction-activity-host-2026-09-28.json)通過；完整基礎與大量／中斷測試沿用 0.13.0，沒有冒稱新跑。
- 本機 debug 包未安裝、未發布、未上傳 APK 或金鑰；雲端、實機與其餘 CORE gate 保留。

## 0.13.0 原支出退款

**2026-09-28 歷史開發包**：0.13.0+17 接入[部分／全額退款](refunds.md)、原支出追溯、跨幣實收、可恢復送出及 V2 schema 9 → 10 安全升級。

- 本機檔案：`build/deliverables/ExpenseTracker-V2-development-0.13.0-arm64.apk`，94,617,771 bytes。
- SHA-256：`4132ae68490ba36a48130162448da674a64b5b64989ccc3c27c85d72089620cf`。
- App ID `dev.expensetracker.preview`、versionCode 17／versionName 0.13.0、min API 24、target API 36、APK v2 簽章、`allowBackup=false` 與 ARM64 Flutter／SQLCipher 核心核對通過。
- [完整 18 套件／810 個主機案例](test-results/refunds-host-2026-09-28.json)、[5,000 事件與雙路乾淨還原](test-results/refunds-scale-2026-09-28.json)、[四處草稿程序退出](test-results/refunds-process-2026-09-28.json)通過。
- 只留本機 debug 包，未安裝、未正式發布、未上傳 APK／金鑰。雲端與實機及其餘 CORE gate 保留。

## 0.12.0 拆分分配與確認

**2026-09-28 歷史開發包**：0.12.0+16 接入[平均／百分比／固定比例分配](split-allocation-assist.md)，預覽後明確確認才更新草稿；沿用 schema 9／snapshot 8。

- 本機檔案：`build/deliverables/ExpenseTracker-V2-development-0.12.0-arm64.apk`，94,576,339 bytes。
- SHA-256：`63943d02135bc69762a8cb2f296eefa1fe9c8cedf9965f6a6e70dcb7bed8b207`。
- App ID `dev.expensetracker.preview`、versionCode 16／versionName 0.12.0、min API 24、target API 36、APK v2 簽章、`allowBackup=false`、ARM64 Flutter／SQLCipher 核心均核對。
- [3 套件／177 個本機案例](test-results/split-allocation-assist-host-2026-09-28.json)含完整 App 回歸與 3,000 組比例 oracle；三種模式的重啟、重試與雙路乾淨還原通過。底層大量及程序退出證據沿用未修改的 0.11.0，不計作新跑。
- 僅本機 debug 包，未安裝、未發布、未上傳 APK／金鑰；雲端、實機及其餘 CORE gate 保留。

## 0.11.0 多分類拆分與可恢復草稿

**2026-09-28 歷史開發包**：0.11.0+15 接入[多分類拆分](split-entry-drafts.md)、各項金額明細、隱私遮罩與複製流程，修正分類收據容量；沿用 schema 9／snapshot 8。

- 本機檔案：`build/deliverables/ExpenseTracker-V2-development-0.11.0-arm64.apk`，94,563,263 bytes。
- SHA-256：`6b50e4b97ffe8cac11ab8d3d50cc4c2e456718f2b34fa03638c5d2c78a2ce255`。
- App ID `dev.expensetracker.preview`、versionCode 15／versionName 0.11.0、min API 24、target API 36、APK v2 簽章、`allowBackup=false` 及 ARM64 Flutter／SQLCipher 核心均核對。
- [受影響 8 套件／515 個主機案例](test-results/split-entry-host-2026-09-28.json)、[5,000 事件／雙路乾淨還原](test-results/split-entry-scale-2026-09-28.json)、[4 處程序退出](test-results/split-entry-process-2026-09-28.json)通過；執行範圍與初期修正明列證據，不將重跑重複計數。
- 只保留本機 debug 包，未安裝、未發布、未上傳 APK／金鑰。雲端、實機及剩餘 CORE gate 保留。

## 0.10.0 跨幣轉帳與實際本金

**2026-09-28 歷史開發包**：0.10.0+14 接入[跨幣轉帳](cross-currency-transfers.md)、精確實際比例、雙金額可恢復草稿、schema 8 → 9 安全升級及列表讀取優化。

- 本機檔案：`build/deliverables/ExpenseTracker-V2-development-0.10.0-arm64.apk`，94,550,703 bytes。
- SHA-256：`3b5250a7b0ab6816e2efd2a54129ffced467dc58594f2b712808b3bed3540643`。
- App ID `dev.expensetracker.preview`、versionCode 14／versionName 0.10.0、min API 24、target API 36、APK v2 簽章、`allowBackup=false`、ARM64 Flutter／SQLCipher 核心均核對通過。
- [完整 18 套件／754 項與最終列表回歸](test-results/cross-currency-transfers-host-2026-09-28.json)、[5,000 事件雙路乾淨還原](test-results/cross-currency-transfers-scale-2026-09-28.json)、[4 處草稿程序中止](test-results/cross-currency-transfers-process-2026-09-28.json)通過；11 處升級中止列於主機案例內。
- 僅本機 debug 封裝，未操作手機、未正式發布、未上傳 APK／金鑰。雲端未執行，其餘 CORE 及實機 gate 保留。


## 0.9.0 同幣轉帳與來源手續費

**2026-09-28 歷史開發包**：0.9.0+13 加入[同幣轉帳](same-currency-transfers.md)、獨立來源費用、可恢復送出、雙帳戶明細及 schema 7 → 8 安全升級。仍是 V2 內部格式，沒有舊 App 匯入。

- 本機檔案：`build/deliverables/ExpenseTracker-V2-development-0.9.0-arm64.apk`，94,543,471 bytes。
- SHA-256：`152ad57b725a73b437003478417aae22b4f1da246ce66b45bdbdcf27ec1498c4`。
- App ID `dev.expensetracker.preview`、versionCode 13／versionName 0.9.0、min API 24、target API 36、APK v2 簽章、`allowBackup=false`、ARM64 Flutter／SQLCipher 核心均核對通過。
- [完整 18 套件／723 項及最後提示修正回歸](test-results/same-currency-transfers-host-2026-09-28.json)、[5,000 事件雙路乾淨還原](test-results/same-currency-transfers-scale-2026-09-28.json)、[4 處實際草稿程序中止](test-results/same-currency-transfers-process-2026-09-28.json)通過。11 處升級程序中止已包含在主機套件內。
- 只有本機 debug 封裝，未操作手機、未正式發布、未上傳 APK 或簽章金鑰。雲端未執行；其餘 CORE 與實機安全 gate 持續保留。


## 0.8.0 共用日期與繁體中文月曆

**2026-09-27 歷史開發包**：0.8.0+12 加入[共用日期輸入](business-date-input.md)、日期／計算器語系資源及失敗後可見提示。資料格式與金鑰命名空間保持既有 V2 規則。

- 本機檔案：`build/deliverables/ExpenseTracker-V2-development-0.8.0-arm64.apk`，94,525,527 bytes。
- SHA-256：`6a2ed71b92711ab22d08c971247c8fcf3f44e2b6c13dacc92ad8c4fbd409ca3c`。
- App ID `dev.expensetracker.preview`；versionCode 12／versionName 0.8.0、min API 24、target API 36、APK v2 簽章、`allowBackup=false` 及 ARM64 Flutter／SQLCipher 核心核對通過。
- [131 個獨立本機案例](test-results/business-date-host-2026-09-27.json)以完整 App 回歸及修正後全部畫面回歸組合驗證，包含日期、舊版 V2 升級與雙路乾淨還原；不是同一次最終完整 18 套件重跑。
- 僅本機 debug 建置，沒有操作手機、正式發布或上傳二進位／簽章金鑰。未執行雲端，剩餘安全與里程碑 gate 不變。

## 0.7.1 背景鎖定開發包

**2026-09-27 歷史開發包**：0.7.1+11 修正[背景鎖定的確認窗與選單](lock-transient-routes.md)，以及舊確認回呼繼續捨棄草稿的時序。沿用 0.7.0 計算器與資料格式。

- 本機檔案：`build/deliverables/ExpenseTracker-V2-development-0.7.1-arm64.apk`，92,809,235 bytes。
- SHA-256：`5485f3c512a61de8b075968c6b4f8b487a3d060894655c37ae3eae6099490165`。
- App ID `dev.expensetracker.preview`，versionCode 11／versionName 0.7.1；min API 24、target API 36、APK v2 簽章、`allowBackup=false` 核對通過。Flutter／SQLCipher 核心僅 ARM64。
- [21 項本機相關回歸](test-results/lock-routes-host-2026-09-27.json)通過；完整保存／計算及大量資料證據沿用下方 0.7.0。
- 僅本機 debug 封裝，未安裝、未實機驗收、未正式發布；二進位及簽章金鑰不加入 Git。

## 0.7.0 計算器開發包

**2026-09-27 歷史開發包**：0.7.0+10 加入[金額欄計算器](amount-calculator.md)。期初與收支支援明確計算後套用，原算式可保留於草稿；沿用隱私遮罩與既有入帳保護，schema 7／snapshot 6 不變。

- 本機檔案：`build/deliverables/ExpenseTracker-V2-development-0.7.0-arm64.apk`，92,802,419 bytes。
- SHA-256：`14b939ccba250eb501ce8ef2418b4299552a263a7563228410e64a272841ba06`。
- App ID `dev.expensetracker.preview`，versionCode 10／versionName 0.7.0；min API 24、target API 36、APK v2 簽章、`allowBackup=false` 核對通過。
- Flutter／SQLCipher 核心僅 ARM64。[完整 18 套件 684 項與最終 UI 修正回歸](test-results/amount-calculator-host-2026-09-27.json)及[五千筆資料](test-results/amount-calculator-scale-2026-09-27.json)通過。
- 僅本機 debug 封裝，未安裝、未實機驗收、未正式發布；APK 與簽章金鑰不提交 Git。其餘既定 CORE 持續接續。

## 0.6.1 金額遮罩開發包

**2026-09-27 歷史開發包**：0.6.1+9 加入[金額遮罩與基本無障礙](privacy-presentation.md)，沿用 0.6.0 的手動收支草稿。財務資料仍為 schema 7／snapshot 6。只完成主機驗證，仍持續開發既定 CORE。

- 本機檔案：`build/deliverables/ExpenseTracker-V2-development-0.6.1-arm64.apk`，92,794,611 bytes。
- SHA-256：`a076f12d262480370a72311d6958eb6b6a071138a816958d72e0a843f4ecf8d8`。
- App ID `dev.expensetracker.preview`，versionCode 9／versionName 0.6.1；min API 24、target API 36、APK v2 簽章、`allowBackup=false` 均核對通過。
- Flutter／SQLCipher 核心僅 ARM64；其他 JNI 架構檔不代表非 ARM64 App 支援。
- [114 個本機回歸案例](test-results/privacy-presentation-host-2026-09-27.json)有通過結果；未執行雲端或實機，未正式發版。APK 與簽章金鑰不加入 Git。

## 0.6.0 草稿開發包

**2026-09-27 歷史開發包**：0.6.0+8 加入[手動收支草稿與恢復](manual-entry-drafts.md)。金額／日期可保留未完成文字，逐次加密保存；入帳前固定命令，重開後不重複入帳。草稿須先完成或明確捨棄才可匯出目前備份、還原或升級。正式帳本仍為 schema 7／snapshot 6。

- 本機檔案：build/deliverables/ExpenseTracker-V2-development-0.6.0-arm64.apk，92,787,079 bytes。
- SHA-256：945b4f7137dfb618da52aae3572ed22e382156a4e32e9ec9f221f3e6b29c9f38。
- App ID dev.expensetracker.preview，versionCode 8／versionName 0.6.0；min API 24、target API 36、APK v2 簽章、allowBackup=false。Flutter／SQLCipher 主程式庫為 ARM64。
- [162 項相關回歸](test-results/manual-entry-drafts-host-2026-09-27.json)與[四次程序退出恢復](test-results/manual-entry-drafts-process-2026-09-27.json)通過；其他大量財務資料證據沿用前批，未冒充本輪重跑。
- 僅本機 debug 封裝，未安裝、未正式發版、未消耗 Actions。APK 與金鑰均不進 Git；其餘既定 CORE 持續開發。

## 0.5.1 安全複製開發包

**2026-09-27 歷史開發包**：`0.5.1+7` 新增[安全複製收支](safe-posting-copy.md)，金額日期重填、封存合併不自動轉向、核對非預設來源帳戶；schema 7／snapshot 6 不變。[本批 73 項回歸](test-results/safe-posting-copy-host-2026-09-27.json)與封裝核對通過，商家完整整合及大量資料證據沿用下方 0.5.0。

- 本機檔名：`build/deliverables/ExpenseTracker-V2-development-0.5.1-arm64.apk`；92,748,879 bytes。
- SHA-256：`6fb345685aa12428402b56bb1a9913d2c9e9c2647f198fbf9a48736a66b2bd09`。
- App ID `dev.expensetracker.preview`，versionCode 7／versionName 0.5.1；最低 API 24、target API 36、APK v2 簽章通過、`allowBackup=false`。Flutter／SQLCipher 主程式庫為 ARM64。
- 僅本機 debug 封裝，尚未安裝或實機驗收，沒有正式發版；APK 與金鑰不提交 Git。既定 CORE 持續開發，不以可安裝作為完成點。

## 0.5.0 商家開發包

**2026-09-27 歷史開發包**：`0.5.0+6` 加入商家管理、基本別名、候選確認與交易引用，舊 V2 帳本沿安全備份逐步升級至 schema 7。完整 16 套件 626 項本機案例及兩組各 5,000 筆資料驗證通過，詳見[清單](test-results/transaction-merchants-host-2026-09-27.json)及[商家流程](transaction-merchants.md)。

- 本機檔名：`build/deliverables/ExpenseTracker-V2-development-0.5.0-arm64.apk`；92,748,111 bytes。
- SHA-256：`f644d39c68ac0cc15694ea43a12a9ae19daaa78bcece37dc3c3ec10af2fbbba1`。
- App ID `dev.expensetracker.preview`，versionCode 6／versionName 0.5.0；最低 API 24、target API 36，APK v2 簽章核對通過，`allowBackup=false`。
- Flutter／SQLCipher 程式庫為 ARM64；其他 JNI 檔案不代表非 ARM64 裝置支援。僅做本機 debug 封裝，沒有安裝、實機驗收或正式發版；APK 與金鑰不提交 Git。

## 0.4.0 標籤開發包

**2026-09-27 歷史開發包**：`0.4.0+5` 加入交易 Tag、管理及歷史引用，既有 V2 帳本可經安全備份逐步升級至 schema 6。15 套件 562 項本機回歸、兩組獨立 5,000 筆資料流程及封裝檢查通過，詳見[驗證清單](test-results/transaction-tags-host-2026-09-27.json)及[Tag 流程](transaction-tags.md)。仍持續開發既定 CORE，不以可安裝為停止點。

- 本機檔名：`build/deliverables/ExpenseTracker-V2-development-0.4.0-arm64.apk`；92,696,203 bytes。
- SHA-256：`86f7de423957a0ec0310079bbdfeb39e3820289c28b1ed63e6d1c5a236970e15`。
- App ID `dev.expensetracker.preview`，versionCode 5／versionName 0.4.0；最低 API 24、target API 36，APK v2 簽章驗證成功，`allowBackup=false`。
- Flutter／SQLCipher 主程式庫為 ARM64。只做本機 debug 封裝，未安裝、未實機驗收、未正式發版；二進位及簽章金鑰不提交 Git。與舊 App 的身份、私人資料及金鑰命名空間保持分開。

## 0.3.1 分類管理開發包

**2026-09-27 歷史開發包**：`0.3.1+4` 接續下方 0.3.0，加入分類搬移與明確確認的合併。完整 36 項 App 回歸與封裝核對通過，範圍及底層沿用證據見[本批驗證清單](test-results/category-management-host-2026-09-27.json)。仍持續開發既定 CORE，不以可安裝為停止點。

- 本機檔名：`build/deliverables/ExpenseTracker-V2-development-0.3.1-arm64.apk`；92,650,915 bytes。
- SHA-256：`7ec418b51864e896dd512faf9b16745e9ea8880c46dbc274020141d817c4e7ea`。
- App ID `dev.expensetracker.preview`，versionCode 4／versionName 0.3.1；最低 API 24、target API 36，APK v2 簽章驗證成功，`allowBackup=false`。
- Flutter／SQLCipher 主程式庫為 ARM64。僅完成本機 debug 封裝；未安裝、未實機驗收、未公開發布，二進位及簽章金鑰不提交 Git。

## 0.3.0 分類與安全升級開發包

**2026-09-27 後續開發包**：本頁下方 0.2.0 為歷史驗證紀錄。新增分類與安全升級的 `0.3.0+3` 已完成本機 debug 建置及封裝核對，範圍見 [App 分類](app-categories.md)，整體主機驗證以[最新進度](work-progress.md)為準；不以此安裝包作為完整 CORE 的停止點。

- 本機檔名：`build/deliverables/ExpenseTracker-V2-development-0.3.0-arm64.apk`；92,648,059 bytes。
- SHA-256：`0022db94b55d45baa0398056d50178b03dcfe1eee9a6e2921a3d4017a0c32a58`。
- App ID 仍為 `dev.expensetracker.preview`，versionCode 3／versionName 0.3.0；最低 API 24、target API 36，APK v2 簽章驗證成功，`allowBackup=false`。
- Flutter／SQLCipher 主程式庫僅包含 ARM64；其他 JNI 架構檔案不代表此包可供非 ARM64 手機使用。
- 尚未安裝或進行本批手機驗收，未正式發版。二進位保留在本機，不把它或簽章金鑰提交 Git；程式、測試與驗證紀錄走私人 V2 repository。

## 0.2.0 歷史驗證範圍

以下僅記錄 0.2.0 當時狀態：debug APK 已建置、簽章及封裝核對通過；大規模測試完成。當時 CI 結果見 PR #31 checks，測試方法與原始紀錄見[驗證報告](preview-validation-report.md)。不可將這些雲端 checks 視為後續 0.3.x 版本已通過雲端或實機驗收。

## 安裝包識別

- 檔名：`ExpenseTracker-V2-preview-0.2.0-arm64.apk`，本機專案的 `build/deliverables/` 目錄。二進位檔未提交 Git、未公開發布。
- 版本：`0.2.0+2`；App ID `dev.expensetracker.preview`；最低 API 24、target API 36。
- 大小：116,209,955 bytes（約 110.8 MiB）。
- SHA-256：`bdb0f3f5d7e028cac3ceedb2b775df38ff397c3e1627a9b718b7ff0274663f84`。
- Android debug 簽章的 APK v2 驗證通過；manifest 的 `allowBackup=false`。Flutter 與 SQLCipher 原生程式庫均為 ARM64；相依套件另附其他架構的 JNI 檔案，不代表此包支援那些裝置。

這是本機建置產物的 hash；其他電腦重新建置可能因 debug 簽章等差異產生不同 hash。原始碼交付於 `test/preview-large-scale`，依賴 PR #30。

## 試用範圍

這是獨立的「記帳 V2 試用版」，App ID `dev.expensetracker.preview`。支援 Android 7.0／API 24 以上的 ARM64 裝置；側載 debug APK，沒有正式上架或發版。它不覆蓋「記帳 V2 地基驗證」原型。

可建立現金／銀行帳戶、期初餘額、收入／支出、日期、帳戶餘額與交易列表；包含離開前景鎖定、加密備份及密碼／救援文字還原。每個帳本最多 32 個帳戶及 5,000 筆交易（含期初）。

分類、商家、Tag、修改／刪除、退款、轉帳、FX、報表、信用卡、投資及完整 migration 協調尚未交付。原本的[完整規劃](implementation-plan.md)保留；這個版本不是整個 M1／M2／M3 完成。

## 安裝方式

1. 將交付的 `.apk` 複製到手機，由檔案管理員開啟。若系統要求允許該檔案來源安裝，請在手機上自行確認。
2. 安裝後開啟「記帳 V2 試用版」。首次設定至少 12 個字元密碼，另外保存顯示的救援文字並確認。
3. 先使用下面的測試資料驗收。此版本是 debug 試用包；本輪未操作手機，Android 新 App 的平台檔案選擇器／安全儲存與整體操作仍待你驗收。

本輪不會自動安裝、操作或清除手機資料。不要為了重新測試而直接清除已有帳本；先匯出並確認備份。

## 簡單驗收流程

1. 新增「測試現金」，選 TWD，期初 `1000`，起始日期選不晚於收支日期。
2. 記一筆支出 `25.50`，帳戶餘額應為 `974.50`；再記收入 `100`，應為 `1074.50`。
3. 切到其他 App 再回來，應要求解鎖，畫面不直接顯示帳務。
4. 匯出加密備份，選擇你能再找到的儲存位置；顯示讀回核對成功後才算完成。系統檔案選擇器也會觸發鎖定，返回後請解鎖。
5. 再新增一筆測試收支，從剛才檔案還原，先用備份密碼，帳戶應回到 `1074.50`。再次匯入同一檔案時可選救援文字路徑核對。
6. 若需要取回還原前的內容，可先「匯出最近一次還原前副本」，再用相同還原流程匯入。每次還原會保留原世代及安全副本，尚無自動清理介面。

救援文字必須與已有加密備份搭配，不能單靠它找回未備份資料。匯入別次安裝的備份後，新匯出的備份使用**本次安裝設定**的密碼與救援文字，畫面也會先說明此規則。忘記本機密碼時，可在新的安裝先設定新密碼，再用原備份及其救援文字匯入；不要在唯一一份資料尚未備份時先移除 App。

## 開發者重建

使用本專案鎖定的 Flutter 3.47.5／Dart 3.13.4、既有 Android SDK／NDK，在 `prototypes/expense_preview`：

```powershell
flutter pub get --enforce-lockfile
flutter build apk --debug --target-platform android-arm64 --no-pub
```

預設產物為該目錄的 `build/app/outputs/flutter-apk/app-debug.apk`。Gradle 已禁止自動下載缺少的 SDK；release variant 關閉。沒有新增接受授權或簽署正式發版的步驟。

詳細驗證方法與容量保護見[測試報告](preview-validation-report.md)，平台尚未完成的門檻見[逐項進度](work-progress.md)。
