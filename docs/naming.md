# 命名

> 名稱只用業界通用詞，不自創；現有的自創名稱對照到通用詞，並照表改掉。新增類別、資料夾、檔名前先查這份。

## 規則

1. **先找正式用語再命名。** 來源依序是：Dart／Flutter 官方、Android 官方、領域驅動設計（Evans）、《企業應用架構模式》（Fowler）、會計與證券的正式用語。找不到才自創，並寫進本文件的「例外」。名稱越正規越好：能用正式術語就不用口語。
2. **名稱說它是什麼，不說它怎麼做。** `Repository` 不叫 `Book`，`UnitOfWork` 不叫 `ChangeSet`。
3. **不用縮寫**（`Perf`、`Cfg`、`Mgr`），用完整的英文詞；通用縮寫（`Id`、`Json`、`Csv`、`Url`）除外。
4. **同一個資料概念，程式、資料夾、檔名用同一個詞**：資料叫 `tag`，功能資料夾就叫 `tags`，不叫 `labels`。
5. **一個概念一個詞。** 同一件事不在不同檔案用不同詞；詞彙表是唯一來源。
6. **檔名後綴固定**，見下表；一個檔案一個公開類別，檔名是類別名的 snake_case。
7. 改名由 `tool/move.py` 與分析器完成，改完由 `naming_test` 禁止舊名重新出現。

## 檔名後綴

| 後綴 | 是什麼 | Flutter 對應 |
| --- | --- | --- |
| `_page` | 一整頁，對應一個 route | `Page`／`Scaffold` |
| `_sheet` | 底部面板 | `showModalBottomSheet` |
| `_dialog` | 中央浮動面板 | `showDialog` |
| `_section` | 頁面裡的一段 | — |
| `_form` | 表單的狀態與驗證（不含畫面） | — |
| `_editor` | 編輯一筆紀錄的表單畫面 | — |
| `_card`、`_tile` | 清單或網格裡的一項 | `Card`、`ListTile` |
| `_repository` | 擁有一種紀錄的記憶體狀態 | Repository 模式 |
| `_service` | 沒有自己的狀態、由別處的狀態算出結果 | 領域服務 |
| `_commands` | 一組寫入指令，協調多個 Repository | CQRS Command |
| `_adapter` | 把平台或外部系統接到 App 定義的介面 | Ports and Adapters |
| `_data_source` | 資料實際存放的位置 | Flutter／Android data source |

## 詞彙表

左欄是現在程式裡的自創名稱，右欄是改成的通用詞。

### 帳本內部

| 現名 | 通用名 | 依據 |
| --- | --- | --- |
| `EntryBook`、`Accounts`、`Categories`、`Budgets`、`Recurrences`、`Trash`（狀態擁有者） | `EntryRepository`、`AccountRepository`、`CategoryRepository`、`BudgetRepository`、`RecurringRepository`、`TrashRepository` | DDD Repository |
| `Drafts`、`Receipts`（`attachments.dart`） | `DraftRepository`、`ReceiptRepository` | DDD Repository |
| `Market`（收盤價、匯率） | `MarketDataRepository` | `infrastructure/market` 已用 MarketData |
| `Holdings`、`Portfolio` | `HoldingRepository`、`Portfolio`（沿用，證券正式用語） | 證券 |
| `Ledger` 上直接寫入的指令（`add`、`mergeCategory`…） | `EntryCommands`、`AccountCommands`、`CategoryCommands`、`BudgetCommands`、`RecurringCommands`、`HoldingCommands`、`AttachmentCommands` | CQRS Command |
| `Balances`、`CardStatements`、`Planning`、`Reports` | `BalanceService`、`StatementService`、`BudgetService`、`RecurringService`、`ReportService` | DDD Domain Service |
| `ChangeSet`、`_before`／`_since` | `UnitOfWork` | Fowler PoEAA |
| `QueryMemo`、`_remember`／`_forget`、`_memo` | `QueryCache` | 快取 |
| `Area` | `Topic` | 發佈／訂閱 |
| `Batch` | `WriteBatch` | Firestore、Android |
| `Shelf` | `Collection` | Firestore |
| `Journal`、`TableJournal`、`JournalFailure` | `LedgerDataSource`、`SqlLedgerDataSource`、`DataSourceException` | data source |
| `RowStore`（`infrastructure/storage`） | `EncryptedDatabase` | 描述它是什麼 |
| `checks.dart`（`EntryChecks`） | `EntryValidator` | 驗證 |
| `records.dart` 與 `records_recurring.dart` | `models/`（依型別拆檔） | MVVM model |

### 資料夾與平台

| 現名 | 通用名 | 依據 |
| --- | --- | --- |
| `core/look` | `core/design_system` | 設計系統 |
| `core/look/kit` | `core/design_system/components` | 元件庫 |
| `core/ui` | `core/widgets` | 認得帳本的共用 widget |
| `core/text` | `core/formatting` | 格式化 |
| `core/nav.dart`、`Place`、`Section`、`SettingsPart`、`Pages`、`openFlow` | `core/navigation/`、`AppRoute`（`Place` 的子類別改成 `*Route`）、`openFullScreen` | Flutter Route |
| `compose/`（功能裡的表單） | `forms/` | 與 Jetpack Compose 撞名 |
| `Hue` | `AppColors` | Flutter 慣例 |
| `*Part.kt`（Kotlin 通道處理） | `*Handler.kt` | `MethodCallHandler` |
| `app/android/*.dart` | `app/android/*_adapter.dart` | Ports and Adapters，已有 `NotifyPort`、`CalendarPort` |
| `Keeper`、`VaultKeeper` | `BackupManager`、`EncryptedBackupManager` | Manager |
| `Services`（`settings/model/services.dart`） | `PlatformServices` | 描述內容 |
| `Connector` | `SyncJob` | 它代表一件對外同步的工作與其狀態（Android WorkManager 的 Job 概念） |
| `Perf` | `PerformanceMonitor` | 不用縮寫 |
| `features/import`（檔名 `exchange*`） | `features/import_export` | 正式名稱 |
| `features/categories` 裡的標籤頁、`Project` | `features/tags`、`TagSummary` | 資料叫 tag |
| `leftovers.dart` | `file_cleanup.dart` | 描述動作 |

### 已是通用詞，保留

`Ledger`、`Entry`、`Account`、`Category`、`Budget`、`Holding`、`Lot`、`Outbox`（Outbox 模式）、`Preferences`、`Clock`、`Money`、`Currency`、`Statement`、`Instalment`。

## 例外

沒有。若真找不到通用詞，在這裡登記：名稱、為什麼找不到、它的定義。

## 守住的方式

`naming_test`（改名完成後新增）掃描 `lib/` 與 `test/`，出現左欄的舊名就失敗；檔名後綴由 `layers_test` 檢查各資料夾只放允許的後綴。
