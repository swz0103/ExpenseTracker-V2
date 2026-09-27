# Ledger 與加密世代整合原型

狀態：Windows host 固定資料整合驗證，非可供日常使用的 App。依賴 [DB／key 配對原型](../storage_generation/README.md)，遵守[生命週期契約](../../docs/storage-lifecycle-contract.md)。本項不改 CORE 範圍，也不表示架構 Freeze。

## 版本邊界

- 舊路徑維持財務 schema 2、snapshot format 1，既有七張權威表與三個 module version 不變。
- 新路徑明確指定 `StorageBinding`，使用財務 schema 3，新增 `storage_identity`，綁定 generation、slot、安裝 operation 與初始輸入摘要。schema 1／2 → 3 的升級在交易內完成；重開已存在的 schema 3 時只能核對，不能覆寫身份。
- 新 snapshot format 2／schema 3 加入 `local_identity: 1` manifest。這表示本機身份的重建政策，不包含該表的任何列。可攜內容仍完整保存 accounts、events、legs、openings、allocations、receipts、audit 七表。
- 新 codec 可匯入 format 1，再轉成已知 format 2；舊 codec 拒絕 format 2。未知 module、欄位、表、schema 或本機身份混入 portable tables 都拒絕。欄位排序正規化後才比較輸入摘要。
- 新世代由目標建立獨立 key slot 與本機身份，不從備份繼承來源身份。檢查 active DB 時先唯讀核對 schema 3，再進行完整財務／身份驗證，不能以開檔為由偷偷升級不符合版本的檔案。

## 完整資料路徑

`LedgerStore.restore` 驗證 envelope 的密碼或救援金鑰 → 正規化 portable snapshot → `GenerationStore` 保留舊組合、建立新 key slot → 全部七表匯入新加密 DB → 重開並核對全部資料與初始摘要 → 控制紀錄的一次交易提交發布目前配對。

安裝摘要用來判斷同一 restore operation 的輸入是否相同。它不是持續變動帳本的內容摘要：發布後的合法入帳會改變資料，後續開檔以本機身份、SQLCipher 完整性及財務 invariant 核對。再次提交舊還原操作回傳原 receipt，不把新增交易清掉或重新啟用舊世代。

`post`、`balance`、snapshot 與 restore 共用生命週期鎖；原型公開 facade 的資料庫連線都在回傳前關閉。底層 `withCurrent` 是內部 adapter scope，呼叫者不得保留 handle。這仍不是正式 App 的 reactive stream／背景工作／活躍連線租約實作。

## 驗證

23 項整合案例涵蓋：

- 舊備份全部權威列相同、100 + 20 − 5 = 115、原財務操作 replay 不重複入帳。
- 新入帳 7 後餘額 122，再備份／還原保留全部新舊資料與 replay；重送舊 restore 不清除新交易。
- 舊／新 snapshot 各自使用密碼與救援金鑰，在獨立子程序完成還原；新版測試先刪除來源 DB 與 key 目錄，再啟動目標程序並比較完整 snapshot。
- 七處程序中止：reserved、keySaved、匯入 accounts 後（財務 transaction 尚未 commit）、staged、validated、publishing、published。提交前保留舊帳本，提交後保留新帳本，再試不混用 key；保留舊 DB／slot。
- 未知 manifest／表／欄位、財務不一致、錯誤密碼／身份與 generated column 拒絕。
- active DB 的 schema 2／99 拒絕且檔案不變；加密 schema 2 → 3 的身份寫入故障完整回滾並可再試。

```powershell
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib bin test
dart analyze
dart build cli --target bin/ledger_worker.dart --output .dart_tool/worker
dart test --reporter expanded
```

worker 必須先編譯再跑測試，避免 Windows SQLCipher DLL 被測試程序占用。全部資料都是擁有明確清理範圍的 fixture。

## 未通過的 gate

FixtureKeySlots 仍以明文 key 檔測試，**不得用於真實財務資料**。預設相容模式沿用明文控制紀錄；後續可明確提供 `CatalogProtection`，以獨立 key 加密控制 DB 和摘要。新增兩項密碼／救援新程序整合案例，連同原有 23 項共 25 項通過。身份、初始化中止與平台限制見[控制紀錄加密邊界](../../docs/storage-control-protection.md)；不能把舊模式摘要視為可公開 metadata。

尚未接入 Android Keystore slot adapter、App 持續連線與背景工作、等待超時／取消、舊世代清理、遺失 catalog 的救援、反回放、任意 active write 中斷的 hot journal 自動復原。未知 sidecar 仍停止並保留資料。程序退出不是實際斷電、磁碟滿或 Android OS kill 的證據。

不將這 23 項案例換算成 BACKUP／KEY／Android 完整 gate 通過。裝置測試仍需可用 Android 目標；詳見[開發進度](../../docs/work-progress.md)。
