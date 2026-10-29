# expense_tracker

記帳本 App（Flutter）。

## 入口

- `lib/main.dart`（正式）：`bootstrap.dart` → `Startup`（解鎖）→ 加密帳本。
- `lib/main_preview.dart`（網頁預覽）：示範資料只放在記憶體。`test/app/entry_test.dart` 走訪 import，確保正式入口碰不到預覽資料。

## 程式結構（`lib/src/`）

依功能分資料夾（[ADR-0002](../../docs/adr/0002-feature-folders.md)）。

| 資料夾 | 內容 | 可以引用 |
| --- | --- | --- |
| `core/ledger/` | 帳本 `Ledger`：資料型別、結帳週期、持股重播、報表、檢查、稅費；`TableJournal` 把每個改動（`Batch`）以一筆一列 JSON 寫進加密帳本。 | 只有自己與 `core/perf.dart`、套件 |
| `core/look/`、`core/charts/`、`core/ui/` | 主題、圖示、共用元件、圖表、選項與計算機、紀錄列。 | `core/` |
| `core/` 根目錄 | 導覽（`nav.dart`）、偏好設定、效能紀錄、錯誤說明、快速動作、螢幕隱私。 | `core/` |
| `features/<功能>/` | `model/`（資料與服務）、`ui/`（頁面）、`compose/`（表單）。功能有：entries（記一筆、紀錄）、accounts、cards、investments、budgets、recurring、reports、overview、more、categories、import、reminders、backup、lock、settings。 | `core/`、其他功能；不能引用 `app/` |
| `app/` | 組裝：`app.dart`、`bootstrap.dart`（正式）、`shell.dart`（底部分頁）、`android/`（Android 通道，每個部分一個檔案，`platform.dart` 一次匯出）、`demo/`（網頁預覽的範例帳本）。 | 全部 |

`test/app/layers_test.dart` 守住上表的方向。測試資料夾跟著分：`test/core/`、`test/features/<功能>/`、`test/app/`。

## 平台

- Android 通道在 `android/app/src/main/kotlin/`：Keystore 指紋金鑰、匯出與選取檔案、Google 日曆（`CalendarBridge.kt`）、通知（`Reminders.kt`）、桌面小工具（`SummaryWidget.kt`，`QuickWidget.kt` 是舊的一列版）、捷徑（`res/xml/shortcuts.xml`）、收據照片。
- 深色模式：`core/look/theme.dart` 的 `Shade` 同時帶淺色與深色值，畫的時候才決定，所以 const 元件也會跟著換；文字或圖示放在有色底上用 `Hue.onAccent`。
- 字型：Noto Sans TC（Adobe Source Han Sans 的繁中版）的 Regular／Bold 兩個字重，收錄 CJK 統一表意文字、擴充 A、全形符號等整段區間，蓋過畫面與使用者自己輸入的文字；OFL 授權見 `fonts/OFL-NotoSansTC.txt`。`test/app/font_coverage_test.dart` 檢查畫面文字沒有缺字。
- App 圖示（霧藍底、三根上升長條加成長箭頭）：`tool/app_icon.svg` 是原稿（108dp 畫布），`android/.../mipmap-*` 由它輸出；畫面裡用 `core/look/app_mark.dart` 畫同一個圖。
- 圖示：`tool/glyphs.py` 定義所有圖示並產生 `lib/src/core/look/glyphs.dart`，不要手改產生的檔案。

## 測試

- `flutter test`：模型、帳本對照、畫面、分層、啟動。
- `integration_test/bench_test.dart`：模擬器量測 3,600 筆的載入、捲動與存檔時間（`Emulator timings` 工作流程）。
