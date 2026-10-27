# Android 建置

`apps/expense_tracker/android/` 由 Flutter 3.47.5 的範本產生，再加上下面幾項。

## 下載安裝檔

每次 main 有變更，`V2 integration validation` 跑完且全部通過後，`Android APK` 工作流程建置同一個 commit，放在 GitHub 的 release `android-latest`（`ExpenseTracker.apk`）；驗證每次 push 只跑一次（驗證進行中又有好幾次 push 時，GitHub 只留最新一次排隊，中間的 commit 不會各自驗證與發布）。PR 與手動執行只檢查能否建置。

工作流程分成兩個工作：`build` 只有讀取權限，建置並存下 APK；`publish` 只在驗證過的 main 執行，是唯一能寫 release 的工作。`publish` 有自己的 concurrency 群組且不取消進行中的執行，所以之後完成的驗證（即使失敗或略過）或建置都不會把它中途打斷；main 的建置也依序排隊，發布順序與 commit 順序一致。上傳時先以暫名（`ExpenseTracker-<執行編號>.apk`）放上新檔，成功後才刪掉舊的並改名，release 不會出現沒有安裝檔的狀態（只有改名前一瞬間固定網址會找不到檔案）。PR 的建置有新 push 時會取消舊的。發布時 `android-latest` 這個 tag 會移到這次建置的 commit，說明附上 APK 的 SHA-256。每次建置都檢查 16 KB 分頁對齊。版本名稱取自 `pubspec.yaml`，版本號（versionCode）用工作流程的執行次數，所以新版一定能蓋過舊版安裝；兩者與 commit 也以 `--dart-define`（`APP_VERSION`、`APP_BUILD`、`APP_COMMIT`）傳進 App，顯示在「設定 › 關於」。

APK 只含 arm64（現行手機都是），約 28 MB：CI 用 `--target-platform android-arm64` 建置，`build.gradle.kts` 的 release 也只收 `arm64-v8a`（debug 與 profile 不限，模擬器才能跑 x86_64）。除錯符號不放進安裝檔，每次建置另存成工作流程的 artifact `symbols-<commit>`（保留 90 天），用 `flutter symbolize` 還原當機堆疊。中文字型 Huninn 已是常用字子集；再縮要另寫子集化工具，目前不做。main 的安裝檔一定用正式金鑰簽章：缺 Secrets 時工作流程直接失敗，不會發出無法覆蓋安裝的版本。正式金鑰只在驗證過的 main 建置時寫出（建置完即刪除）；PR 與手動執行一律用 debug 金鑰，碰不到正式金鑰。debug 簽章的安裝檔只供試用，不能覆蓋正式版。除錯符號的 artifact 以實際建置的 commit 命名：main 是驗證過的 commit，PR 是 GitHub 測試用的合併 commit。

## 專案設定

- application ID：`io.github.swz0103.expensetracker`。第一次分享安裝檔之後就固定了。
- 帳本放在 App 的私有資料夾（`Context.filesDir`），其他 App 讀不到。
- 權限：
  - `INTERNET`：抓證交所、櫃買中心的收盤價與臺灣銀行匯率。
  - `USE_BIOMETRIC`：指紋或臉部解鎖。
  - `READ_CALENDAR`、`WRITE_CALENDAR`：把到期提醒寫進使用者選的日曆；只在設定裡連結日曆時才詢問。
  - `POST_NOTIFICATIONS`：到期提醒與每日記帳提醒（Android 13 以上第一次開提醒時詢問）。
  - `ACCESS_NETWORK_STATE`：判斷是否連上 Wi-Fi，每週的雲端硬碟備份（含照片）只在 Wi-Fi 上傳（`NetworkPart.kt`）。
  - `SCHEDULE_EXACT_ALARM`：只在打開「準時提醒」時使用；Android 12 起要使用者在系統設定允許「鬧鐘與提醒」（App 會帶過去），沒允許時退回一般鬧鐘。不申請 `USE_EXACT_ALARM`（Play 只給鬧鐘、行事曆類 App）。
  - `RECEIVE_BOOT_COMPLETED`：重開機後重新排定提醒。`RestartReceiver` 也在 App 更新、改時間（`TIME_SET`）與改時區（`TIMEZONE_CHANGED`）時重排，這兩個不需要權限。
- 收件匣（`InboxWriter.kt`）：到期通知的「確認入帳」由 `ConfirmReceiver` 收下，用 `filesDir/inbox.pub` 的公鑰加密後寫進 `filesDir/inbox/`，帳本仍鎖著；下次打開帳本時才讀出入帳。加密用 Tink（`tink-android`）的 X25519 與 HKDF 加上系統的 AES-GCM；`InboxWriterTest.kt` 在 CI 以 `testDebugUnitTest` 驗證與 Dart 端相同的範例。`RestartReceiver` 也在 App 更新、改時間（`TIME_SET`）與改時區（`TIMEZONE_CHANGED`）時重排，這兩個不需要權限。
- 通知（`Reminders.kt`）：每則提醒記下手機當地的日期與時、分（另存當時的時間點，給舊版留下的資料用）。重開機、改時間或改時區時，依現在的時區重新算出時間點，所以 9:00 的提醒到了別的時區仍是當地 9:00；時間已過的則取消。鬧鐘預設用 `setAndAllowWhileIdle`，不是精準鬧鐘，手機休眠（Doze）時可能晚幾分鐘；打開「準時提醒」且系統允許時改用 `setExactAndAllowWhileIdle`。每則提醒帶標籤（`nudge`、`due:<key>`），重排時把已跳出但不再適用的通知收回（當天記過帳的每日提醒、已入帳或已繳的到期通知；測試通知除外）。「傳送測試通知」用另一個鬧鐘在一分鐘後跳出。設定頁的狀態列讀 `areNotificationsEnabled`、`canScheduleExactAlarms`、`isIgnoringBatteryOptimizations`，並可開 `ACTION_REQUEST_SCHEDULE_EXACT_ALARM`、`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`。
  - 已知限制：為了重開機後能重排，每則提醒的標題、內文（可能含金額）與點下去要開的畫面以明文存在 App 的 SharedPreferences（`reminders`）。這是 App 私有資料，其他 App 讀不到，也不在自動備份規則內（規則只收 `file` 網域），但不受帳本的 SQLCipher 加密保護。關掉通知後下次同步就會清空。
- 收據照片：相機寫到快取的 `camera/`（`FileProvider`，`res/xml/file_paths.xml`），縮小、加密存進 `receipts/` 後刪掉。

## Google 雲端硬碟備份

`play-services-auth` 的 `AuthorizationClient` 要 `https://www.googleapis.com/auth/drive.file` 的存取權杖（`DrivePart.kt` 的 `driveToken`），Dart 端直接呼叫 Drive REST v3（`lib/src/features/backup/model/drive_backup.dart`）。不需要 Firebase、`google-services.json` 或伺服器用戶端 ID，但 Google Cloud 要設定：

1. 建專案、啟用 Google Drive API。
2. Google Auth Platform：品牌（App 名稱、聯絡信箱）、目標對象選「外部」並發布（`drive.file` 是非敏感權限，不需審查）。
3. 用戶端：類型 Android，套件名稱 `io.github.swz0103.expensetracker`，SHA-1 用發佈簽章的（`keytool -list -v -keystore <jks> -alias <alias>`）。換簽章要再加一個用戶端。

備份寫在 `exports/`，上傳完就刪；雲端資料夾是「記帳本備份」。每份標上帳本 id（Drive `appProperties.ledger`，即 keyring id），只整理同一本帳本的備份：留最新 5 份，較舊的移到雲端硬碟垃圾桶（30 天內可救回）；別本帳本的、或沒有標記的舊備份不動。「停止」會呼叫 `oauth2.googleapis.com/revoke` 撤銷授權，下次連結重新選帳號。還原畫面的「從 Google 雲端硬碟選擇」把挑到的那份下載到快取 `restore.etbk`（啟動時清掉）。

## 備份到手機資料夾

`FolderPart.kt` 用系統的資料夾選擇（`OpenDocumentTree`）讓使用者選一次資料夾，並以 `takePersistableUriPermission` 取得長期讀寫權；之後用 `DocumentsContract` 建立、列出、刪除檔案（在背景執行緒）。檔名是「記帳本-<帳本代碼>-年月日-時分.etbk」，帳本代碼取自 keyring id 的前 6 碼；只整理同一本帳本的備份（留最新 5 份），資料夾裡的其他檔案、別本帳本的備份都不動。寫到一半失敗會把那個檔刪掉。使用者在系統設定收回權限後，下次備份會失敗並在設定頁標示，提示一次。「停止」會歸還權限，已寫的備份留著。這個資料夾在 App 外：其他 App、電腦或雲端同步軟體都看得到檔案（內容已加密）。

## 從設定還原

設定 › 備份與還原 › 從備份還原：先把目前的帳本連同照片寫到 `before-restore/`（只留最新 2 份，不進 Android 雲端備份），關閉帳本，解鎖畫面直接開在還原表單。選好檔案、雲端硬碟的備份或「還原前自動留下的帳本」後，先顯示備份時間與筆數再輸入密碼或救援碼。`LedgerVault.restore(replacing: true)` 才會覆蓋已存在的帳本：暫存資料庫通過完整性檢查前不動原帳本，失敗就保留原帳本。按返回回到原帳本。

## Android 自動備份

`allowBackup="true"`，規則在 `res/xml/data_extraction_rules.xml`（Android 12 以上）與 `backup_rules.xml`。帳本與每週備份會進使用者的 Google 備份，Android 以螢幕鎖加密；不帶走的有：

- `device-id`（這支手機的指紋登記）、`no-fingerprint`（拒絕指紋的紀錄）：換手機要重新登記。
- `exports`：要交出去的檔案（附照片的備份、CSV）只在這裡放到系統存檔畫面寫完為止，之後立即刪除；App 啟動時也會清掉上次沒刪到的（`lib/src/features/backup/model/leftovers.dart`，連同快取裡的相機暫存與選取的備份副本）。所以附照片的匯出備份不會佔用 25 MB 的備份額度；每週備份（不含照片）仍在 `backups/`，照常備份。
- `calendar`：選的日曆，換手機要重新選。
- `diagnostics.log`：「設定 › 關於」的錯誤紀錄，只屬於這支手機（只記錯誤類型與簡短訊息，不含帳本內容）。
- `before-restore`：從設定還原前留下的帳本（含照片），只放在這支手機。
- `receipts`：收據照片，不進雲端備份（很快就會超過 25 MB 額度）；裝置對裝置轉移（`device-transfer`）仍會帶走。要保留照片請匯出備份檔，它會附上照片。

沒設密碼時，帳本金鑰存在 App 的私有資料夾，會跟著帳本進 Android 的雲端備份（由 Google 以手機螢幕鎖加密）；新手機還原後可直接打開，但也代表帳本的安全等同那份雲端備份。設了密碼後，金鑰只以密碼、救援碼與指紋包裝存放，還原後要輸入密碼或救援碼。

## 指紋或臉部解鎖

- `KeystorePart.kt` 在 Android Keystore 建立一把 AES-256-GCM 金鑰，每次使用都要指紋或臉部確認（`BIOMETRIC_STRONG`）；新增或刪除指紋後這把金鑰就失效。
- 第一次用密碼打開帳本時會請你確認一次指紋；之後可直接用指紋打開。拒絕後不再詢問；之後想用，在解鎖畫面點指紋即可。
- 指紋失效或換手機時，用密碼或救援碼打開。
- App 在背景超過 5 分鐘再回來，帳本會自動鎖上。時間同時用手機時鐘與只會往前走的時鐘計算，把手機時間調回去會直接鎖上。
- 離開 App 時（含拉下通知欄）整個畫面，連同開著的表單與對話框，都蓋上只有「記帳本」字樣的遮罩，多工畫面看不到金額（`PrivacyCover`）。

## Google 日曆

`CalendarBridge.kt` 用 Android 的 `CalendarContract` 寫事件，不需要 Google API 金鑰：手機上登入的 Google 帳號日曆會由 Google 日曆 App 同步。事件說明的最後一行是「記帳本#」加識別碼，App 只會改寫或刪除自己建立的事件。

刪掉舊事件與寫入新事件在同一批（`applyBatch`）、不設 yield point，日曆在一次交易內套用：中途失敗時日曆維持原樣。系統日曆一批少於 500 個操作，所以一次最多寫 450 個操作（每個事件 1 個，加上每個提醒 1 個）；放不下的是最遠的事件，等之後同步再寫。沒有提醒的事件不標記 `HAS_ALARM`。

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

4. Google 雲端硬碟登入用的 Android OAuth 用戶端要填發佈簽章的 SHA-1：`keytool -list -v -keystore ~/expense-tracker.jks -alias expense-tracker`（設定步驟見上方「Google 雲端硬碟備份」）。

## 本機建置

```bash
cd apps/expense_tracker
flutter build apk --release --target-platform android-arm64 \
  --split-debug-info=build/symbols   # 和 CI 相同；或 flutter run --release
```

`--target-platform` 不加也能建置，只是多編譯兩種架構的程式碼，release 仍只打包 arm64。
