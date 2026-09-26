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
- 加密儲存接入原型：`feat/encrypted-storage-probe`，基於 PR #9。沿用 sqlite3 3.6.0 的 SQLCipher 4.19.0 community source；12 項本機測試完成加密開檔／重開、錯誤金鑰／損壞拒絕、交易、加密暫存與新金鑰還原、WAL、migration 及切換回滾。靜態分析通過，遠端狀態以 PR checks 為準。[原型紀錄](../prototypes/encrypted_storage/README.md)列明版本、來源與未通過項目，仍非 Android 安全 gate。
- 下一項：將加密還原放進獨立程序，補密碼／救援、切換中斷恢復及未知版本保護的組合測試；接著確認 Android 建置、裝置測試與 secure storage 接入條件。繼續處理不受裝置阻礙的 migration 故障案例與正式 Data packages／ports 邊界。平台加密 gate 未過前不交付日常使用版本。

## 尚未完成的 gate

整體階段 0／1 尚未完成，Architecture Baseline 仍 rc1。Android 裝置沒有可用測試目標；Android 加密資料庫／secure storage、密碼／救援金鑰兩條乾淨還原、完整 migration 故障與 provider 路線尚待實測。M1／M2／M3 未完成，不把 host 原型或套件單元測試冒充可用 App。

詳細順序見[實作計畫](implementation-plan.md)，財務契約見[工程規格](foundation-contracts.md)，驗收案例見[案例清單](foundation-acceptance.md)。
