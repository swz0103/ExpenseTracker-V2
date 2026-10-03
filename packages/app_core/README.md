# app_core

應用層契約（ADR-0001）。不依賴任何儲存或 UI。

- `CommandRunner`：指令依序執行、不因忙碌而失敗。每個指令的 OperationKey、輸入與結果和業務寫入在同一交易內記錄；重試會拿到同一個結果，同一個 key 換了輸入則回 `AppFailure.operationConflict`。
- `UnitOfWork` / `WriteTransaction`：儲存層要實作的介面，含操作日誌與交易性 outbox。
- `AppFailure`：型別化錯誤，`diagnostic` 是不含使用者資料的穩定代碼。
- `Clock`：唯一的「現在」來源，測試用 `FixedClock`。
- `package:app_core/testing.dart`：`MemoryStore` 參考實作，新的儲存層必須通過同一組行為測試。
