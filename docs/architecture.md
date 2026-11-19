# 架構

> 程式分成哪些模組、App 內部怎麼分層、資料怎麼流、外部資料從哪來。每條依賴規則都由測試守住，見最後一節。

## 模組

依賴只能往下。

| 模組 | 做什麼 | 依賴 |
| --- | --- | --- |
| `apps/expense_tracker` | App：畫面與唯一的帳本模型 | 以下全部 |
| `infrastructure/vault` | 金鑰、打開帳本、加密備份 | storage |
| `infrastructure/storage` | SQLCipher 加密檔，每筆資料一列 JSON | — |
| `infrastructure/market` | 證交所、櫃買中心收盤價，臺灣銀行牌告匯率 | core |
| `packages/domain` | 純計算規則：持股成本、台股費稅、信用卡週期與分期、貸款月付、CSV、電子發票 | core |
| `packages/core` | 金額、日期、匯率、ID、時鐘 | — |

`packages/*` 是純 Dart、不碰平台（`tooling/architecture_checks` 檢查）。不需要帳本狀態的計算一律放 `domain`，App 只呼叫。

## App 內部分層

```
lib/src/
  app/        組裝：啟動、底部分頁、設定與更多的入口頁、Android 通道、網頁預覽
  features/   每個功能一個資料夾：model/ forms/ ui/
  core/       所有功能共用：text look charts ledger platform ui，加上 nav.dart
```

### core 的十個部分

規則的唯一來源是 `test/support/layout.dart`；這張表照它寫。

| 部分 | 內容 | 可以用 |
| --- | --- | --- |
| `formatting/` | 金額、日期與共用詞彙（`Words`）的文字，`JsonFields`；純函式 | — |
| `time/` | `AppClock`：App 讀時間的唯一地方 | — |
| `diagnostics/` | `ErrorLog`（去識別化的錯誤記錄）、`PerformanceMonitor`（載入與影格時間） | time |
| `design_system/` | 設計系統：顏色、字級、圖示、動態、面板；元件在 `components/`（不知道帳本） | formatting |
| `charts/` | 圖表 | design_system、formatting |
| `ledger/` | 帳本 `Ledger`、資料型別、JSON、儲存；Flutter 只用 `foundation`（ADR-0012） | formatting、diagnostics、time |
| `platform/` | 偏好設定、背景同步工作、開啟帳本、隱私 | ledger、formatting、diagnostics、time |
| `messages/` | 告訴使用者的帳本數值與問題，集中一處 | ledger、formatting |
| `navigation/` | `Nav`、`AppRoute`、`AppRoutes`：打開頁面與流程 | ledger、platform |
| `widgets/` | 認得帳本的共用元件：紀錄列、選擇器、計算機、金額顯示 | 以上全部 |

### features

`accounts` `backup` `budgets` `categories` `debts` `entries` `import_export` `investments` `lock` `overview` `recurring` `reminders` `reports` `settings` `tags`

- `model/`：資料與服務，不碰畫面。
- `forms/`：表單與面板，別的功能可以打開它。
- `ui/`：頁面，只有自己的功能和 `app/` 用。
- 功能可以用別的功能的 `model/`、`forms/`，不能用 `ui/`；功能之間不能互相需要（含間接）。

### 導覽

- 頁面一律是 `core/navigation/nav.dart` 的一個 `AppRoute`，由 `Nav.open` 打開、`app/shell.dart` 決定畫哪一頁；返回鍵跟著 `AppRoute.parent`。
- 有自己「取消／完成」的整頁工作（排序帳戶、匯入）用 `openFullScreen`，這是全 App 唯一自己推路由的地方。
- 表單用底部面板（`showSheet`），設定細項與選擇器用中間面板（`showPanel`、`CenterPanel`）。

## 帳本與資料流

1. 啟動：`core/platform/startup.dart` 解鎖並打開加密帳本，讀進記憶體成一個 `Ledger`。
2. 讀：頁面讀 `Ledger` 的查詢（報表、規劃、信用卡在各自的 part 檔），並用 `ledger.watch(areas)` 只在相關資料區變動時重畫。
3. 寫：頁面呼叫 `Ledger` 的修改（紀錄、定期、設定各一個 part 檔）；畫面先生效，再交給 `Journal` 一個 `Batch`。
4. 存：`TableJournal` 把 `Batch` 寫成 `EncryptedDatabase` 一個交易；失敗時回報並重讀，畫面回到實際存下的狀態。

- 資料格式：每列 JSON 帶 `_v`；新欄位一律選填、有預設值。改變資料的存法時（不只是加欄位）寫一個升級函式，打開帳本時在**一個交易**裡完成、失敗就整個還原，並用舊格式的樣本資料列測試。
- 版本 2：紀錄、預算、定期交易、回收區、拆帳都以**分類 id** 存放，載入時換回名稱；分類改名只寫分類那一列。找不到對應分類的名稱（已刪除的）照原樣保留。舊帳本與舊備份打開時自動升級（`persistence/category_id_migration.dart`）。
- 能不能記（`EntryValidator`）只有一處；計算規則呼叫 domain，不在畫面重寫。

## 金鑰與備份

| 項目 | 做法 |
| --- | --- |
| 加密 | 帳本是 SQLCipher 檔；資料金鑰由密碼（Argon2id）、救援碼、指紋金鑰分別包裝，或免密碼存在 App 私有資料夾 |
| 備份格式 | v3：分塊、gzip、AES-256-GCM，AAD 綁定標頭雜湊與塊的順序；還原前先寫暫存庫並檢查 |
| Android 系統備份 | 只帶 `files/cloud/` 的加密帳本，給換手機時歡迎頁還原；一律寫入、不在畫面上出現（[ADR-0005](adr/0005-backup-choices.md)） |
| 雲端硬碟 | `drive.file` 權限，帳本有變就每天一份，收據照片另外開；留同一本帳本最新 5 份 |
| 手機資料夾 | 使用者選的資料夾，每天或每週；檔案直接寫在裡面，留最新 5 份 |
| 背景 | 離開 App 時把加密備份放進 `outbox/`，`BackupWorker` 不需金鑰就能送出 |

細節在 `infrastructure/vault/README.md` 與 [android.md](android.md)。

## 外部資料來源

每種資料只用一個免費、免帳號的來源；查不到就說查不到，不用 0 或舊值冒充（舊值會標示日期）。

| 資料 | 來源 | 備註 |
| --- | --- | --- |
| 上市收盤 | 證交所 `STOCK_DAY_ALL`；缺時查 `STOCK_DAY` 月報 | 價格保留十進位文字 |
| 上櫃收盤 | 櫃買中心每日收盤 | 抓不到沿用上次並標示 |
| 走勢圖 | 證交所 `STOCK_DAY`、櫃買 `tradingStock` 月報 | 讀過的月份存在 `prices/` |
| 匯率 | 臺灣銀行牌告 CSV | 外幣帳戶以即期買入估值 |

- 不做盤中行情：正式來源要付費簽約，免帳號的都不是正式介面。
- 匯率用 `FxRate` 存成正整數比例，換算到最後才取位（`half-away-from-zero`），不經 `double`。

## 由測試守住的規則

| 規則 | 測試 |
| --- | --- |
| 套件不碰平台、lockfile 一致、CI 涵蓋每個模組 | `tooling/architecture_checks` |
| core 的六部分只用允許的部分 | `test/rules/layers_test.dart` |
| 功能不用別人的 `ui/`、功能之間沒有循環 | `layers_test` |
| model 與帳本不碰畫面；帳本只用 Flutter 的 `foundation`；只有 `sql_ledger_data_source.dart` 碰儲存 | `layers_test` |
| 測試用 `Keys` 按按鈕 | `test/rules/test_rules_test.dart` |
| 只有 `openFullScreen` 推路由 | `layers_test` |
| 檔案 600 行以內 | `layers_test` |
| 捕捉到的錯誤要記錄、重新拋出或說明為何不用處理；不把原始例外放進訊息 | `test/rules/error_rules_test.dart` |
| 範例帳本只在 `app/demo/`，正式入口碰不到 | `layers_test`、`entry_test.dart` |
| 顏色、字級、按鈕只在 `core/design_system` | `test/rules/design_rules_test.dart`；色碼與字級數字由語法樹檢查（`app_syntax_test`） |
| Android 自動備份只帶 `files/cloud/` | `test/rules/backup_rules_test.dart` |
| 文件有摘要、150 行以內、連結都有效 | `tooling/architecture_checks/test/docs_test.dart` |
