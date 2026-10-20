# expense_tracker

記帳本 App（Flutter）。

## 入口

- `lib/main.dart`（正式）：`bootstrap.dart` → `Startup`（解鎖）→ 加密帳本。
- `lib/main_preview.dart`（網頁預覽）：示範資料只放在記憶體。`test/entry_test.dart` 走訪 import，確保正式入口碰不到預覽資料。

## 程式結構（`lib/src/`）

| 資料夾 | 內容 | 可以引用 |
| --- | --- | --- |
| `model/` | 畫面用的帳本 `Ledger`：資料型別、結帳週期、持股重播、報表、提醒。先即時套用改動，再交給 `Journal` 存檔。 | 只有 Dart 與 `domain` 的值 |
| `book/` | `VaultJournal`：把 `Ledger` 的改動轉成 `domain` 指令寫進加密帳本，再讀回來。 | model、套件 |
| `look/`、`charts/` | 主題、圖示、共用元件、圖表。 | model |
| `compose/` | 記一筆的表單與計算機。 | model、look |
| `pages/` | 各頁面。 | 以上全部 |
| 根目錄 | 啟動、解鎖、日曆同步、螢幕隱私、平台通道、效能紀錄、錯誤說明；`services.dart` 把金鑰與備份、日曆、螢幕隱私一起交給畫面。 | 以上全部 |

`test/layers_test.dart` 守住上表的方向：`model` 不能引用畫面或 `book`，`book` 不能引用頁面。

## 平台

- Android 通道在 `android/app/src/main/kotlin/`：Keystore 指紋金鑰、匯出與選取檔案、Google 日曆（`CalendarBridge.kt`）、通知（`Reminders.kt`）、桌面小工具（`QuickWidget.kt`）、捷徑（`res/xml/shortcuts.xml`）、收據照片。
- 深色模式：`look/theme.dart` 的 `Shade` 同時帶淺色與深色值，畫的時候才決定，所以 const 元件也會跟著換；文字或圖示放在有色底上用 `Hue.onAccent`。
- 字型：jf open 粉圓（Huninn）2.1 的常用字子集，加上程式裡用到的每個字；OFL 授權見 `fonts/OFL-Huninn.txt`。`test/font_coverage_test.dart` 檢查畫面文字沒有缺字。
- App 圖示（霧藍底、三根上升長條加成長箭頭）：`tool/app_icon.svg` 是原稿（108dp 畫布），`android/.../mipmap-*` 由它輸出；畫面裡用 `look/app_mark.dart` 畫同一個圖。
- 圖示：`tool/glyphs.py` 定義所有圖示並產生 `lib/src/look/glyphs.dart`，不要手改產生的檔案。

## 測試

- `flutter test`：模型、帳本對照、畫面、分層、啟動。
- `integration_test/bench_test.dart`：模擬器量測 3,600 筆的載入、捲動與存檔時間（`Emulator timings` 工作流程）。
