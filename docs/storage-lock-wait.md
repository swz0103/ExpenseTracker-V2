# 儲存排他權：等待上限與取消

狀態：Windows host 機制已驗證；Android 裝置、正式 App session 與背景工作協調仍待驗收。補充[生命週期契約](storage-lifecycle-contract.md) KEY-05，接續[控制紀錄加密](storage-control-protection.md)。

## 行為契約

`GenerationStore` 與 `LedgerStore` 的 `lockTimeout` 預設 10 秒；負值立即拒絕，零表示只嘗試取得一次。使用 monotonic stopwatch 計算等待時間，非阻塞 OS 排他鎖失敗時每次最多延後 25 ms 再試；不再無限阻塞。這是等待鎖的期限，不是整筆還原、密碼解鎖、DB 查詢或作業系統 I/O 的硬即時期限。

- 相同 isolate 的同一實際目錄已有操作：立即回報 `busy`，維持原契約，未增加佇列或重入。
- 合作的其他程序持鎖超過期限：回報 `lockTimeout`。
- `LockWaitCancellation.cancel()` 在取得鎖前被觀察到：回報 `lockCancelled`。剛取得鎖時再檢查一次，取消者釋放鎖後返回；尚未載入 catalog 或金鑰。
- 只重試已辨識的鎖競爭錯誤。Windows error 33 已實測；Linux／Android errno 11／13 為平台分支，仍待目標平台執行。其他 I/O 錯誤保留既有 `recoveryRequired` 邊界，不把損壞或權限錯誤當成持續忙碌。

取消 token 只控制等待階段。成功取得排他權並通過最後檢查後，操作繼續到可判定的結果；不承諾任意中斷 SQL、金鑰寫入或已提交還原。發布後回覆遺失仍依 operation receipt 重試判定，不回報「取消成功」掩蓋已提交結果。

Ledger 的 `restore`、`snapshot`、`backup`、`post`、`balance` 都能傳入同一種 token。還原的 envelope 解鎖可能先執行，取消不代表 Argon2id 計算中斷；備份取得 snapshot 後也不因 token 變更而中止 envelope 產生。正式 UI 尚未接取消按鈕。

## 驗證與資料保留

11 項新增儲存案例使用真正獨立持鎖程序，驗證：期限、等待中取消、期限內釋放後成功、零期限、首次建立、負值、取得鎖後取消、讀取入口取消與非競爭錯誤。失敗後核對 catalog bytes、key 數量與 loader 次數未變，釋放後可重試。

2 項 Ledger 整合案例核對取消後完整 snapshot 不變、同一財務操作正常重試只入帳一次，以及首次還原取消沒有建立目標、相同還原 ID 可再試。連同既有案例，儲存 55 項與 Ledger 27 項通過。取消前已建立目錄／lock 檔的等待者可能留下這兩者，不能宣稱完全沒有檔案系統副作用。

此項不提供公平排隊、跨 isolate 的 Dart 記憶體協調、非合作程序保護、App session drain、舊世代清理或 Android 斷電保證。所有 DB handle 仍須在內部 scope 完成前關閉；下一項處理首次控制建表中止復原。
