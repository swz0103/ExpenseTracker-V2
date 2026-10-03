# expense_tracker

新 App（ADR-0001 階段 4）。畫面只透過 `AppSession` 呼叫 `bookkeeping` 指令，不直接碰儲存。

- 目前三個分頁：帳戶（淨資產、餘額、新增帳戶）、記一筆（收入／支出）、本月（收支合計、最近紀錄，長按可沖銷）。
- 資料暫存在記憶體（`package:bookkeeping/memory.dart`），預覽版附示範資料；Android 版之後改接 `ledger_sqlcipher`。
- 字型：Noto Sans TC 常用字子集（Big5 常用字），OFL 授權見 `fonts/LICENSE.txt`。
- 網頁預覽：`.github/workflows/web-preview.yml` 把 `flutter build web` 結果放在 `refs/previews/web`，再發佈成私人網頁。
