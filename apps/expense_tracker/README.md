# expense_tracker

新 App（Flutter）。畫面只透過 `AppSession` 呼叫 `bookkeeping` 指令，不直接碰儲存。

- 目前介面已拆成空殼，等底層完成後重做；`AppSession`、啟動流程、`vaultSession`（加密帳本）與 `format.dart`、`problems.dart`（金額格式、錯誤說明）保留給新介面使用。
- 網頁預覽走記憶體帳本（`package:bookkeeping/memory.dart`）；Android 版接 `ledger_vault`＋`ledger_sqlcipher`。
- 字型：Noto Sans TC 常用字子集，OFL 授權見 `fonts/LICENSE.txt`。
- 網頁預覽：`.github/workflows/web-preview.yml` 把 `flutter build web` 結果放在 `refs/previews/web`，再發佈成私人網頁。
