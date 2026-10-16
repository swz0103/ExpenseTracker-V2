# Android 建置

> 現況（2026-10-16）：`apps/expense_tracker/android/` 由 Flutter 3.47.5 的範本產生，再加上下面幾項。CI 目前只建網頁預覽，還沒有建 Android；第一次請在本機建置並裝到手機上驗收。

## 專案設定

- application ID：`io.github.swz0103.expensetracker`。第一次上架或分享安裝檔之前還能改，之後就固定了。
- 帳本放在 App 的私有資料夾（`Context.filesDir`），其他 App 讀不到。`android:allowBackup="false"`：Android 的自動備份不會複製帳本，備份請用 App 內的加密備份。
- 權限：
  - `INTERNET`：抓證交所和櫃買中心的收盤價。
  - `USE_BIOMETRIC`：指紋或臉部解鎖。

## 指紋或臉部解鎖

- `MainActivity.kt` 在 Android Keystore 建立一把 AES-256-GCM 金鑰。每次使用都要指紋或臉部確認（`BIOMETRIC_STRONG`），新增或刪除指紋後這把金鑰就失效。
- 第一次用密碼打開帳本時，App 會請你確認一次指紋，把帳本金鑰包進 Keystore；之後就能直接用指紋打開。取消指紋不影響密碼解鎖，下次用密碼打開時會再問。
- 指紋失效或換手機時，用密碼或救援碼打開即可。
- App 在背景超過 5 分鐘再回來，帳本會自動鎖上。

## 本機建置

```bash
cd apps/expense_tracker
flutter build apk --release   # 或 flutter run --release
```

沒有 `android/key.properties` 時，release 版用 debug 金鑰簽章，只適合自己測試。

## 正式簽章

1. 建立金鑰（只做一次，檔案和密碼都要另外安全保存，遺失就無法更新 App）：

   ```bash
   keytool -genkey -v -keystore ~/expense-tracker.jks -keyalg RSA -keysize 2048 -validity 10000 -alias expense-tracker
   ```

2. 建立 `apps/expense_tracker/android/key.properties`（已在 `.gitignore`，不會提交）：

   ```properties
   storeFile=/home/you/expense-tracker.jks
   storePassword=…
   keyAlias=expense-tracker
   keyPassword=…
   ```

3. 取得 SHA-1 給 Google Drive 的 Android OAuth client：`keytool -list -v -keystore ~/expense-tracker.jks -alias expense-tracker`。

## 待辦

- CI 建置 Android（需要新增 workflow；要用有 `workflow` 權限的 token 推送，或由你在 GitHub 網頁上新增）。
- Google 登入與 Drive 備份：需要 Google 登入的套件，要在能連上 pub.dev 的環境加入。
- 真機驗收：解鎖、指紋失效、背景鎖定、備份還原、收盤價。
