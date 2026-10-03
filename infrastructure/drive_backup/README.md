# drive_backup

把備份檔上傳到 Google Drive（`drive.file` 權限）。

- `DriveClient`：
  - 分塊續傳（Content-Range、308）；
  - token 被拒時自動換一次；
  - 網址只接受 `*.googleapis.com`；
  - 備份清單會略過壞掉的項目並計數。
- `CloudUploadQueue`（`cloud` schema 模組）：
  - session 存在資料庫，重開 App 會從 Drive 已收到的位置接著傳；
  - 上傳完成並核對大小與 SHA-256 後刪掉本機副本；
  - 失敗或卡住的上傳不擋新備份，可放棄或重試；
  - 保留最近 N 份時只依本機紀錄的時間，不信任 Drive 上可被改的屬性。
- 寫入走傳入的 `Exclusive`（`Bookkeeping.exclusive`），不會和記帳指令同時寫。
- `package:drive_backup/testing.dart`：模擬 Drive 的 `FakeDrive`，只供測試。
