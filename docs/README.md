# 文件導覽

## 專案結構

依賴只能往下：App → 執行層 → 規則 → 基礎。

| 位置 | 內容 |
| --- | --- |
| `apps/expense_tracker/` | App（Flutter）：畫面、帳本模型（唯一的一份）、把每筆資料存進加密檔的 `TableJournal`。 |
| `infrastructure/vault/` | 金鑰、打開帳本、加密備份。 |
| `infrastructure/storage/` | SQLCipher 加密檔：每筆資料一列 JSON。 |
| `infrastructure/market/` | 證交所、櫃買中心收盤價與臺灣銀行牌告匯率。 |
| `packages/domain/` | 計算規則：持股成本、配股減資、台股費用、信用卡帳單週期與分期、CSV、電子發票。 |
| `packages/core/` | 金額、日期、匯率等值物件與時鐘。 |
| `tooling/` | `architecture_checks`（CI 的輕量檢查：core／domain 不碰平台、測試寫明預期的失敗、lockfile 版本一致、工作流程涵蓋每個模組）與本機檢查腳本 `run-host-checks.ps1`。 |
| `docs/` | 狀態、架構決策、設定說明；`images/` 是 README 的截圖。 |

## 文件

- [STATUS.md](STATUS.md)：功能、品質、已知限制與待辦。
- [plan-2026-11-13.md](plan-2026-11-13.md)：0.9 之後的審查回應、復盤與工作規劃。
- [ADR-0001](adr/0001-target-architecture.md)：模組、依賴方向、儲存、金鑰、備份的架構決策。
- [ADR-0002](adr/0002-feature-folders.md)：App 依功能分資料夾。
- 數值與資料來源：[精確匯率](architecture/exact-fx-values.md)、[行情與匯率來源（ADR-06）](architecture/provider-feasibility.md)。
- 設定：[Android 建置與簽章](delivery/android.md)。
- 各模組的行為說明在各自的 README（`packages/*`、`infrastructure/*`、`apps/expense_tracker`）。

舊 App 的規格、進度紀錄、審查報告與 2026-09 的產品需求初稿（原 `docs/history/`）已移除，需要時查 git 歷史。
