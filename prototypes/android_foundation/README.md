# Android 地基驗證入口

狀態：限定原型，Android ARM64 debug APK 已建置成功，尚未通過 Android 裝置驗收。不得保存真實帳本。

對應[實作計畫階段 1](../../docs/implementation-plan.md)與[地基驗證紀錄](../../docs/foundation-validation.md)。此入口沿用既有業務套件及加密／還原原型，待平台 gate 通過後才整理正式產品組件。

## 驗證路徑

- Android secure storage 保存隨機 32-byte DB key，寫入後讀回核對；資料庫存在而 key 遺失、格式未知或讀寫失敗時拒絕開檔，不重設金鑰。
- 固定測試帳戶依序入帳期初 100、收入 20、支出 5，關閉加密 DB 後重新讀 key、開檔並核對餘額 115。
- 密碼與文字救援金鑰分別還原至各自的加密世代 DB，以獨立安全儲存 slot 保存目標 key。重新建立 adapter 後讀回目前配對、完整 snapshot 與餘額，重送收入操作必須回傳 replay。
- 重複執行沿用固定 operation ID，確認不重複入帳。原始測試 DB 保留，供下次啟動核對。

目前兩條 Android 還原在同一應用程序內執行，來源 key 仍可能存在記憶體；即使通過，也不能替代乾淨新裝置還原 gate。跨程序及刪除來源 DB 的 host 證據見[加密儲存原型](../encrypted_storage/README.md)。

## 安全界線

來源 DB 的 `AndroidKeyVault` 沿用原 namespace；目標的 `AndroidSlotVault` 使用 `expense_v2_generation_probe_v1` 與逐 slot 名稱。兩者都明確設定 `resetOnError: false`、`migrateOnAlgorithmChange: false`。`SecureKeySlots` 建立前拒絕已存在欄位，寫後讀回；讀取缺失或未知格式只拒絕，不建立替代 key，不刪除寫入結果未定的 slot。

目標使用 [Ledger 世代整合](../ledger_generation/README.md) 的財務 schema 3／snapshot format 2，以及[加密控制 schema 2](../../docs/storage-control-protection.md)。`androidCatalogProtection` 的 factory 以獨立 namespace 和逐 store key 保護控制紀錄，核對內外本機身份。平台 adapter 未匯入明文 FixtureKeySlots。正式輪替、清理、超時及活躍連線租約仍未完成。

新測試路徑使用 `generation_v2_password`／`generation_v2_recovery`；兩個目標目錄、控制 key 與世代 slot 保留給重啟核對。先前 v1 目錄與 key 保留，不就地轉換；此改動不是正式資料升級機制。初始控制建表 transaction 中止目前停止並保留，不能宣稱可自動恢復所有中斷。

`KeyAccess` 僅合併同一 instance 的來源初始化請求；`SecureKeySlots` 的建立保護跨 instance、限同 isolate。入口限制同程序一個 runner，目標協調器另持有檔案鎖；這不是平台 vault 本身提供的跨程序 compare-and-set，不支援任意繞過協調器的寫入。

備份密碼及帳戶資料都是公開的固定測試值。不得加入使用者輸入或真實資料。App root 的 sqlite3 hook 指定 SQLCipher；不可因建置失敗退回明文 SQLite。

Android manifest 停用系統備份，另加入 cloud／device／cross-platform transfer 排除規則；Activity 設定 FLAG_SECURE。這些設定尚未在 Android 裝置驗證，不能宣稱所有裝置皆阻止備份或截圖。Release variant 已停用，runner 也拒絕 release 模式。

## 版本與目前證據

- Flutter 3.47.5／Dart 3.13.4；相依鎖定於 pubspec.lock。
- App compile SDK 36、min SDK 24；NDK 28.2.13676358 已安裝。
- flutter_secure_storage 11.2.0、path_provider 2.1.6、sqlite3 3.6.0。
- 本機靜態分析與 17 項 host 金鑰測試通過：原有 6 項，加上 11 項 slot 獨立性、重新讀取、缺失／未知格式、不可覆寫、寫入前／後失敗、讀回不一致、錯誤去敏與跨 instance 競爭。測試 vault 為記憶體實作，不是 Android Keystore 證據；遠端結果見 PR checks。
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

本機產物：`build/app/outputs/flutter-apk/app-debug.apk`，117,467,266 bytes；SHA-256：`943b00c07461325623e8b66caff4fd57f46edbf05ae0bf3755b646f9c277947c`。此為 2026-09-27 接入加密控制紀錄後重新建置的 debug 成品，已核對 ARM64 SQLCipher 與上述 manifest 設定。不保證其他機器重建得到相同 hash。APK 不納入 Git，也未正式發版。

連接開啟 USB 偵錯的測試手機，或準備可用模擬器後執行：

```powershell
flutter devices
flutter test integration_test/device_probe_test.dart -d <Android裝置ID>
```

此測試在同一程序執行兩次；另需關閉／重啟 App 再次執行、記錄裝置與 OS，以及補足 key 遺失、乾淨還原與 migration 故障的平台案例。完整範圍以[驗收清單](../../docs/foundation-acceptance.md)為準。

參考：[secure storage 版本紀錄](https://pub.dev/packages/flutter_secure_storage/changelog)、[Android 備份規則](https://developer.android.com/identity/data/autobackup)。實際相依及編譯結果以鎖定版本與執行結果為準。
