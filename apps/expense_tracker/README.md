# expense_tracker

新 App（Flutter）。畫面只透過 `AppSession` 呼叫 `bookkeeping` 指令，不直接碰儲存。

- 目前介面已拆成空殼，等底層完成後重做；`AppSession`、啟動流程、`vaultSession`（加密帳本）與 `format.dart`、`problems.dart`（金額格式、錯誤說明）保留給新介面使用。
- 兩個入口：
  - `lib/main.dart`（正式）：只走 `bootstrap.dart` → `Startup` → `ledger_vault` 加密帳本。Android 的帳本目錄在 4b-2 接上前，只有桌面開發版能啟動。
  - `lib/main_preview.dart`（網頁預覽）：示範資料放在記憶體（`preview.dart`）。
  - `test/entry_test.dart` 會走訪 import，確保正式入口碰不到記憶體預覽。
- 字型：Noto Sans TC 常用字子集，OFL 授權見 `fonts/LICENSE.txt`。
- 網頁預覽：`.github/workflows/web-preview.yml` 把 `flutter build web` 結果放在 `refs/previews/web`，再發佈成私人網頁。
