# vault

金鑰與備份：密碼、救援碼、裝置金鑰、打開帳本的 vault、加密備份。

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
