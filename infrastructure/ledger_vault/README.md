# ledger_vault

手機上的帳本檔案：`keyring.json` 和 `ledger.db` 放在一起。

- 第一次設定時建立 keyring；救援碼只回傳一次，不寫入任何檔案。
- 可用密碼、救援碼或裝置金鑰（Android Keystore）解鎖。裝置金鑰遺失時，密碼仍能打開。
- keyring 一律先寫成 `.new` 再改名覆蓋，當機時留下的不是舊的就是新的。第一次設定時寫到一半的檔案不算帳本，可以重新設定。
- `OpenVault.workspace`：取自帳本第一筆事件的 workspace。
- `OpenVault.updateKeys`：換密碼、加裝置、輪替備份金鑰後存回。
