# storage

> 加密的單一 SQLite 檔（SQLCipher）：App 的每一筆資料都是一列 JSON，依「架」（shelf）分開。

## 做什麼

- 打開時檢查函式庫是 SQLCipher（否則 `notEncrypted`）、金鑰正確（否則 `wrongKey`，訊息不含金鑰）、檔案不比程式新（否則 `newerSchema`）、同時只有一個連線（否則 `inUse`）。
- 一個檔案、WAL、`synchronous=FULL`（0.21.0 起）：存檔回來時資料已經寫進磁碟，App 當掉或存完瞬間斷電都不會少。模擬器實測（`apps/expense_tracker/integration_test/bench_test.dart` 的 `keep_one`，2026-11-21）：每存一筆 NORMAL 約 0.15 ms、FULL 約 0.45～1.1 ms；最慢的 5% NORMAL 約 1 ms、FULL 約 1.0～1.3 ms，都遠低於一格畫面的 16.7 ms，所以寫入留在畫面的執行緒上。
- `write` 是一個交易：全部寫入，或丟例外時全部不寫；每次寫入 `revision` 加一，備份用它判斷有沒有變動。
- `writeApart`：大批寫入（改商家名、合併分類、匯入、還原、重設金鑰）在背景 isolate 透過同一個連線寫成一個交易，畫面不停頓（DAT-03）。寫入期間 `revision` 回答開始前的值，其他讀寫丟 `StateError`，`close` 等它寫完；`idle` 在寫完時完成。SQLite 編譯為 `THREADSAFE=1`，連線可以交給另一條執行緒。
- `readApart`：在背景 isolate 透過同一個連線，以一個讀取交易讀出全部資料、`revision`、帳本版本（`bookVersionKey`）與 layout（`StoreSnapshot`），再在那個 isolate 上接著做事（備份的壓縮與加密），資料不回到畫面的執行緒（D41）。讀取期間這裡仍可讀、不可寫（寫入丟 `StateError`，要等 `idle`）；資料讀完就放開，之後的工作不擋寫入。
- 一筆資料改內容時保留原本的順序（`seq`）。

## 對外入口

| 入口 | 內容 |
| --- | --- |
| `storage.dart` | `EncryptedDatabase`（`open`、`write`、`writeApart`、`readApart`、`idle`、`busyApart`、`revision`、`schema`、`bookVersionKey`）、`RowWriter`（`put`、`drop`）、`RowChange`、`StoredRow`、`StoreSnapshot`、`StorageKey`、`StorageUnavailable` |
| `bin/crash_worker.dart` | 「寫到一半被強制結束」的測試用，CI 會先編譯它 |

## 不做什麼

- 不懂資料內容（JSON 由 App 解讀）；不管金鑰（在 `vault`）；結構只有一版，沒有 migration。
