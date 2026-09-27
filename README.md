# ExpenseTracker V2

Android 優先、Flutter、local-first 的個人財務管理 App。

持續開發完整 M1／M2／M3 CORE，並逐項回查、回歸與收斂分支。已有帳戶、收入／支出與加密備份還原的階段驗證入口及大量資料紀錄；實機等使用者安排，不以既有試用 APK 為停止點。完整安全／升級 gate 仍未完成，Architecture Baseline 仍為 rc1。

## 專案文件

- [多分類拆分與可恢復草稿](docs/split-entry-drafts.md)
- [平均、百分比與固定比例分配](docs/split-allocation-assist.md)

- [背景鎖定與浮層取消](docs/lock-transient-routes.md)
- [金額欄內建計算器](docs/amount-calculator.md)
- [金額遮罩與基本無障礙](docs/privacy-presentation.md)
- [手動收支草稿與恢復](docs/manual-entry-drafts.md)

- [試用 APK 安裝與驗收](docs/installable-preview.md)
- [大規模測試、原始結果與容量限制](docs/preview-validation-report.md)
- [完整願景與原始 170 項決策](docs/full-vision-baseline.md)
- [Architecture Baseline v1.0-rc1](docs/architecture-baseline-v1.0-rc1.md)
- [整合架構與已選方向](docs/architecture-proposal.md)
- [實作順序與驗收安排](docs/implementation-plan.md)
- [本輪可安裝試用版與大規模測試安排](docs/installable-preview-plan.md)
- [開發前置準備](docs/development-readiness.md)
- [地基工程契約](docs/foundation-contracts.md)
- [業務套件邊界與 CI 檢查](docs/architecture-boundary-checks.md)
- [Actions 額度與本機驗證](docs/ci-budget-policy.md)
- [資料版本與升級前備份契約](docs/data-evolution-contract.md)
- [持久安全備份限定原型](docs/verified-safety-backup.md)
- [救援憑證沿用與 BackupProfile 契約](docs/backup-profile-contract.md)
- [具體驗收案例](docs/foundation-acceptance.md)
- [地基驗證結果與剩餘門檻](docs/foundation-validation.md)
- [Android 實機驗證紀錄](docs/android-device-validation.md)
- [逐項實作進度](docs/work-progress.md)
- [持續開發與分支收斂](docs/branch-consolidation.md)
- [SQLite 交易邊界原型](prototypes/transaction_boundary/README.md)

## 已選方向

按業務拆套件，業務內有必要可以再拆；以小型流程協調跨模組操作，需要一起成功的財務變動在同一交易提交。

日常以消費為主要口徑；首個可用版本提供備份密碼與文字救援金鑰。先交付日常記帳，再完成信用卡與日常管理，最後接上股票／ETF。

## 開發方式

先完成具體規格與關鍵技術驗證，再逐功能交付。變更走分支與 PR；文件初始化不代表正式 Architecture Freeze。未實作或未驗證的能力不顯示為可用功能。
