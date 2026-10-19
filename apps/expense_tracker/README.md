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
| 根目錄 | 啟動、解鎖、日曆同步、平台通道、效能紀錄、錯誤說明。 | 以上全部 |

`test/layers_test.dart` 守住上表的方向：`model` 不能引用畫面或 `book`，`book` 不能引用頁面。

## 平台

- Android 通道在 `android/app/src/main/kotlin/`：Keystore 指紋金鑰、匯出與選取檔案、Google 日曆（`CalendarBridge.kt`）。
- 字型：Noto Sans TC 常用字子集，OFL 授權見 `fonts/LICENSE.txt`。
- 圖示：`tool/glyphs.py` 定義所有圖示並產生 `lib/src/look/glyphs.dart`，不要手改產生的檔案。

## 測試

- `flutter test`：模型、帳本對照、畫面、分層、啟動。
- `integration_test/bench_test.dart`：模擬器量測 3,600 筆的載入、捲動與存檔時間（`Emulator timings` 工作流程）。
