# 最小試用版安裝與驗收

交付狀態：最終 debug APK 已建置、簽章及封裝核對通過；大規模測試完成。完整 CI 結果見 PR #31 checks，測試方法與原始紀錄見[驗證報告](preview-validation-report.md)。本輪未操作手機。

## 安裝包識別

- 檔名：`ExpenseTracker-V2-preview-0.2.0-arm64.apk`，本機專案的 `build/deliverables/` 目錄。二進位檔未提交 Git、未公開發布。
- 版本：`0.2.0+2`；App ID `dev.expensetracker.preview`；最低 API 24、target API 36。
- 大小：116,209,955 bytes（約 110.8 MiB）。
- SHA-256：`bdb0f3f5d7e028cac3ceedb2b775df38ff397c3e1627a9b718b7ff0274663f84`。
- Android debug 簽章的 APK v2 驗證通過；manifest 的 `allowBackup=false`。Flutter 與 SQLCipher 原生程式庫均為 ARM64；相依套件另附其他架構的 JNI 檔案，不代表此包支援那些裝置。

這是本機建置產物的 hash；其他電腦重新建置可能因 debug 簽章等差異產生不同 hash。原始碼交付於 `test/preview-large-scale`，依賴 PR #30。

## 試用範圍

這是獨立的「記帳 V2 試用版」，App ID `dev.expensetracker.preview`。支援 Android 7.0／API 24 以上的 ARM64 裝置；側載 debug APK，沒有正式上架或發版。它不覆蓋「記帳 V2 地基驗證」原型。

可建立現金／銀行帳戶、期初餘額、收入／支出、日期、帳戶餘額與交易列表；包含離開前景鎖定、加密備份及密碼／救援文字還原。每個帳本最多 32 個帳戶及 5,000 筆交易（含期初）。

分類、商家、Tag、修改／刪除、退款、轉帳、FX、報表、信用卡、投資及完整 migration 協調尚未交付。原本的[完整規劃](implementation-plan.md)保留；這個版本不是整個 M1／M2／M3 完成。

## 安裝方式

1. 將交付的 `.apk` 複製到手機，由檔案管理員開啟。若系統要求允許該檔案來源安裝，請在手機上自行確認。
2. 安裝後開啟「記帳 V2 試用版」。首次設定至少 12 個字元密碼，另外保存顯示的救援文字並確認。
3. 先使用下面的測試資料驗收。此版本是 debug 試用包；本輪未操作手機，Android 新 App 的平台檔案選擇器／安全儲存與整體操作仍待你驗收。

本輪不會自動安裝、操作或清除手機資料。不要為了重新測試而直接清除已有帳本；先匯出並確認備份。

## 簡單驗收流程

1. 新增「測試現金」，選 TWD，期初 `1000`，起始日期選不晚於收支日期。
2. 記一筆支出 `25.50`，帳戶餘額應為 `974.50`；再記收入 `100`，應為 `1074.50`。
3. 切到其他 App 再回來，應要求解鎖，畫面不直接顯示帳務。
4. 匯出加密備份，選擇你能再找到的儲存位置；顯示讀回核對成功後才算完成。系統檔案選擇器也會觸發鎖定，返回後請解鎖。
5. 再新增一筆測試收支，從剛才檔案還原，先用備份密碼，帳戶應回到 `1074.50`。再次匯入同一檔案時可選救援文字路徑核對。
6. 若需要取回還原前的內容，可先「匯出最近一次還原前副本」，再用相同還原流程匯入。每次還原會保留原世代及安全副本，尚無自動清理介面。

救援文字必須與已有加密備份搭配，不能單靠它找回未備份資料。匯入別次安裝的備份後，新匯出的備份使用**本次安裝設定**的密碼與救援文字，畫面也會先說明此規則。忘記本機密碼時，可在新的安裝先設定新密碼，再用原備份及其救援文字匯入；不要在唯一一份資料尚未備份時先移除 App。

## 開發者重建

使用本專案鎖定的 Flutter 3.47.5／Dart 3.13.4、既有 Android SDK／NDK，在 `prototypes/expense_preview`：

```powershell
flutter pub get --enforce-lockfile
flutter build apk --debug --target-platform android-arm64 --no-pub
```

預設產物為該目錄的 `build/app/outputs/flutter-apk/app-debug.apk`。Gradle 已禁止自動下載缺少的 SDK；release variant 關閉。沒有新增接受授權或簽署正式發版的步驟。

詳細驗證方法與容量保護見[測試報告](preview-validation-report.md)，平台尚未完成的門檻見[逐項進度](work-progress.md)。
