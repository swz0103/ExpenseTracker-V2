# 分塊快照容器原型主機證據（2026-10-02）

## 已完成範圍

- 以 `Stream<Map<String,Object?>>` 逐列輸入，不先 materialize 全部 authority rows。
- 依 row 數及 UTF-8 bytes 雙上限切成 canonical NDJSON chunks；每塊保存 ordinal、列數、bytes 與 SHA-256。
- manifest 固定 format／version／schema、table 順序、chunk 順序、總列數與總 bytes，另存 manifest SHA-256。
- 先寫唯一暫存目錄，完整自我驗證後才 rename 到目標；失敗清除暫存，既有目標拒絕覆寫。
- 驗證拒絕 digest 變更、缺塊、多餘檔案、table／chunk 順序變更、總數竄改、超大單列、非法名稱與 symlink／非一般檔案。
- `SnapshotCodec.captureChunked` 先核對現行 schema 與 authority，再在同一 read transaction 內讀取資料；每張表從實際 `PRAGMA table_info` 取得並驗證主鍵，使用 tuple keyset cursor 分頁串入 bounded writer，不以 `rowid` 猜測穩定順序。

## 驗證

- 分塊容器定向：6/6 通過；新增真實 v1 authority、`pageSize=1` 的跨頁 stable primary-key capture／verify 案例。
- validated_restore 完整套件：137/137 通過；既有單檔 snapshot、各 schema、失敗注入、跨程序還原與 promotion 行為未切換。
- 靜態分析：零問題。

既有 Drift 多資料庫訊息仍是測試診斷；137 項 assertion 全數通過，本批未隱藏警告。

## 安全邊界與未完成

- SHA-256 是完整性 digest，不是攻擊者不可偽造的 authentication。正式格式必須以密碼／救援資料金鑰對完整 manifest 與 chunk 集合做 authenticated encryption／MAC 綁定。
- SQLCipher 各表的 stable primary-key capture 已在原型完成；尚未把 chunks 逐塊 stage 到全新 generation。
- 尚未定義正式 portable envelope 版本、舊 App 拒絕規則、舊單檔唯讀匯入與中斷回復 journal。
- 因此本批不提高 5,000／50,000／16 MiB 上限，也不在正式 App／雲端備份使用此容器。
