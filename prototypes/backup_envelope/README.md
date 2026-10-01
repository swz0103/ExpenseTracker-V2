# 雙解鎖備份 Envelope 原型

依據使用者 [2A 決策](../../docs/architecture/full-vision-baseline.md#decision-product-delivery) 與 [BACKUP 驗收案例](../../docs/foundation/foundation-acceptance.md)。本原型驗證加密封裝，不是完整資料庫備份產品。

## 封裝設計

每份備份產生獨立 256-bit 資料金鑰，以 cryptography 2.9.0 的 AES-256-GCM 加密 payload。密碼透過固定版本的 Argon2id 派生 wrapping key（19 MiB、2 iterations、parallelism 1、32 bytes），另以獨立隨機 256-bit 文字救援金鑰包裝同一資料金鑰。兩個 slot 各有 nonce 與 authentication tag，不保存原裝置金鑰。

Header 固定順序重新編碼並作為 AAD，額外綁定 password／recovery／payload 用途，防止跨 slot 混用。版本、cipher、KDF policy、salt 和 nonce 都參與驗證。救援文字有固定前綴與四 bytes SHA-256 checksum，檢查誤輸入；checksum 不取代 AEAD authentication。密碼與救援金鑰不可附在備份內。

解密前檢查格式、固定 nonce／tag／key 長度、版本與 KDF allowlist；不照任意輸入設定記憶體或運算成本。原型 payload 限 16 MiB、JSON 限 24 Mi 字元；建立密碼至少 12 code points、最多 1024 UTF-8 bytes。這些是原型政策，正式 ADR 仍須評估效能與使用流程，不能當成使用者已選的密碼規則。

## 驗證

封裝現可明確提供已保存的 `recoveryKey` 供後續備份沿用；未提供時仍每份生成新 key。資料 key／salt／nonce 每次重新產生，格式不變；錯誤已保存憑證不自動替換。實作範圍與尚未完成的正式設定檔見[BackupProfile 契約](../../docs/foundation/backup-profile-contract.md)。

```sh
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib bin test
dart analyze
dart test --reporter expanded
```

9 項測試包含兩種解鎖、錯誤密碼／救援碼、payload 與 header／wrapped key 竄改、slot 互換、未知版本／KDF、截斷、大小限制及獨立隨機值。兩個全新子程序各只接收一種 credential 的 fixture 檔案，均能還原相同 bytes；不靠父程序記憶體中的資料金鑰，也不把 credential 放在命令列參數值。

## 尚未通過的範圍

這是 host bytes round-trip，不是 Android 新裝置還原或完整 ledger snapshot 驗收。尚未完成正式備份 manifest、權威資料清單、資料庫一致快照、附件、migration／重建、還原前驗證與可恢復切換。CLI restore_probe 只寫測試目標，不可作正式覆寫入口。兩個 slot 彼此獨立；未使用的 slot 損壞不必阻止另一條有效救援路徑還原已驗證 payload。

密碼學使用既有函式庫，沒有自製 cipher 或 KDF。此結果不構成獨立安全稽核；Android 效能、平台實作、金鑰管理、記憶體保護與格式審查仍待完成。Dart managed memory 不宣稱已安全抹除所有敏感副本。

來源：[cryptography](https://pub.dev/packages/cryptography/versions/2.9.0)、[Argon2id API](https://pub.dev/documentation/cryptography/latest/cryptography/Argon2id-class.html)、[OWASP KDF 參數](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#argon2id)。
