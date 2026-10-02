# 分塊快照容器原型主機證據（2026-10-02）

## 已完成範圍

- 以 `Stream<Map<String,Object?>>` 逐列輸入，不先 materialize 全部 authority rows。
- 依 row 數及 UTF-8 bytes 雙上限切成 canonical NDJSON chunks；每塊保存 ordinal、列數、bytes 與 SHA-256。
- manifest 固定 format／version／schema、table 順序、chunk 順序、總列數與總 bytes，另存 manifest SHA-256。
- 先寫唯一暫存目錄，完整自我驗證後才 rename 到目標；失敗清除暫存，既有目標拒絕覆寫。
- 驗證拒絕 digest 變更、缺塊、多餘檔案、table／chunk 順序變更、總數竄改、超大單列、非法名稱與 symlink／非一般檔案。
- `SnapshotCodec.captureChunked` 先核對現行 schema 與 authority，再在同一 read transaction 內讀取資料；每張表從實際 `PRAGMA table_info` 取得並驗證主鍵，使用 tuple keyset cursor 分頁串入 bounded writer，不以 `rowid` 猜測穩定順序。
- `SnapshotCodec.stageChunked` 先完整驗證容器，再於單一 transaction 逐塊寫入全新 staged database；每塊在讀取時重驗 manifest／chunk digest 與 canonical row。中途竄改會回滾先前列並清除 DB、WAL、SHM／journal，不碰既有 generation。
- 新增 authenticated chunk session：Argon2id 每次開啟只派生一次 password wrapping key，隨機 AES-256-GCM data key 同時由密碼與救援碼獨立包裝；manifest 與每個 chunk 使用獨立 nonce，並以 session header＋固定用途／ordinal 檔名作 AAD。
- authenticated directory 先驗證加密 manifest，再只接受它列出的精確 chunk 集合；ciphertext 竄改、metadata 竄改、用途交換與 chunk 對調均 fail closed。

## 驗證

- 分塊容器定向：9/9 通過；包含真實 v1 authority、`pageSize=1` 跨頁 capture、capture→stage→recapture bytes 等價、預先損壞與寫入中途竄改清理。
- authenticated container 定向：3/3；backup_envelope 完整套件：19/19。
- validated_restore 完整套件：143/143 通過；既有單檔 snapshot、各 schema、失敗注入、跨程序還原與 promotion 行為未切換。
- 靜態分析：零問題。

既有 Drift 多資料庫訊息仍是測試診斷；143 項 validated_restore assertion 全數通過，本批未隱藏警告。

## 安全邊界與未完成

- SHA-256 仍只用於內層完整性；外層原型已以 AES-256-GCM 綁定 session、manifest 與各 chunk 用途，密碼／救援雙路皆會驗證 authentication tag。
- SQLCipher 各表 stable primary-key capture 與逐塊 stage 到全新 database 已在原型完成；尚未接正式 generation promotion／中斷 journal。
- authenticated opener 目前會重建由呼叫端管理的暫時明文 bounded container；正式接線必須直接把已認證 rows 串入 SQLCipher stage，確保磁碟不保留明文 chunks。
- 尚未定義正式 portable envelope 版本、舊 App 拒絕規則、舊單檔唯讀匯入與中斷回復 journal。
- 因此本批不提高 5,000／50,000／16 MiB 上限，也不在正式 App／雲端備份使用此容器。
