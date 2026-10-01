# 首次控制資料庫初始化復原

狀態：階段 1 Windows host 原型；Android 程序中止及實際斷電仍待驗收。接續[控制紀錄加密](storage-control-protection.md)、[等待／取消](storage-lock-wait.md)，補充[KEY-01／KEY-03](storage-lifecycle-contract.md#8-必須執行的驗收)。

## 協定

先前直接在 `catalog.db` 建表，首次 transaction 中止會留下無法區分來源的不完整正式檔，故只能保留並停止。現在首次建立改走固定的 `catalog.init.db`：

1. 取得同一個生命週期排他權。沒有正式 catalog 時，目錄只允許 lock、初始化 stage 及其 SQLite journal；任何既有世代、未知檔案、orphan journal、WAL／SHM 均停止，不建立空 catalog。
2. stage 已存在就視為「已有需要原 key 的檔案」。loader 必須讀既有控制 key，遺失時不可新建；尚無 stage 的首次操作可建立或重用已保存的 key。
3. 開 stage，由 SQLite 處理未提交 transaction。只有 stage 的 `user_version=0` 且 `sqlite_master` 完全為空，才重新執行已知初始化 transaction；不刪檔、不刪 journal、不覆寫金鑰。
4. schema 1 fixture／schema 2 加密模式仍明確區分。驗證版本、完整性、欄位、store 身份，並要求 attempts 完全為空、唯一 active 參照為 NULL；有任何已發布或未結嘗試都不得拿來首次初始化。
5. 關檔後重新開啟與驗證，確認沒有遺留旁檔。stage 在同目錄 rename 成此前不存在的 `catalog.db`；再次正常開啟並驗證後，才允許帳本世代安裝。

這次 rename 只發布**空的控制資料庫**，不是財務還原完成點。真正帳本／slot 的發布仍是原 attempts 與 active 的同一 SQLite COMMIT。初始化階段不建立財務世代或世代 key。

## 中止、相容與拒絕

rename 前中止：正式 catalog 不存在，下次只接續已辨識的 stage。rename 後中止：stage 不存在，正常驗證既有完整 catalog 再接續。兩者同時存在視為衝突，不能依修改時間選一個。rename 回覆遺失由下一次實際路徑判定，不嘗試反向 rename。

既有正式 catalog 仍只接受完整已知 schema。先前版本留下的零版本 `catalog.db` 不自動搬到 stage 或清空；保留並要求復原，避免把正式資料損壞誤認成首次啟動。完整舊 catalog 相容，沒有改控制 schema 2、Ledger schema 3 或 backup format 2。

未知版本、額外欄位、非空 stage、store 身份錯誤、密文破壞、必要 key 遺失均拒絕且保留；已有世代但遺失 catalog 的規則沒有放寬。stage 名稱只是生命週期角色，不是跳過資料驗證的信任標記。

## 證據與未完成項目

Windows host 測試涵蓋八個首次建立退出點：key 保存、開 stage、建表 transaction 內、stage 已關閉、重開驗證後、rename 前、rename 後、正式開啟後。重試沿用同一控制 key，未提前發布帳本，再由獨立程序完成原安裝。

另核對舊版不完整正式 catalog 保留、各種無效 stage、遺失 key、兩檔衝突、遺留世代與 orphan 旁檔拒絕。密碼與文字救援兩路各在三個初始化邊界中止，以乾淨子程序重試核對完整帳務 snapshot、115.00 餘額及安裝去重。最新結果與 PR 見[工作進度](../work-progress.md)。

此證據來自可控制的程序退出，不是實際斷電／磁碟故障。rename 的裝置耐久性、Android journal recovery、平台 key 可用性、正式 session 協調、既有損壞 catalog 的使用者復原 UI 仍未驗收；不因此宣稱階段 1 已完成。
