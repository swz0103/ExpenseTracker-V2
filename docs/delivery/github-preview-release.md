# GitHub 可下載 Android 預發版

`.github/workflows/preview-release.yml` 提供人工確認後的可下載 Android ARM64 預發版。它只允許從 `main` 執行，先鎖定依賴、格式、分析及完整 Flutter host 測試，再建置 APK、計算 SHA-256，最後建立 GitHub prerelease。

## 執行方式

1. 先更新 `prototypes/expense_preview/pubspec.yaml` 的 `version`，同一版本不可覆蓋既有 release。
2. 在 GitHub Actions 選擇 **Downloadable Android preview**，從 `main` 執行並勾選確認。
3. 工作完成後，到 GitHub Releases 下載 ARM64 APK 與同名 `.sha256`。
4. 核對 SHA-256 後側載；App ID 固定為 `dev.expensetracker.preview`，不覆蓋舊版 `com.wzet.app`。

這條流程使用每次 CI 隔離產生的開發簽章，目的是提供可安裝驗收包，不冒充 Google Play 正式簽章。商店發行需要使用者持有且妥善備份的長期 keystore，應以 GitHub environment secrets 注入，不能提交到 repository。

## 長期 release signing 接入點

Android release variant 預設不存在；只有 Gradle property
`v2EnableReleaseSigning=true` 明確啟用時才建立。啟用後下列環境值全部必填，任一缺少即在設定階段失敗，不會退回 debug key：

- `V2_RELEASE_APPLICATION_ID`：由金鑰持有人決定的正式套件 ID；不得在未決定舊 App 遷移策略前沿用 `com.wzet.app`。
- `V2_RELEASE_STORE_FILE`：runner 上暫存 keystore 的絕對路徑。
- `V2_RELEASE_STORE_PASSWORD`
- `V2_RELEASE_KEY_ALIAS`
- `V2_RELEASE_KEY_PASSWORD`

本機已以一次性 2,048-bit RSA 合成 keystore 驗證：預設只產生 debug/profile tasks；缺少秘密時 fail closed；五項值齊全時才出現 `assembleRelease` 與 `bundleRelease`。合成 keystore 已在驗證結束時刪除。真正長期 key、正式 package ID、GitHub environment 保護規則及 AAB 發布仍須由 key owner 決定與設定；repository 不保存私鑰或密碼。
