# ExpenseTracker V2

Android 優先、Flutter、local-first 的個人財務管理 App。

目前進行架構規格與開發前置準備，尚未發布可用 App，Architecture Baseline 仍為 rc1。

## 專案文件

- [完整願景與原始 170 項決策](docs/full-vision-baseline.md)
- [Architecture Baseline v1.0-rc1](docs/architecture-baseline-v1.0-rc1.md)
- [整合架構與已選方向](docs/architecture-proposal.md)
- [實作順序與驗收安排](docs/implementation-plan.md)
- [開發前置準備](docs/development-readiness.md)

## 已選方向

按業務拆套件，業務內有必要可以再拆；以小型流程協調跨模組操作，需要一起成功的財務變動在同一交易提交。

日常以消費為主要口徑；首個可用版本提供備份密碼與文字救援金鑰。先交付日常記帳，再完成信用卡與日常管理，最後接上股票／ETF。

## 開發方式

先完成具體規格與關鍵技術驗證，再逐功能交付。變更走分支與 PR；文件初始化不代表正式 Architecture Freeze。未實作或未驗證的能力不顯示為可用功能。
