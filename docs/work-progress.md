# 逐項實作進度

使用者於 2026-09-26 授權：逐項實作，每項完成後開下一分支，直到回來驗收或完成所有既定階段。採依賴分支與堆疊 PR，驗證完成後才推進；不自行合併 main。自動接續仍遵守 Android、加密、還原與 migration 等 gate，遇到阻礙先做不受影響的項目。

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
- DB／key 配對原型：`feat/storage-generation-probe`，基於 PR #14。SQLite 控制紀錄一次提交發布配對、加密 DB 內身份核對、舊組合保留與安裝去重；26 項新 host 測試通過，包含七處程序退出與跨程序競爭。詳見[原型範圍](../prototypes/storage_generation/README.md)。fixture key 是明文暫存檔，不能當作平台 secure storage；遠端結果以 PR checks 為準。
- 下一項：將世代 metadata 與實際 Ledger snapshot 以明確版本邊界整合，核對完整權威資料與財務 receipt；再接正式 key slot adapter、連線租約與 Android 裝置驗證。不放寬既有未知 schema 拒絕規則。裝置實測待測試手機連接並允許 USB 偵錯後接續。

## 尚未完成的 gate

整體階段 0／1 尚未完成，Architecture Baseline 仍 rc1。Android 裝置沒有可用測試目標；Android 加密資料庫／secure storage、密碼／救援金鑰兩條乾淨還原、完整 migration 故障與 provider 路線尚待實測。M1／M2／M3 未完成，不把 host 原型或套件單元測試冒充可用 App。

詳細順序見[實作計畫](implementation-plan.md)，財務契約見[工程規格](foundation-contracts.md)，驗收案例見[案例清單](foundation-acceptance.md)。
