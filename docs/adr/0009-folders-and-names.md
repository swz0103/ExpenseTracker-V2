# ADR-0009：資料夾依職責分，名稱只用通用詞

- 狀態：採用（2026-11-15）；分階段實作
- 補充：ADR-0002、ADR-0003；名稱對照見 [naming.md](../naming.md)

## 背景

審查整個 `lib/src` 的結構，發現：

- `core/ledger/` 平放 20 個檔，資料型別、狀態、讀寫、儲存、JSON 全混在一起。
- `core/look`、`core/ui`、`core/look/kit` 的分界要靠讀過文件才知道；`look/headers.dart` 與 `look/kit/headers.dart` 兩份同名，`figures.dart`、`calendar.dart`、`notifications.dart`、`widgets.dart` 也各有同名的兩份。
- 功能資料夾的名稱和內容不符：`features/cards` 只有一個檔（信用卡是帳戶的一種）；`features/import` 裡的檔卻叫 `exchange*`；標籤頁放在 `categories`；`entries/ui/ledger_page.dart` 與 `Ledger` 類別撞名。
- `compose/` 與 Jetpack Compose 同名，但裡面其實是表單。
- `core/platform/problems.dart` 在不該有畫面的資料夾裡畫 `SnackBar`。
- `core/nav.dart` 單獨散在 `core/` 根目錄；測試資料夾 `test/core` 平放 30 個檔，和 `lib` 對不起來。

## 決策

1. **`core/` 分七部分，名稱用通用詞**：`formatting`（原 `text`）、`design_system`（原 `look`，元件放 `components/`）、`widgets`（原 `ui`，認得帳本的共用 widget）、`charts`、`ledger`（內部分法見 [ledger.md](../ledger.md#資料夾)）、`platform`、`navigation`（原 `nav.dart`）。可用的依賴方向不變：設計系統不知道帳本。
2. **功能資料夾固定 `model/`、`forms/`、`ui/`**（`compose/` 改名 `forms/`）。`model/` 不含畫面，`forms/` 放可被別的功能打開的表單與面板，`ui/` 只有自己的功能和 `app/` 用。
3. **功能依使用者看到的名稱分**，一個資料夾一個主題：

   | 現在 | 之後 |
   | --- | --- |
   | `features/cards/ui/card_page.dart` | `features/accounts/ui/card_page.dart` |
   | `features/import/` | `features/import_export/` |
   | `features/categories/ui/labels_page.dart`、`label_page.dart`、`model/project.dart` | `features/tags/ui/tags_page.dart`、`tag_page.dart`、`features/tags/model/tag_summary.dart` |
   | `features/entries/ui/ledger_page.dart`、`ledger_filter_sheet.dart` | `entries_page.dart`、`entries_filter_sheet.dart` |
   | `features/recurring/model/calendar.dart` | `recurring_schedule.dart` |
   | `features/reminders/model/notifications.dart` | `reminder_alerts.dart` |
   | `features/backup/model/keeper.dart`、`vault_keeper.dart`、`leftovers.dart` | `backup_manager.dart`、`encrypted_backup_manager.dart`、`file_cleanup.dart` |
   | `features/settings/model/services.dart` | `platform_services.dart` |
   | `core/look/headers.dart`、`look/kit/headers.dart` | `design_system/page_header.dart`、`components/heading.dart` |
   | `core/look/kit/figures.dart` | `components/figure_card.dart` |
   | `core/look/widgets.dart`、`kit.dart`（兩個轉出檔） | `design_system/design_system.dart`、`components/components.dart` |
   | `core/platform/problems.dart` | 畫面部分到 `core/widgets/problem_note.dart`，文字部分到詞彙庫 |
   | `app/android/*.dart`（15 檔） | `app/android/*_adapter.dart` |
   | `core/platform/perf.dart`、`connector.dart` | `performance_monitor.dart`、`sync_job.dart` |

4. **檔名後綴固定**（表見 [naming.md](../naming.md#檔名後綴)），一個檔案一個公開類別；`lib` 內不允許兩個同名檔案。
5. **測試資料夾與 `lib` 一一對應**：`lib/src/a/b.dart` 的測試是 `test/a/b_test.dart`；跨模組的情境測試放 `test/scenarios/`。
6. **搬移一律用 `tool/move.py`**（`git mv` 並改寫全部 import），一批一個提交，每批跑完整測試。

## 守住的方式

`layers_test` 新增三條：`lib` 內檔名不得重複；各資料夾只放允許的後綴；`test/` 的路徑要能對到 `lib/` 的檔案（或在 `scenarios/`）。

## 後果

- 想找一個東西，從它在畫面上的名稱就能猜到資料夾；同名的兩份檔案從搜尋結果裡消失。
- 搬檔不改行為，所以和帳本拆分分開提交；每批都能單獨還原。
- 測試與程式的對應讓「這個檔案有沒有測試」一眼可見，覆蓋率的缺口也容易補。
