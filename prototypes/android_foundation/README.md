# Android 地基驗證入口

狀態：限定原型，Android ARM64 debug APK 已建置成功，尚未通過 Android 裝置驗收。不得保存真實帳本。

對應[實作計畫階段 1](../../docs/implementation-plan.md)與[地基驗證紀錄](../../docs/foundation-validation.md)。此入口沿用既有業務套件及加密／還原原型，待平台 gate 通過後才整理正式產品組件。

## 驗證路徑

- Android secure storage 保存隨機 32-byte DB key，寫入後讀回核對；資料庫存在而 key 遺失、格式未知或讀寫失敗時拒絕開檔，不重設金鑰。
- 固定測試帳戶依序入帳期初 100、收入 20、支出 5，關閉加密 DB 後重新讀 key、開檔並核對餘額 115。
- 密碼與文字救援金鑰分別還原至使用新 key 的加密暫存 DB，核對完整 snapshot，再清除該次產生的暫存目錄。
- 重複執行沿用固定 operation ID，確認不重複入帳。原始測試 DB 保留，供下次啟動核對。

目前兩條 Android 還原在同一應用程序內執行，來源 key 仍可能存在記憶體；即使通過，也不能替代乾淨新裝置還原 gate。跨程序及刪除來源 DB 的 host 證據見[加密儲存原型](../encrypted_storage/README.md)。

## 安全界線

`AndroidKeyVault` 明確設定 `resetOnError: false`、`migrateOnAlgorithmChange: false`，使用獨立 namespace。這是固定原型版本的 key 讀寫策略，尚未實作正式 key metadata 與資料庫切換、輪替或升級流程。`KeyAccess` 僅合併同一 instance 的並行請求；入口另限制同一程序只能執行一個 runner，不宣稱跨程序初始化鎖。

備份密碼及帳戶資料都是公開的固定測試值。不得加入使用者輸入或真實資料。App root 的 sqlite3 hook 指定 SQLCipher；不可因建置失敗退回明文 SQLite。

Android manifest 停用系統備份，另加入 cloud／device／cross-platform transfer 排除規則；Activity 設定 FLAG_SECURE。這些設定尚未在 Android 裝置驗證，不能宣稱所有裝置皆阻止備份或截圖。Release variant 已停用，runner 也拒絕 release 模式。

## 版本與目前證據

- Flutter 3.47.5／Dart 3.13.4；相依鎖定於 pubspec.lock。
- App compile SDK 36、min SDK 24；NDK 28.2.13676358 已安裝。
- flutter_secure_storage 11.2.0、path_provider 2.1.6、sqlite3 3.6.0。
- 本機靜態分析及 6 項 host 金鑰測試通過：遺失 key 不覆寫、並行初始化、既有 key 重用、無效格式拒絕、讀取失敗保留、寫入讀回不一致拒絕。測試 vault 為記憶體實作，不是 Android Keystore 證據。
- 2026-09-27 排除 JNI 相依的 SDK Platform 35 與 CMake 3.22.1 缺漏後，ARM64 debug APK 建置成功。App 使用 SDK 36 不代表相依套件不需要 SDK 35；Build Tools 35 也不能替代 Platform 35。
- 已核對 APK 含 ARM64 libsqlcipher.so；最終 manifest 為 min SDK 24／target SDK 36、debuggable=true、allowBackup=false，兩份備份排除規則引用存在。這是封裝檢查，不是裝置行為驗證。
- 沒有可用 Android 裝置；integration test 尚未執行。host CI 狀態以 PR checks 為準。

## 接續步驟

建置環境需 SDK Platform 35／36、NDK 28.2.13676358、CMake 3.22.1；本機已補齊此次缺漏。`android.builder.sdkDownload=false` 保留，避免建置時自動安裝 SDK 或接受新授權。若安裝需要新授權，應交由使用者處理。

在本目錄執行：

```powershell
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --reporter expanded
flutter build apk --debug --target-platform android-arm64
```

本機產物：`build/app/outputs/flutter-apk/app-debug.apk`，93,873,282 bytes；SHA-256：`fac4619a4b9e9200bebd8234b88e2c357404c9fca1fa28b2d53b899aa0072f8f`。這是此次本機 debug 成品，不保證其他機器重建得到相同 hash。APK 不納入 Git，也未正式發版。

連接開啟 USB 偵錯的測試手機，或準備可用模擬器後執行：

```powershell
flutter devices
flutter test integration_test/device_probe_test.dart -d <Android裝置ID>
```

此測試在同一程序執行兩次；另需關閉／重啟 App 再次執行、記錄裝置與 OS，以及補足 key 遺失、乾淨還原與 migration 故障的平台案例。完整範圍以[驗收清單](../../docs/foundation-acceptance.md)為準。

參考：[secure storage 版本紀錄](https://pub.dev/packages/flutter_secure_storage/changelog)、[Android 備份規則](https://developer.android.com/identity/data/autobackup)。實際相依及編譯結果以鎖定版本與執行結果為準。
