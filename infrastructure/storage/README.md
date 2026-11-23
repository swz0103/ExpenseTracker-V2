# storage

> 加密的單一 SQLite 檔（SQLCipher）：App 的每一筆資料都是一列 JSON，依「架」（shelf）分開。

## 做什麼

- 打開時檢查函式庫是 SQLCipher（否則 `notEncrypted`）、金鑰正確（否則 `wrongKey`，訊息不含金鑰）、檔案不比程式新（否則 `newerSchema`）、同時只有一個連線（否則 `inUse`）。
- 一個檔案、WAL、`synchronous=FULL`（0.21.0 起）：存檔回來時資料已經寫進磁碟，App 當掉或存完瞬間斷電都不會少。模擬器實測（`apps/expense_tracker/integration_test/bench_test.dart` 的 `keep_one`，2026-11-21）：每存一筆 NORMAL 約 0.15 ms、FULL 約 0.45～1.1 ms；最慢的 5% NORMAL 約 1 ms、FULL 約 1.0～1.3 ms，都遠低於一格畫面的 16.7 ms，所以寫入留在畫面的執行緒上。
- `write` 是一個交易：全部寫入，或丟例外時全部不寫；每次寫入 `revision` 加一，備份用它判斷有沒有變動。
- `writeApart`：大批寫入（改商家名、合併分類、匯入、還原、重設金鑰）在背景 isolate 透過同一個連線寫成一個交易，畫面不停頓（DAT-03）。寫入期間 `revision` 回答開始前的值，其他讀寫丟 `StateError`，`close` 等它寫完；`idle` 在寫完時完成。SQLite 編譯為 `THREADSAFE=1`，連線可以交給另一條執行緒。
- 一筆資料改內容時保留原本的順序（`seq`）。
- 版面第 2 版（`createJournalTables`）：在同一個檔案裡加上分錄的資料表 `account`、`intent_index`（id、種類、日期、順序；內容仍在 `rows`，不重複）、`intent_stream`、`posting`、`month_sum`（與分錄在同一個交易內維護）。這些表都是**衍生**的：可以整批丟掉重建（`clear`），備份不帶（備份只讀 `rows`），被隔離的紀錄沒有分錄。`journal` 是 kernel 的 `PostingStore`；它記下自己由哪一版規則、紀錄的哪一個 `revision` 算出（`mark`，存在 `meta`，不算一次變動）。

## 對外入口

| 入口 | 內容 |
| --- | --- |
| `storage.dart` | `EncryptedDatabase`（`open`、`write`、`writeApart`、`idle`、`writingApart`、`revision`、`schema`、`journal`）、`RowWriter`（`put`、`drop`）、`RowChange`、`StoredRow`、`StorageKey`、`StorageUnavailable`、`SqlPostingStore` |
| `bin/crash_worker.dart` | 「寫到一半被強制結束」的測試用，CI 會先編譯它 |

## 不做什麼

- 不懂資料內容（JSON 由 App 解讀）；不懂分錄的意思（規則在 `packages/ledger/postings`）；不管金鑰（在 `vault`）。
