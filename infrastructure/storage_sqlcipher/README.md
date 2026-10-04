# storage_sqlcipher

基礎設施層（ADR-0001）：單一 SQLCipher 加密資料庫，實作 `app_core` 的 `UnitOfWork`。

- 一個檔案、WAL、`synchronous=FULL`；崩潰復原交給 SQLite，不自行解讀 journal。
- `events` 只能新增、`operations` 不能改或刪（觸發器強制），和業務寫入同一交易提交。
- 開啟時檢查：函式庫必須是 SQLCipher（否則 `notEncrypted`）、金鑰正確（否則 `wrongKey`，錯誤訊息不含金鑰）、schema 不比程式新（否則 `newerSchema`）。
- Migration 只能往 `lib/src/schema.dart` 末尾新增，每一步和 `user_version` 在同一交易。
- `bin/crash_worker.dart` 給 SIGKILL 測試用，CI 會先編譯它。
