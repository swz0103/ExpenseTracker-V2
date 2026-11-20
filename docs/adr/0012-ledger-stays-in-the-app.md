# ADR-0012：帳本暫不移出成純 Dart 套件

- 狀態：採用（2026-11-19）
- 相關：ADR-0003（分層規則）、ADR-0008（帳本聚合）

## 背景

`apps/expense_tracker/lib/src/core/ledger` 有 55 個檔、約 7,100 行，是整個 App 的資料核心。移到 `packages/` 成為純 Dart 套件，可以讓「帳本不碰畫面」由編譯器保證，也能用 `dart test` 單獨測試。要不要搬，先量再決定。

## 量測（2026-11-19，這台開發機）

| 項目 | 結果 |
| --- | --- |
| 帳本用到 Flutter 的檔案 | 6 個，全部只用 `package:flutter/foundation.dart`：`ChangeNotifier`、`ValueNotifier`、`Listenable`、`mapEquals` |
| 帳本用到 App 其他部分 | `core/formatting`（金額、日期、JsonFields）、`core/diagnostics`（錯誤紀錄、效能監看）、`core/models` |
| 帳本相關的 71 個測試檔，以 `flutter test` 跑 | 26.5 秒 |
| 單跑一個檔：`flutter test` ／ 純 Dart 套件的 `dart test` | 2.6 秒 ／ 1.0 秒 |

## 決策

現在不搬。

- **好處小。** 只有在單跑一個檔時省約 1.6 秒；整批測試本來就平行跑。
- **代價不小。** `Ledger` 本身是 `ChangeNotifier`，所有畫面都靠它更新；搬出去要另寫一套通知介面，再在 App 端轉接。錯誤紀錄、效能監看也得一起搬，或改成由外部注入。改動面廣，換來的只有上面那一點好處。
- **邊界改由規則守住。** `layers_test` 已規定帳本只能依賴 `text`、`diagnostics`、`time`；這次再加一條：帳本只能用 Flutter 的 `foundation.dart`，不能碰 `widgets`、`material` 或平台通道。這樣將來真的要搬時，不會比今天更難。

## 何時重新評估

符合任一項就重新評估：
- 帳本要給 App 以外的程式用（例如電腦版匯入工具、伺服器）。
- 帳本相關測試整批超過 60 秒。
- 帳本開始需要 `foundation.dart` 以外的 Flutter 程式庫。

## 後果

- 帳本留在 App 內，現有的 import 與測試不動。
- 新規則在 `layers_test`：`core/ledger` 只能 import `package:flutter/foundation.dart`。
