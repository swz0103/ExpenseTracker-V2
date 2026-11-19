# 開發

> 怎麼在本機跑起來、跑哪些檢查、CI 做什麼、怎麼發版。寫程式的規則在 [conventions.md](conventions.md)。

## 環境

- Flutter 3.47.5（Dart 跟著它）；Android 建置要 Android SDK 與 JDK 17。
- 每個模組各有 `pubspec.lock`，一律 `pub get --enforce-lockfile`。
- 沒有 Flutter 時：把分支推到 `tools/<名稱>`，`Flutter tools` 工作流程會更新 lockfile 並排版到 `tools/<名稱>-done`。

## 常用指令

在 `apps/expense_tracker` 下：

| 做什麼 | 指令 |
| --- | --- |
| 全部測試 | `flutter test` |
| 只看規則 | `flutter test test/app/layers_test.dart test/app/design_rules_test.dart` |
| 只看版面 | `flutter test test/app/layout_common_test.dart` |
| 分析與排版 | `flutter analyze`、`dart format lib test` |
| 網頁預覽 | `flutter run -d chrome -t lib/main_preview.dart` |
| 截圖 | `flutter test tool/screenshots`（`SHOTS_ONLY=頁名,頁名` 只拍幾頁，`SHOTS_TEXT=200` 用 Android 最大字級），存到 `build/screenshots` |
| Android 單元測試 | `cd android && ./gradlew :app:testDebugUnitTest` |
| 本機建置 APK | `flutter build apk --release --target-platform android-arm64 --split-debug-info=build/symbols` |

全部模組一次檢查：在根目錄 `./tooling/run-host-checks.ps1 -Package all`（每個模組依序 pub get、格式、analyze、測試）。

## 工具

| 工具 | 做什麼 |
| --- | --- |
| `tool/move.py` | 搬 Dart 檔並改好所有 import 與 part（用 git mv） |
| `tool/split.py` | 把太長的檔案後段的宣告搬到 part 檔 |
| `tool/glyphs.py` | 定義所有圖示，產生 `core/look/glyphs.dart`（不要手改產生的檔） |
| `tool/test_ledger.py` | 產生兩年份、約 2,500 筆的測試帳本 `test-ledger.etbk`（密碼 `test1234`）：多家銀行、三張信用卡、外幣、車貸、代墊、十檔股票、預算與定期 |
| `tool/screenshots/` | 依 `test/app/places.dart` 拍每頁淺色、深色截圖 |
| `tool/app_icon.svg` | App 圖示原稿 |

## CI

| 工作流程 | 什麼時候 | 做什麼 |
| --- | --- | --- |
| `V2 integration validation` | PR 與 main | `dart`：純 Dart 模組；`flutter-host`：App 的 analyze、測試、截圖（artifact `screenshots`） |
| `Android APK` | PR 與驗證過的 main | `build`（看不到金鑰）→ `sign`（apksigner 換正式簽章）→ `publish`（release `android-latest`） |
| `V2 web preview` | PR 與 main | 建網頁預覽 |
| `Emulator timings` | main | 模擬器量測載入、捲動、存檔時間 |
| `Supply chain` | 每週 | OSV 弱點與授權掃描 |
| `Flutter tools` | `tools/*` 分支 | 代為更新 lockfile 與排版 |

只改文件的 PR 不跑 CI；分支保護與必過檢查的設定見 [android.md](android.md#分支保護)。

## 發版

1. 改 `apps/expense_tracker/pubspec.yaml` 的版號（規則見 [conventions.md](conventions.md#五提交與發版)）。
2. 改 `apps/expense_tracker/whats_new.txt`：三行以內、給使用者看，會出現在 App 的更新浮窗。
3. 在 [CHANGELOG.md](CHANGELOG.md) 加一節、在 [acceptance.md](acceptance.md) 加驗收項目。
4. PR 合併到 main：驗證通過後自動建置、簽章、發布；手機在 App 內就能更新。

版本號（versionCode）用工作流程的執行次數，新版一定蓋得過舊版；`APP_VERSION`、`APP_BUILD`、`APP_COMMIT` 會顯示在「設定 › 關於」。

## 除錯

- 除錯符號不在 APK 裡，每次建置存成 artifact `symbols-<commit>`（90 天），用 `flutter symbolize` 還原堆疊。
- 「設定 › 關於 › 效能與診斷」可看載入與影格時間、最近的背景錯誤，並匯出診斷紀錄。
