# 資料庫／金鑰配對切換原型

狀態：Windows host 的限定機制原型；尚非正式儲存、Ledger 還原或 Android 安全能力。

依據：[生命週期契約](../../docs/storage-lifecycle-contract.md)、[驗收案例](../../docs/foundation-acceptance.md)。本項處理新 DB 與新 key 分開保存時，如何在程序中止後決定可用的配對。

## 實際範圍

- 每次安裝建立獨立 UUID v7 世代與 key slot。新 DB 為 SQLCipher 4.19.0 加密的兩表 fixture，保存配對身份與最長 4 KiB 的固定測試文字。
- `catalog.db` 只保存不透明身份、測試內容指紋、前一世代及嘗試狀態。它是**未加密的非秘密控制紀錄原型**，不保存 key 或 fixture 原文；不能直接套用到正式帳務 metadata 的安全需求。
- key 建立與讀回、DB 寫入與重開驗證都在發布前完成。發布時在同一 SQLite transaction 將 attempt 標為 committed 並更新唯一 active 參照；該 COMMIT 是唯一完成點，沒有另刪 journal 才完成的第二套判斷。
- 發布前中止，SQLite 回滾控制參照；啟動核對舊組合後將 pending 改為 aborted，保留未提交 DB 與 slot。發布後中止，啟動核對新組合，不退回舊帳本。
- 同一 operation ID 的已提交重試回傳原 receipt；如果其後已有新世代，不重新啟用舊世代。同 ID 改內容拒絕。這是儲存安裝去重，未取代財務 operation receipt。
- 開檔核對 key、DB 內 generation／slot／operation 身份、內容指紋、schema 及 SQLite／SQLCipher 完整性。錯誤 key、缺失控制紀錄、未知版本或欄位、異常旁檔均停止；不自動重設金鑰或建立空帳本遮蔽已有資料。
- 同程序競爭回傳 busy，合作的不同程序使用 OS 檔案排他鎖依序執行。DB handle 不外流，所有測試世代關閉後才發布。

`FixtureKeySlots` **以明文檔案保存測試 key**，只供暫存目錄與子程序測試。不得在 App 使用、保存真實資料或宣稱其提供 Android Keystore 保護。沒有把它加入 Android 入口。

## 觀察結果

2026-09-27，Dart 3.13.4／sqlite3 3.6.0／SQLCipher 4.19.0 community 的 Windows 環境：格式、靜態分析及 26 項測試通過。

- 不同新舊 key／DB 配對；錯 key 拒絕、原 key／DB 保留、重新啟動核對。
- 舊 operation 重試不重新啟用已退役世代；同 ID 改內容拒絕。
- 七個 checkpoint 直接退出子程序（exit 73）：reserved、keySaved、databaseWriting、staged、validated、publishing、published。另一獨立程序核對舊或新組合，重試後僅一個已提交結果。
- 首次安裝在四個 checkpoint 退出；發布前沒有正式世代，發布後重開正確世代。
- key 寫入前失敗、寫入後回報失敗、未知編碼及遺失：不覆寫原 slot；可恢復時使用新 slot 重試，原失敗材料保留。
- 控制 DB 遺失／版本未知／新增 generated column、DB 身份／內容不符、未知旁檔及刻意混配 key 都拒絕，保留測試材料。
- 同程序兩個 coordinator 的競爭被阻止；兩個子程序同操作同時提交，最後只有一個 committed 世代。

第一次並行測試揭露非阻塞 file lock 讓第二程序直接失敗；改用 blocking exclusive lock 後以上全數通過。錯 key 測試中 SQLCipher 可能印出 HMAC 失敗診斷，這是預期拒絕案例，不含測試金鑰；測試結果以 assertions 為準。

## 執行

```powershell
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib bin test
dart analyze
dart build cli --target bin/generation_worker.dart --output .dart_tool/worker
dart test --reporter expanded
```

先編譯 worker，再執行測試，避免 Windows 原生 DLL 被測試父程序占用時重新覆寫。全部 fixture 在新建暫存目錄內，測試結束清除該目錄。

## 不能支持的結論

後續新增明確的 `CatalogProtection` 模式：控制 DB 使用獨立 key、SQLCipher 與 schema 2，內部 store 身份必須符合 composition 提供的 ID；原 schema 1 明文模式只保留給舊 fixture。18 項新增案例與原有 26 項切換案例通過，初始化中止有一種保留並停止的情境，不能宣稱所有中止自動復原。完整邊界見[控制紀錄加密](../../docs/storage-control-protection.md)。

預設文字 fixture 有自己的 schema 1。後續新增 `GenerationPayload` adapter 與受鎖保護的內部連線 scope，由 [Ledger 整合原型](../ledger_generation/README.md) 接入明確的財務 schema 3／snapshot format 2，未放寬未知欄位檢查。發布前重開後的內容必須與正規化輸入摘要相同；文字 fixture 仍要求內容不可變，Ledger adapter 則允許發布後合法入帳。

尚未實作平台 secure storage adapter、App 活躍連線租約、跨程序等待超時／取消、舊世代清理、catalog 災難恢復或抗整套舊 metadata 回放。原型跨程序鎖會等待持鎖者釋放，不能直接拿來滿足正式超時契約；同程序 busy 保護不代替正式背景工作協調。

不刪除任何舊世代或 slot，尚不支援長期保留政策。若 active key 遺失，這個原型停止操作；正式產品從可攜備份恢復到新安全環境的路徑仍需另行整合。

程序退出不是斷電證據；本項未模擬實際磁碟滿、Android OS kill 或安全儲存故障。未重新驗證 BACKUP-01／02 的乾淨 Android 路徑，亦未將任何 KEY-01～08 整組標為完整通過。舊模式的 SHA-256 去重摘要不可視為可公開 metadata；新模式把摘要與參照納入加密控制 DB，並不提供整套舊資料的防回放保證。
