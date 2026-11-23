# vault

> 金鑰與備份：密碼、救援碼、裝置金鑰、打開帳本的 vault、加密備份。

## 做什麼

金鑰階層（ADR-0001）：

```
主密碼（NFC 正規化 → Argon2id）──┐
備份密碼（選用，同上）───────────┤
救援碼 ETR1-XXXX-…（32 bytes）───┼─ 包裝 → 主金鑰（隨機 32 bytes）─┬─ 包裝 → 資料庫金鑰（SQLCipher）
裝置金鑰（Keystore＋生物辨識）───┘                                └─ 包裝 → 備份金鑰 epoch 1..n
```

- 密碼政策只有一處：`PasswordPolicy.standard`（暫定：至少 8 個字、不能全是數字；待擁有者決定）。設定密碼與備份密碼都經過它；以前設的較短密碼仍可解鎖。
- 改密碼、換救援碼、設定備份密碼、加減裝置只重寫對應的 slot，不碰資料；舊的 keyring（例如舊備份裡的）配舊密碼仍能打開舊的金鑰。
- `UnlockedKeyring.reset` 換掉全部金鑰：新的主金鑰與資料庫金鑰、舊 epoch 以新主金鑰重新包裝並新增一個 epoch、新的救援碼；裝置與備份密碼要重新設定。`LedgerVault.resetKeys` 把資料庫逐筆複製到以新金鑰加密的新檔、收據照片與 inbox 金鑰重新封裝，與還原相同的暫存 → 檢查 → 換入流程。
- 備份金鑰輪替會新增 epoch；舊 epoch 仍可解開舊備份。
- 每個密文的 AAD 綁定 keyring id 與用途，搬移或交換 slot 會解密失敗。
- Argon2id 參數只由程式決定，檔案內的 policy id 必須完全相符；`PasswordKdf.insecureForTests` 寫出的 keyring 正式版不會接受。
- 解析時嚴格檢查欄位、長度與 canonical base64，任何偏差都是 `invalidFormat`。
- `DeviceKeyWrapper` 已由 Android 端實作：App 的 `KeystoreDeviceKey`（`lib/src/app/android/keystore_adapter.dart`）透過平台通道交給 `MainActivity.kt`，用需要指紋或臉部確認的 Keystore AES-GCM 金鑰包裝與解開。

帳本檔案（`keyring.json` 與 `ledger.db` 放在一起）：

- 第一次設定時建立 keyring；救援碼只回傳一次，不寫入任何檔案。
- 可用密碼、救援碼或裝置金鑰（Android Keystore）解鎖。裝置金鑰遺失時，密碼仍能打開。
- keyring 一律先寫成 `.new` 再改名覆蓋，當機時留下的不是舊的就是新的。第一次設定時寫到一半的檔案不算帳本，可以重新設定。
- `restore`：還原備份時先寫到暫存資料庫並通過 SQLite 完整性檢查，備份帶的收據照片寫到 `files.restore/`；接著寫好新的 `keyring.json.new`，再換上資料庫、把暫存的檔案逐一換入（被換掉的先移到 `files.replaced/`），最後才把 keyring 改名就位。下次打開時（`_settle`）依留下的檔案收尾：暫存與資料庫都在就丟掉暫存（連同暫存的檔案），只剩暫存就換上，新 keyring 完整就把檔案換完並採用；任何一步之間當機都開得回一本完整、照片也屬於它的帳本。
- `OpenVault.updateKeys`：換密碼、加裝置、輪替備份金鑰後存回。

備份格式 v5：帳本的每一筆資料（`EncryptedDatabase` 的每一列）分塊、gzip、用 keyring 的備份金鑰以 AES-256-GCM 加密，之後可附帶收據照片等檔案。v3、v4 仍可讀取（`test/ledger_backup/fixtures/v4.etbk` 是 v4 寫的備份）。

- 檔案開頭是明文標頭：備份 ID、時間、帳本的 `revision`、筆數、keyring（`Keyring.exported`：不含 App 密碼與裝置的 slot，只能用救援碼或備份密碼打開；v3 還帶著密碼 slot）、備份金鑰 epoch；v5 起還有帳本版本（`book`）與 layout（`layout`）。每個版本的標頭欄位固定，多一個少一個都拒絕。每週備份用 `revision` 判斷帳本有沒有變動。
- 寫入與讀取用同一個區塊上限（`maxFrame`）：資料依大小分塊，大檔案切成多段（`more`），寫得出來的備份一定讀得回來。
- 每一塊的 AAD 綁定標頭雜湊與塊的順序，換塊、刪塊、截斷、改標頭都會被拒絕。
- 擷取時用 `readApart` 在背景 isolate 一次讀出全部資料，接著在同一個 isolate 壓縮加密，備份是同一個時間點的帳本，畫面不停頓（D41）。
- 還原時把標頭的帳本版本寫回，同版本的備份還原後不會再跑一次升級，也不會多存一份升級前備份（D26）；layout 比這版新的備份拒絕還原（`unsupportedVersion`）。
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
