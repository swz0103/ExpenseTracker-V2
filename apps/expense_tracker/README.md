# expense_tracker

> 記帳本 App（Flutter）。分層與依賴規則見 [architecture.md](../../docs/architecture.md)，寫法見 [conventions.md](../../docs/conventions.md)。

## 入口

| 檔案 | 用途 |
| --- | --- |
| `lib/main.dart` | 正式版：`app/bootstrap.dart` → 解鎖 → 加密帳本 |
| `lib/main_preview.dart` | 網頁預覽：範例帳本只在記憶體；正式入口碰不到它（`entry_test`） |

## 資料夾（`lib/src/`）

| 位置 | 內容 |
| --- | --- |
| `app/` | 啟動、底部分頁（`shell.dart`）、設定與更多的入口頁、Android 通道（`android/`）、網頁預覽（`demo/`） |
| `features/<功能>/` | `model/` 資料與服務、`forms/` 表單與面板、`ui/` 頁面 |
| `core/formatting/` | 金額、日期的文字格式 |
| `core/design_system/` | 設計系統：`theme.dart`（顏色 `AppColors`）、`type.dart`（字級）、`glyphs.dart`（圖示，產生的）、`components/`（元件） |
| `core/charts/` | 圖表 |
| `core/ledger/` | 帳本 `Ledger` 與資料型別；`persistence/sql_ledger_data_source.dart` 寫進加密檔 |
| `core/platform/` | 偏好設定、同步工作、開啟帳本、隱私 |
| `core/diagnostics/` | 錯誤紀錄、效能紀錄 |
| `core/messages/` | 共用的提示與錯誤文字 |
| `core/time/` | App 的時鐘 |
| `core/widgets/` | 認得帳本的共用元件 |
| `core/navigation/nav.dart` | 頁面（`AppRoute`）與 `Nav` |

測試的位置對應 `lib/`：`test/<lib/src 底下的路徑>_test.dart`；另有 `test/scenarios/`（跨功能情境）、`test/rules/`（全 App 的規則）、`test/support/`（共用工具與頁面清單）、`test/perf/`（效能）。

## 平台

- Android 端在 `android/app/src/main/kotlin/`，每塊能力一個 `ChannelHandler`；細節見 [android.md](../../docs/android.md)。
- 字型：Nunito ＋ Noto Sans TC（Regular／Bold，OFL 授權見 `fonts/`）；`font_coverage_test` 檢查沒有缺字。
- App 圖示原稿 `tool/app_icon.svg`；畫面裡用 `core/design_system/app_mark.dart` 畫同一個圖。

## 測試與工具

- `flutter test`：全部測試；頁面清單在 `test/support/places.dart`，新頁面加進去就有版面、無障礙與截圖。
- `tool/`：`move.py`（搬檔改 import）、`split.py`（拆長檔）、`glyphs.py`（產生圖示）、`test_ledger.py`（測試帳本）、`screenshots/`（截圖）。
- `integration_test/bench_test.dart`：模擬器量測載入、捲動、存檔時間。

指令見 [development.md](../../docs/development.md)。
