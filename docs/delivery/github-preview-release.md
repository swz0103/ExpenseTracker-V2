# GitHub 可下載 Android 預發版

`.github/workflows/preview-release.yml` 提供人工確認後的可下載 Android ARM64 預發版。它只允許從 `main` 執行，先鎖定依賴、格式、分析及完整 Flutter host 測試，再建置 APK、計算 SHA-256，最後建立 GitHub prerelease。

## 執行方式

1. 先更新 `prototypes/expense_preview/pubspec.yaml` 的 `version`，同一版本不可覆蓋既有 release。
2. 在 GitHub Actions 選擇 **Downloadable Android preview**，從 `main` 執行並勾選確認。
3. 工作完成後，到 GitHub Releases 下載 ARM64 APK 與同名 `.sha256`。
4. 核對 SHA-256 後側載；App ID 固定為 `dev.expensetracker.preview`，不覆蓋舊版 `com.wzet.app`。

這條流程使用每次 CI 隔離產生的開發簽章，目的是提供可安裝驗收包，不冒充 Google Play 正式簽章。商店發行需要使用者持有且妥善備份的長期 keystore，應以 GitHub environment secrets 注入，不能提交到 repository。

