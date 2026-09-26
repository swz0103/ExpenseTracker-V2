# 逐項實作進度

使用者於 2026-09-26 授權：逐項實作，每項完成後開下一分支，直到回來驗收或完成所有既定階段。採依賴分支與堆疊 PR，驗證完成後才推進；不自行合併 main。自動接續仍遵守 Android、加密、還原與 migration 等 gate，遇到阻礙先做不受影響的項目。

## 分支與交付

- 架構與 SQLite 原型：`docs/architecture-and-implementation-plan`，PR #1；11 項測試及 GitHub CI 已通過，基準提交 `3712cfe781e8ee2725594cb9ee52db8f58fccef3`。原型只驗證 host transaction 機制。
- 金額值型別：`feat/foundation-money`，PR #2，基於 PR #1，提交 `95b6f3a`。10 項新測試與 11 項既有原型測試在 GitHub 通過。Money／Currency、嚴格精度、整數溢位、版本化 JSON、量化與尾差分攤已完成。
- 身份與日期：`feat/foundation-identity-time`，基於 PR #2。UUID v7、不同型別的帳本／操作身份、嚴格日曆日期與 UTC instant。新 7 項測試與原有 10 項值型別測試在本機通過；遠端狀態見此分支 PR。
- 下一項：Accounts 的身份、生命週期與寫入參與規則，再接 Ledger／共用 transaction adapters。

## 尚未完成的 gate

整體階段 0／1 尚未完成，Architecture Baseline 仍 rc1。Android 裝置沒有可用測試目標；加密資料庫、密碼／救援金鑰兩條乾淨還原、migration 故障與 provider 路線尚待實測。M1／M2／M3 未完成，不把套件單元測試冒充可用 App。

詳細順序見[實作計畫](implementation-plan.md)，財務契約見[工程規格](foundation-contracts.md)，驗收案例見[案例清單](foundation-acceptance.md)。
