# 逐項實作進度

使用者於 2026-09-26 授權：逐項實作，每項完成後開下一分支，直到回來驗收或完成所有既定階段。採依賴分支與堆疊 PR，驗證完成後才推進；不自行合併 main。自動接續仍遵守 Android、加密、還原與 migration 等 gate，遇到阻礙先做不受影響的項目。

## 分支與交付

- 架構與 SQLite 原型：`docs/architecture-and-implementation-plan`，PR #1；11 項測試及 GitHub CI 已通過，基準提交 `3712cfe781e8ee2725594cb9ee52db8f58fccef3`。原型只驗證 host transaction 機制。
- 金額值型別：`feat/foundation-money`，基於 PR #1。Money／Currency、嚴格精度輸入、整數溢位、版本化字串 JSON、half-away-from-zero 量化與最後份吸收尾差。測試結果以該分支 CI 為準。
- 下一項：身份與業務日期值型別，再接 Accounts／Ledger 的資料與共用 transaction adapters。

## 尚未完成的 gate

整體階段 0／1 尚未完成，Architecture Baseline 仍 rc1。Android 裝置沒有可用測試目標；加密資料庫、密碼／救援金鑰兩條乾淨還原、migration 故障與 provider 路線尚待實測。M1／M2／M3 未完成，不把套件單元測試冒充可用 App。

詳細順序見[實作計畫](implementation-plan.md)，財務契約見[工程規格](foundation-contracts.md)，驗收案例見[案例清單](foundation-acceptance.md)。
