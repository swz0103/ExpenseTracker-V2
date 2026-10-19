# vault

金鑰與備份：密碼、救援碼、裝置金鑰、打開帳本的 vault、加密備份、排程備份服務與 Google Drive 傳輸。

每一節對應一個公開入口（`package:vault/<入口>.dart`），原本是獨立的套件。

## backup_security

基礎設施層（ADR-0001）：資料庫與備份的金鑰階層。

```
主密碼（NFC 正規化 → Argon2id）─┐
救援碼 ETR1-XXXX-…（32 bytes）──┼─ 包裝 → 主金鑰（隨機 32 bytes）─┬─ 包裝 → 資料庫金鑰（SQLCipher，終身不變）
裝置金鑰（Keystore＋生物辨識）──┘                                └─ 包裝 → 備份金鑰 epoch 1..n
```

- 改密碼、換救援碼、加減裝置只重寫對應的 slot，不碰資料。
- 備份金鑰輪替會新增 epoch；舊 epoch 仍可解開舊備份。
- 每個密文的 AAD 綁定 keyring id 與用途，搬移或交換 slot 會解密失敗。
- Argon2id 參數只由程式決定，檔案內的 policy id 必須完全相符；`PasswordKdf.insecureForTests` 寫出的 keyring 正式版不會接受。
- 解析時嚴格檢查欄位、長度與 canonical base64，任何偏差都是 `invalidFormat`。
- `DeviceKeyWrapper` 由 Android 端以 Keystore 實作（階段 4）。

## ledger_vault

手機上的帳本檔案：`keyring.json` 和 `ledger.db` 放在一起。

- 第一次設定時建立 keyring；救援碼只回傳一次，不寫入任何檔案。
- 可用密碼、救援碼或裝置金鑰（Android Keystore）解鎖。裝置金鑰遺失時，密碼仍能打開。
- keyring 一律先寫成 `.new` 再改名覆蓋，當機時留下的不是舊的就是新的。第一次設定時寫到一半的檔案不算帳本，可以重新設定。
- `restore`：還原備份時先寫到暫存資料庫，通過 SQLite 完整性、外鍵與單一 workspace 檢查後才改名就位，最後才寫 keyring；任何一步失敗或當機都不會留下半套帳本，可以重來。
- `OpenVault.workspace`：建立或還原時存進資料庫（`vault` 模組），不再從事件推測；帳本含兩個以上 workspace 時拒絕開啟。
- `OpenVault.updateKeys`：換密碼、加裝置、輪替備份金鑰後存回。

## ledger_backup

備份格式 v2：事件日誌分塊、gzip、用 keyring 的備份金鑰以 AES-256-GCM 加密。

- 檔案開頭是明文標頭：備份 ID、時間、日誌位置、keyring（已包裝）、備份金鑰 epoch。
- 每一塊的 AAD 綁定標頭雜湊與塊的順序，換塊、刪塊、截斷、改標頭都會被拒絕。
- 擷取不檢查商業規則，帳本有問題時也一定備得出來。
- 還原時把事件逐一重播到空的帳本，問題在這一步才會被發現。
- 錯誤一律回報為 `BackupProblem`：格式錯、版本較新、驗證失敗、目標非空、內容無效。

## backup_service

把整條備份流程串起來：

- `due`：判斷是否到了排程時間；帳本自上次備份後沒變就不備份。
- `backupNow`：寫出加密備份並放進上傳佇列。只需要備份金鑰，不需要密碼。
- `sync`：上傳到期的項目，全部成功後才依 `Retention` 清掉 Drive 上多餘的舊備份。
- `runScheduled`：排程用，一次做完「到期就備份、有 Drive 就上傳」，不丟例外；同帳號重疊執行會略過。App 在解鎖後與解鎖期間的定時器呼叫。
- `health`：最後一次成功上傳的時間、是否逾期、待上傳與失敗的筆數，以及上次排程失敗的原因（之後成功才清除）。
- `restore`：從 Drive 分段下載（每段 8 MiB，記憶體不隨檔案變大），核對大小與 SHA-256，再還原。檔案屬性裡的備份 ID 必須和加密標頭一致，被換成別份備份會被拒絕。
- `restoreFile`：從本機的備份檔還原，不需要 Drive。
- 兩者都還原到呼叫端給的 `RestoreTarget`；App 傳入 `LedgerVault.restore`，所以還原是全有或全無。

## drive_backup

把備份檔上傳到 Google Drive（`drive.file` 權限）。

- `DriveClient`：
  - 分塊續傳（Content-Range、308）；
  - token 被拒時自動換一次；
  - 網址只接受 `*.googleapis.com`；
  - 備份清單會略過壞掉的項目並計數；
  - `downloadTo`：用 Range 分段下載寫入檔案，核對大小與 SHA-256，不符就刪掉暫存檔（`DriveFailure.damaged`）。
- `CloudUploadQueue`（`cloud` schema 模組）：
  - session 存在資料庫，重開 App 會從 Drive 已收到的位置接著傳；
  - 上傳完成並核對大小與 SHA-256 後刪掉本機副本；
  - 失敗或卡住的上傳不擋新備份，可放棄或重試；
  - `Retention` 分代保留（預設最近 7 份、每週 4 份、每月 12 份），只依本機紀錄的時間，不信任 Drive 上可被改的屬性。
- 寫入走傳入的 `Exclusive`（`Bookkeeping.exclusive`），不會和記帳指令同時寫。
- `package:drive_backup/testing.dart`：模擬 Drive 的 `FakeDrive`，只供測試。
