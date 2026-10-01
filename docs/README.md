# 文件導覽

這裡保留產品決策、實作契約、逐批驗證與歷史紀錄。新增功能時先看目前的基準與進度；舊文件和測試結果是追溯資料，不因整理而刪除。

## 目前應先讀

- [Architecture Baseline v1.0-rc1](architecture/architecture-baseline-v1.0-rc1.md)：CORE、延後項目及驗收邊界。
- [實作安排](delivery/implementation-plan.md)：地基、M1、M2、M3 的交付順序與 gate。
- [工作進度](work-progress.md)：最新功能狀態、未完成事項與驗證限制。
- [Full Vision Baseline](architecture/full-vision-baseline.md)：完整願景與延後能力的來源。
- [架構回查](architecture/architecture-review-2026-09-29.md)：目前已知風險與改善方向。
- [2026-09-30 上市審查](architecture/shipping-review-2026-09-30.md)：兩支非 main 分支的整合與上市 gate。
- [2026-10-01 功能缺陷與建議](architecture/functional-review-2026-10-01.md)：既有功能缺陷與建議補上的能力。

## 開發與交付規則

- [GitHub 交付規則](delivery/github-delivery-policy.md)與[分支收斂](delivery/branch-consolidation.md)。
- [CI 額度規則](delivery/ci-budget-policy.md)與[架構邊界檢查](architecture/architecture-boundary-checks.md)。
- [資料演進契約](foundation/data-evolution-contract.md)、[加密備份](foundation/verified-safety-backup.md)與[Android 實機驗證](delivery/android-device-validation.md)。

## 資料夾

根目錄只留這份導覽、[能力矩陣](capability-matrix.md)與[工作進度](work-progress.md)。其餘文件依用途分開，沒有刪除舊紀錄。

- `architecture/`：願景、架構基準、審查與精確數值契約。
- `delivery/`：實作順序、分支、CI、安裝包與實機驗證。
- `foundation/`：地基驗收、儲存、備份與帳本升級契約。
- `features/`：各功能的設計與操作說明。是否完成以[實作安排](delivery/implementation-plan.md)及[工作進度](work-progress.md)為準。
- `test-results/YYYY-MM-DD/`：逐批證據，依檔名日期分資料夾。檔名日期不等於當前提交已通過同一項檢查；確認結果時須核對測試範圍、提交與主機／實機／雲端 gate。
- `branch-history/`：舊分支查詢紀錄。
