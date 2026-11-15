# storage

> 加密的單一 SQLite 檔（SQLCipher）：App 的每一筆資料都是一列 JSON，依「架」（shelf）分開。

## 做什麼

- 打開時檢查函式庫是 SQLCipher（否則 `notEncrypted`）、金鑰正確（否則 `wrongKey`，訊息不含金鑰）、檔案不比程式新（否則 `newerSchema`）、同時只有一個連線（否則 `inUse`）。
- 一個檔案、WAL、`synchronous=NORMAL`：App 當掉不會壞，只有存檔後瞬間斷電可能少最後一筆。
- `write` 是一個交易：全部寫入，或丟例外時全部不寫；每次寫入 `revision` 加一，備份用它判斷有沒有變動。
- 一筆資料改內容時保留原本的順序（`seq`）。

## 對外入口

| 入口 | 內容 |
| --- | --- |
| `storage.dart` | `RowStore`（`open`、`write`、`revision`、`schema`）、`RowWriter`（`put`、`drop`）、`StoredRow`、`StorageKey`、`StorageUnavailable` |
| `bin/crash_worker.dart` | 「寫到一半被強制結束」的測試用，CI 會先編譯它 |

## 不做什麼

- 不懂資料內容（JSON 由 App 解讀）；不管金鑰（在 `vault`）；結構只有一版，沒有 migration。
