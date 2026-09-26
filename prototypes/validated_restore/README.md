# Ledger 驗證還原原型

依據[實作計畫階段 1](../../docs/implementation-plan.md)、[BACKUP／DATA 驗收案例](../../docs/foundation-acceptance.md)與 [2A 決策](../../docs/full-vision-baseline.md#decision-product-delivery)。此項接續 [Envelope 原型](../backup_envelope/README.md)，只使用測試資料；本機 SQLite 尚未加密，不能存放日常財務資料。

## 備份與驗證

在同一 Drift read transaction 讀取 accounts、events、legs、openings、allocations、receipts、audit，保存 schema 2 與各模組版本。整數以十進位字串保存，避免 JSON 數值精度損失。遇到未識別的資料表、欄位、模組版本或過量內容即拒絕，不默默省略。上限為 16 MiB／50,000 列，是原型邊界，未測大資料集效能。

解鎖後，先在全新 stage.db 用綁定參數與單一交易匯入，再核對外鍵、SQLite 完整性、帳戶還原、期初日期與引用、幣別、餘額溢位、各種入帳／轉帳／費用符號、報表數字、receipt 與 audit 關聯及 receipt 入帳內容。所有驗證完成並關閉 handle 後才切換。現階段無 Categories adapter，因此不接受非空 allocations；不能把保留欄位當成已支援分類還原。

manifest 只承諾目前原型七張表，不是未來所有業務的正式格式。新模組必須擴充清單、驗證器與對應 round-trip 測試。備份不攜帶 SQL 指令，不執行來源 schema。

## 切換與恢復

僅適用程式獨占的測試資料夾；呼叫前必須停止寫入並關閉全部資料庫 handle。檔案鎖防止配合此協定的程序同時切換，不能取代正式 App 的資料生命週期管理。

1. 完成 stage 驗證。
2. 寫入並 flush journal，記錄是否存在舊資料。
3. current.db 移至 previous.db，stage.db 移至 current.db。
4. 刪除 journal 作為提交點；保留 previous.db，不自動刪除財務版本。

journal 尚在即視為未提交。下次啟動 recover 先保留未提交檔案，再恢復舊資料；第一次還原則回到「尚無正式資料」。恢復可重複執行。遺留暫存／舊檔以 UUID 改名保留，不覆寫既有目的檔。損壞 journal、意外路徑型別、WAL／SHM／hot journal 會停止並保留檔案；目前不自動處理匯入途中留下的 SQLite hot journal。

本原型沒有目錄 fsync／裝置斷電驗證，也没有實際填滿磁碟測試。checkpoint 的 I/O 例外及子程序 exit 73 只代表那些切換邊界，不能推論任意 OS kill、磁碟故障、斷電皆已通過。保留檔案的空間管理與正式加密暫存策略仍待實作。

## 執行與結果

```sh
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib bin test
dart analyze
dart build cli --target bin/restore_worker.dart --output .dart_tool/worker
dart test --reporter expanded
```

先建置子程序，避免 Windows 的 SQLite DLL 已載入後被再次打包覆寫。測試 fixture 來自固定 v1 SQL，先由既有 migration 升級，再備份與還原。

28 項測試涵蓋：密碼／救援金鑰各自在新程序還原全部權威列，餘額 115 與 operation replay 不重複入帳；成功替換保留舊檔；錯誤密碼、截斷、十種已通過加密驗證但內容無效的快照拒絕；四處例外回滾；三處程序中止後復原及再次還原；首次還原中止；損壞 journal、hot stage sidecar、跨程序鎖，以及未知持久結構拒絕。保護舊資料的案例逐 bytes 比對原檔。

本機靜態分析與測試已通過；遠端狀態以此分支 PR 的 CI 為準。此結果只完成 host 原型的一部分 BACKUP／DATA 證據，Android 裝置、本機加密、完整 migration、正式備份格式與安全審查 gate 仍未通過。

參考：[Dart rename 行為](https://api.dart.dev/dart-io/File/rename.html)、[檔案鎖語意](https://api.dart.dev/dart-io/RandomAccessFile/lock.html)、[Drift transaction](https://drift.simonbinder.eu/dart_api/transactions/)。
