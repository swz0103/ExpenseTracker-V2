# ledger_vault

手機上的帳本檔案：`keyring.json` 和 `ledger.db` 放在一起。

- 第一次設定時建立 keyring；救援碼只回傳一次，不寫入任何檔案。
- 可用密碼、救援碼或裝置金鑰（Android Keystore）解鎖。裝置金鑰遺失時，密碼仍能打開。
- keyring 一律先寫成 `.new` 再改名覆蓋，當機時留下的不是舊的就是新的。第一次設定時寫到一半的檔案不算帳本，可以重新設定。
- `restore`：還原備份時先寫到暫存資料庫，通過 SQLite 完整性、外鍵與單一 workspace 檢查後才改名就位，最後才寫 keyring；任何一步失敗或當機都不會留下半套帳本，可以重來。
- `OpenVault.workspace`：建立或還原時存進資料庫（`vault` 模組），不再從事件推測；帳本含兩個以上 workspace 時拒絕開啟。
- `OpenVault.updateKeys`：換密碼、加裝置、輪替備份金鑰後存回。
