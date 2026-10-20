# Android 建置

`apps/expense_tracker/android/` 由 Flutter 3.47.5 的範本產生，再加上下面幾項。

## 下載安裝檔

每次 main 有變更，`Android APK` 工作流程會建好 APK，放在 GitHub 的 release `android-latest`（`ExpenseTracker.apk`）。PR 只檢查能否建置。版本名稱取自 `pubspec.yaml`，版本號（versionCode）用工作流程的執行次數，所以新版一定能蓋過舊版安裝。

APK 只含 arm64（現行手機都是），約 28 MB；除錯符號不放進安裝檔。main 的安裝檔一定用正式金鑰簽章：缺 Secrets 時工作流程直接失敗，不會發出無法覆蓋安裝的版本。PR 的檢查沒有 Secrets 也能用 debug 金鑰建置。

## 專案設定

- application ID：`io.github.swz0103.expensetracker`。第一次分享安裝檔之後就固定了。
- 帳本放在 App 的私有資料夾（`Context.filesDir`），其他 App 讀不到。
- 權限：
  - `INTERNET`：抓證交所、櫃買中心的收盤價與臺灣銀行匯率。
  - `USE_BIOMETRIC`：指紋或臉部解鎖。
  - `READ_CALENDAR`、`WRITE_CALENDAR`：把到期提醒寫進使用者選的日曆；只在設定裡連結日曆時才詢問。

## Android 自動備份

`allowBackup="true"`，規則在 `res/xml/data_extraction_rules.xml`（Android 12 以上）與 `backup_rules.xml`。帳本與每週備份會進使用者的 Google 備份，Android 以螢幕鎖加密；不帶走的有：

- `device-id`（這支手機的指紋登記）、`no-fingerprint`（拒絕指紋的紀錄）：換手機要重新登記。
- `exports`：匯出的檔案。
- `calendar`：選的日曆，換手機要重新選。

沒設密碼時，帳本金鑰也在私有資料夾，會跟帳本一起備份，新手機可直接打開；設了密碼就要輸入密碼或救援碼。

## 指紋或臉部解鎖

- `MainActivity.kt` 在 Android Keystore 建立一把 AES-256-GCM 金鑰，每次使用都要指紋或臉部確認（`BIOMETRIC_STRONG`）；新增或刪除指紋後這把金鑰就失效。
- 第一次用密碼打開帳本時會請你確認一次指紋；之後可直接用指紋打開。拒絕後不再詢問；之後想用，在解鎖畫面點指紋即可。
- 指紋失效或換手機時，用密碼或救援碼打開。
- App 在背景超過 5 分鐘再回來，帳本會自動鎖上。

## Google 日曆

`CalendarBridge.kt` 用 Android 的 `CalendarContract` 寫事件，不需要 Google API 金鑰：手機上登入的 Google 帳號日曆會由 Google 日曆 App 同步。事件說明的最後一行是「記帳本#」加識別碼，App 只會改寫或刪除自己建立的事件。

## 正式簽章

1. 建立金鑰（只做一次；檔案和密碼要另外安全保存，遺失就無法更新 App）：

   ```bash
   keytool -genkey -v -keystore ~/expense-tracker.jks -keyalg RSA -keysize 2048 -validity 10000 -alias expense-tracker
   ```

2. 在 GitHub 的 Settings › Secrets and variables › Actions 新增 [STATUS](../STATUS.md#簽章-secrets) 表中的 4 個 Secrets（`.jks` 先 `base64 -w0` 轉成文字）。
3. 本機建置時改建立 `apps/expense_tracker/android/key.properties`（已在 `.gitignore`）：

   ```properties
   storeFile=/home/you/expense-tracker.jks
   storePassword=…
   keyAlias=expense-tracker
   keyPassword=…
   ```

4. 之後要接 Google 登入時，用 `keytool -list -v -keystore ~/expense-tracker.jks -alias expense-tracker` 取得 SHA-1。

## 本機建置

```bash
cd apps/expense_tracker
flutter build apk --release   # 或 flutter run --release
```
