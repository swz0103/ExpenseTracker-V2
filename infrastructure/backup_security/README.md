# backup_security

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
