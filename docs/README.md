# 文件導覽

這裡保留產品決策、實作契約、逐批驗證與歷史紀錄。新增功能時先看目前的基準與進度；舊文件和測試結果是追溯資料，不因整理而刪除。

## 目前應先讀

- [Architecture Baseline v1.0-rc1](architecture-baseline-v1.0-rc1.md)：CORE、延後項目及驗收邊界。
- [實作安排](implementation-plan.md)：地基、M1、M2、M3 的交付順序與 gate。
- [工作進度](work-progress.md)：最新功能狀態、未完成事項與驗證限制。
- [Full Vision Baseline](full-vision-baseline.md)：完整願景與延後能力的來源。
- [架構回查](architecture-review-2026-09-29.md)：目前已知風險與改善方向。
- [2026-09-30 上市審查](shipping-review-2026-09-30.md)：兩支非 main 分支的整合與上市 gate。

## 開發與交付規則

- [GitHub 交付規則](github-delivery-policy.md)與[分支收斂](branch-consolidation.md)。
- [CI 額度規則](ci-budget-policy.md)與[架構邊界檢查](architecture-boundary-checks.md)。
- [資料演進契約](data-evolution-contract.md)、[加密備份](verified-safety-backup.md)與[Android 實機驗證](android-device-validation.md)。

## 功能與驗證紀錄

各功能的設計與操作說明仍保留在本目錄的個別 Markdown；請以[實作安排](implementation-plan.md)及[工作進度](work-progress.md)判斷是否已正式完成。`test-results/` 是逐批證據，檔名日期不等於當前提交已通過同一項檢查；確認結果時須核對測試範圍、提交與主機／實機／雲端 gate。
