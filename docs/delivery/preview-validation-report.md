# 試用版驗證與容量

狀態：主要大規模 run 與最後防護修改的滿容量回歸均通過。APK 封裝資訊見[安裝與驗收](installable-preview.md)。

## 驗證方式

`prototypes/expense_preview/tool/large_scale.dart` 使用實際 PreviewEngine、SQLCipher、加密 catalog、獨立測試 vault，以及與實作分開累加的 BigInt 預期餘額。沒有手機、網路服務或使用者資料。

主要 run 共 10 組資料，各 5,000 筆新增交易（含期初），每筆立即以同一 operation 重送一次。第一組全部集中一個帳戶，其餘每組 32 個帳戶，涵蓋現金／銀行、TWD／USD／JPY、正負期初與餘額、2006-01-01～2026-09-27、100 字帳戶名稱。每 1,000 筆核對全部餘額並量測摘要／首頁，最後按獨立排序的 ID 核對所有分頁。

每組匯出後以救援文字解密，核對 events／receipts／audit 數量。以新的 profile、catalog／generation key 還原，密碼與救援各五組；比較完整 snapshot bytes、餘額、還原後的舊 operation 重送與重新開啟。帳戶及交易超限新增須拒絕，滿額後仍可重送既有操作。

本機為 Intel Core i5-1135G7（4 核／8 執行緒）、15.7 GiB RAM、Windows；Dart／OS 完整版本由工具寫入原始紀錄。這是主機正確性與容量驗證，不是 Android 手機效能承諾；同一主機期間也有一般開發作業，時間屬實測觀察而非隔離環境的效能保證。每組還原在同一程序的獨立目錄及 vault；獨立程序故障與還原另由既有回歸測試覆蓋，不混稱實機。

## 容量保護

試用版限定 32 帳戶、5,000 筆事件（包含期初）。匯入再限制一筆事件各一列 leg／receipt／audit、單 workspace、沒有分類／轉帳／額外封存紀錄。

另檢查每列 JSON 的 UTF-8 bytes：帳戶最多 4,096；一般 receipt 最多 1,024，開戶 receipt 最多 4,096；其餘列最多 512。完整財務驗證後，開戶 receipt／opening 均不超過帳戶數。最多 20,064 列，逐列上限合計 13,045,760 bytes；加上固定 manifest、表名與分隔字元仍低於 16 MiB payload 上限。超長來源標記、JSON 空白或歷史輸入不因筆數較少而繞過保護。

目前 UI 產生的固定來源、UUID、日期、Money 與 Account.open 欄位均有界；新的帳務透過相同 session 容量檢查。這是最小試用版界線，M3 單帳本 100k+ 的目標仍保留，不能將跨 10 組資料的總筆數稱為單帳本容量。

## 本輪修正與回歸

首次大量測試的第一組寫到 5,000 筆時，餘額／重送核對通過，但完整備份還原的驗證重複掃描全部事件與明細，因而停止該次診斷 run；它不列入完成的大規模結果。

驗證器改為一次建立 `(workspace, id)` 事件與帳戶索引、依事件整理已排序 legs，並改為分組計數檢查 receipt 基數。保留重複 ID 檢查及原有每項財務 invariant，不新增持久餘額快取、不變更 schema。新增跨 workspace 同 ID 不同幣別、重複／缺少 receipt 的案例。

重新建置獨立程序 worker 後，還原 32、加密 26、Ledger 世代 54 項（共 112）回歸通過；App 16 項 engine／widget 與靜態檢查通過。關閉失敗會向呼叫端傳回並阻止再開啟，不再吞掉關閉錯誤。

## 重現

在 `prototypes/expense_preview` 使用鎖定的 Flutter 3.47.5／Dart 3.13.4：

```powershell
flutter pub get --enforce-lockfile
flutter test --reporter expanded
dart run tool/large_scale.dart
```

原始報告寫入 `.dart_tool/scale-report.json`。成功的合成帳本會在確認測試根目錄後移除；失敗／中斷資料保留於 `.dart_tool/scale-tests` 供診斷。fixture vault 不是正式平台 key storage。

## 啟動與空帳本補強

大規模測試期間另檢查啟動流程：設定保留為 pending，直到空帳本已驗證發布才完成 profile。已完成設定的 App 缺少 catalog 或 active generation 時停止，不把資料遺失當成首次使用。完整 pending 仍可安全接續。另統一還原空帳本時的 workspace fallback，使立即新增與重新啟動後一致。這些設定／空帳本變更另執行新增案例與 5,000 筆容量回歸；不把先前執行中的大規模 run 冒充已包含後續修改。

## 主要 run 結果

[原始 JSON 紀錄](../test-results/2026-09-27/preview-scale-2026-09-27.json)：10 組全部通過，50,000 筆不同交易、50,000 次立即重送、10 次還原後重送，合計 100,010 次財務操作。交易數包含 289 筆期初；不把還原複製資料或查詢算成新增交易。總執行 1,037,289 ms（約 17 分 17 秒）。

每組包含 5,000 筆交易，單帳本完整 payload 為 5,226,575～5,268,615 bytes；權威列 20,002～20,064。備份含雙路解密核對為 6,292～8,098 ms；還原含原帳本安全副本為 8,224～15,762 ms；解鎖重開 2,938～3,295 ms。完整 167 頁／5,000 筆游標遍歷約 2,928～4,334 ms。各 1,000 筆階段的摘要及首頁數據均在原始紀錄中。

第一組集中單帳戶的 5,000 次新增／5,000 次重送共 91,621 ms；其餘 32 帳戶組為 63,152～73,642 ms。這包含分段查詢核對，不是單筆寫入延遲分位數，也不是 100k 筆單帳本驗證。

## 最終容量回歸

[最終程式的單帳本紀錄](../test-results/2026-09-27/preview-capacity-regression-2026-09-27.json)：新增 5,000 筆、重送 5,001 次，完整 bytes、餘額、全部分頁、滿額拒絕與重開通過，耗時 132,832 ms。payload 5,226,548 bytes，加密 envelope 6,969,278 bytes；備份／雙路核對 7,982 ms、還原 8,448 ms、重開 2,929 ms。

兩份已完成紀錄合計 **55,000 筆新增交易、55,011 次重送，共 110,011 次財務操作**。最終 App 的 19 項 engine／widget 案例通過，包含已發布帳本遺失時不建立空資料、完整 pending 初始化接續，以及空帳本還原前後 workspace 一致。新測試中的兩份獨立來源改成依序開啟，避免 Drift 的多實例偵錯提醒；沒有關閉或隱藏該警告設定。

完整 CI 測試清單共 331 項，涵蓋值型別、帳戶／Ledger、資料交易、envelope、還原、加密、世代、Android adapter、試用 UI 及架構邊界。此次受影響的 131 項已在本機通過；遠端整體結果以本分支 PR checks 為準。沒有執行本輪手機／OS 重啟／斷電或新 App 系統檔案選擇器的實機驗證。


## 2026-09-28 備註修訂

[完整主機證據](../test-results/2026-09-28/notes-host-2026-09-28.json)：18 套件、869 獨立案例；[大量資料](../test-results/2026-09-28/notes-scale-2026-09-28.json)包含 5,000 事件＋5,000 備註修訂、9,999 重播、容量拒絕與來源刪除後雙方式乾淨還原；[四處草稿程序退出](../test-results/2026-09-28/notes-process-2026-09-28.json)另列。主機通過不取代雲端／實機 gate。
