# vault

> 金鑰與備份：密碼、救援碼、裝置金鑰、打開帳本的 vault、加密備份。

## 做什麼

金鑰階層（ADR-0001）：

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
- `DeviceKeyWrapper` 已由 Android 端實作：App 的 `KeystoreDeviceKey`（`lib/src/app/android/keystore.dart`）透過平台通道交給 `MainActivity.kt`，用需要指紋或臉部確認的 Keystore AES-GCM 金鑰包裝與解開。

帳本檔案（`keyring.json` 與 `ledger.db` 放在一起）：

- 第一次設定時建立 keyring；救援碼只回傳一次，不寫入任何檔案。
- 可用密碼、救援碼或裝置金鑰（Android Keystore）解鎖。裝置金鑰遺失時，密碼仍能打開。
- keyring 一律先寫成 `.new` 再改名覆蓋，當機時留下的不是舊的就是新的。第一次設定時寫到一半的檔案不算帳本，可以重新設定。
- `restore`：還原備份時先寫到暫存資料庫並通過 SQLite 完整性檢查，接著寫好新的 `keyring.json.new`，再換上資料庫，最後才把 keyring 改名就位。下次打開時（`_settle`）依留下的檔案收尾：暫存與資料庫都在就丟掉暫存，只剩暫存就換上，新 keyring 完整就採用；任何一步之間當機都開得回一本完整的帳本。
- `OpenVault.updateKeys`：換密碼、加裝置、輪替備份金鑰後存回。

備份格式 v3：帳本的每一筆資料（`EncryptedDatabase` 的每一列）分塊、gzip、用 keyring 的備份金鑰以 AES-256-GCM 加密，之後可附帶收據照片等檔案。

- 檔案開頭是明文標頭：備份 ID、時間、帳本的 `revision`、筆數、keyring（已包裝）、備份金鑰 epoch。每週備份用 `revision` 判斷帳本有沒有變動。
- 每一塊的 AAD 綁定標頭雜湊與塊的順序，換塊、刪塊、截斷、改標頭都會被拒絕。
- 擷取時一次讀出全部資料，備份是同一個時間點的帳本。
- 還原時 `accept` 先看每一筆，App 讀不懂的一筆會讓還原失敗（`invalidContent`），不會換上一本打不開的帳。
- 錯誤一律回報為 `BackupProblem`：格式錯、版本較新、驗證失敗、目標非空、內容無效。

## 對外入口

| 入口 | 內容 |
| --- | --- |
| `backup_security.dart` | keyring、`PasswordKdf`、救援碼、`DeviceKeyWrapper`（Android 端由 App 的 `KeystoreDeviceKey` 實作） |
| `ledger_vault.dart` | 建立、解鎖、`restore`、`OpenVault.updateKeys` |
| `ledger_backup.dart` | 備份的寫出、檢查與還原，錯誤為 `BackupProblem` |

## 不做什麼

- 不決定什麼時候備份、送去哪裡（App 的 `backup` 功能與 Android 的 `BackupWorker`）；不保存救援碼。
