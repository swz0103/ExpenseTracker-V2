# core

共用的值與指令執行：金額、匯率、日期、編號、名稱、錯誤，以及每個指令在一個交易裡完成的 CommandRunner。每個模組都建立在它上面。

每一節對應一個公開入口（`package:core/<入口>.dart`），原本是獨立的套件。

## foundation_values

所有套件共用的值型別，純 Dart，不依賴其他套件（只用 `uuid`）。

- `Money`／`Currency`：BigInt 最小單位，檢查有號 64 位元範圍；JSON 的金額是字串。
  - `Currency.of` 只接受 `Currency.supported` 裡的常用幣別；台幣、日圓、韓圓沒有小數。
  - 手動輸入超過小數位就拒絕；計算結果才取位（`half-away-from-zero-v1`，`quantizeRatio`）。
  - 分攤用最大餘數法（`largest-remainder-v1`），總和不差一分。
- `PublicId`（UUID v7）、`WorkspaceId`、`OperationId`、`OperationKey`：重試同一個意圖要用同一個 key。
- `BusinessDate`、`UtcInstant`：無效日期直接拒絕，不自動進位。`BankingCalendar` 處理假日順延。
- `FxRate`：用正整數比例保存的精確匯率，換算到最後才取位。
- `cleanName`／`nameKey`：名稱整理與比對（算字數、擋控制字元、統一全形半形與大小寫）。
- `resolveRedirects`：分類、標籤、商家共用的合併鏈解析。

## app_core

應用層契約（ADR-0001）。不依賴任何儲存或 UI。

- `CommandRunner`：指令依序執行、不因忙碌而失敗。每個指令的 OperationKey、輸入與結果和業務寫入在同一交易內記錄；重試會拿到同一個結果，同一個 key 換了輸入則回 `AppFailure.operationConflict`。
- `UnitOfWork` / `WriteTransaction`：儲存層要實作的介面，含操作日誌。
- `AppFailure`：型別化錯誤，`diagnostic` 是不含使用者資料的穩定代碼。
- `Clock`：唯一的「現在」來源，測試用 `FixedClock`。
- `package:app_core/testing.dart`：`MemoryStore` 參考實作，新的儲存層必須通過同一組行為測試。
