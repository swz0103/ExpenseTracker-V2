# storage

加密的單一 SQLite 檔（SQLCipher）：App 的每一筆資料（帳戶、分類、紀錄、預算、定期交易、最近刪除、收據、行情）都是一列 JSON，依「架」（shelf）分開。

- `RowStore.open`：檢查函式庫是 SQLCipher（否則 `notEncrypted`）、金鑰正確（否則 `wrongKey`，錯誤訊息不含金鑰）、檔案不比程式新（否則 `newerSchema`）、同時只有一個連線（否則 `inUse`）。
- 一個檔案、WAL、`synchronous=NORMAL`（WAL 下 App 當掉不會壞；只有存檔後瞬間斷電可能少最後一筆）；崩潰復原交給 SQLite。
- `write` 是一個交易：全部寫入，或丟例外時全部不寫。每次寫入 `revision` 加一，備份用它判斷有沒有變動。
- 一筆資料改內容時保留原本的順序（`seq`），讀回時順序和寫入時一樣。
- 結構只有一版（`RowStore.schema`），沒有 migration。
- `bin/crash_worker.dart` 給「寫到一半被強制結束」的測試用，CI 會先編譯它。
