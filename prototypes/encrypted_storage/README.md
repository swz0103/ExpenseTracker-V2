# SQLCipher 加密儲存接入原型

接續 [Ledger 驗證還原](../validated_restore/README.md)，對應[地基計畫](../../docs/implementation-plan.md)中的本機加密與可攜還原風險。這是候選接入路線的 Windows host 實測，尚未決議完整平台 ADR／Architecture Freeze。

## 路線與邊界

2026-09-27 接續：加入[交易分類引用 schema 5 的加密暫存還原](../../docs/ledger-category-references.md)，密碼／救援分別在無來源 DB 的獨立程序驗證；同一帳本 5,000 事件及 7,498 分攤的完整還原通過。正式 schema 5 世代發布、session 容量及 App 入口仍待後續，原有預設加密入口不自動升級。

沿用已鎖定的 sqlite3 3.6.0，於本原型根目錄選擇 `hooks.user_defines.sqlite3.source: sqlcipher`。沒有另外安裝舊版 Flutter libs，也沒有商業授權碼或付費服務。套件的 hook 文件與原始碼提供此來源，下載成品會對照套件內的 SHA-256。

本機實際輸出：SQLCipher `4.19.0 community`，provider `openssl`，SQLite `3.53.4`。Windows x64 成品在 sqlite3 3.6.0 的預期 SHA-256 為 `4da12fe34e8b6f3efeff9131d60ee28fb30091c481a7565d4bdf756870935283`。平台成品不同，不能拿此 hash 驗證 Android。

連線建立時檢查 cipher_version，缺少加密引擎即停止，release 也執行。使用獨立隨機 32 bytes 資料金鑰與嚴格 hex literal；金鑰不進入命令列、文件或例外訊息。明確指定 SQLCipher 4 相容設定、4096-byte page、page HMAC、零明文 header，暫存查詢資料使用記憶體；再讀取 schema 驗證金鑰，而不以設定 key 成功代替真正解密成功。

`StorageKey` 只提供記憶體值及隨機產生，沒有假裝完成 Android Keystore、PIN／biometrics、金鑰封裝、輪替或安全抹除。密碼是備份 envelope 的解鎖憑證，不直接當成本機 DB raw key。

在既有 ProbeDatabase 加入 executor 注入入口，SnapshotCodec／RestoreStore 加入資料庫建立函式。原本明文 fixture 的預設行為保留；此加密入口則把相同的財務流程、備份快照、暫存驗證與切換接上加密 executor。這些仍是 prototype 內部接口，正式 Data packages 尚未交付。

## 實測

```sh
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib bin test
dart analyze
dart build cli --target bin/restore_worker.dart --output .dart_tool/worker
dart test --reporter expanded
```

原有 12 項測試涵蓋：

- 確認實際加密引擎／provider；關閉重開後核對帳務與餘額。
- 無金鑰、錯誤金鑰、明文檔與單一首頁位元損壞被拒絕；原檔 bytes 保留。
- 實際交易失敗回滾與 operation replay，避免重複入帳。
- 密碼／救援各自解鎖備份，來源 handle 關閉後，以獨立新金鑰建立加密 stage，核對全部快照列與餘額；舊 DB 金鑰無法開啟新 DB。
- 固定 v1 fixture 在加密 DB 中升級到 v2，保留餘額 115 與引用。
- 切換失敗恢復舊資料；留下的未提交 stage 也保持加密。
- DB／stage 檔無明文 SQLite header 或測試商家字串；實際非空 WAL 無該字串。金鑰長度／byte 範圍與字串遮蔽檢查。

字串掃描只證明測試標記沒有以明文出現在那些檔案，不能代替完整資料外洩稽核。錯誤金鑰／竄改案例會產生 SQLCipher 預期的 HMAC error 診斷，不代表測試失敗。初次接入曾因 pragma 返回字串而錯判設定；目前明確正規化後核對數值，未移除檢查。

### 獨立程序組合測試

另加 10 項程序測試：密碼／救援各自啟動編譯後的 worker 還原，再啟動另一個 worker 核對完整 snapshot、cipher integrity 與舊 operation replay；三個切換邊界 exit 73 後，由新程序執行兩次 recover，再以原目標金鑰核對舊檔 bytes 與餘額 122；首次還原中止回到無正式 DB；錯誤密碼、錯誤救援码、已重新加密的未知 schema 與截斷封裝均不修改原目標檔。

來源 DB 在任何還原子程序啟動前已刪除，來源 key 從未持久化或傳給子程序。子程序只接收備份、一種解鎖憑證及新目標 key 的 fixture 檔案路徑，驗證不依賴來源裝置金鑰。目標 key／credential 的明文 fixture 僅存在被忽略且測後清除的目錄，這不是正式金鑰保存方式。檔案恢復本身不需要 key，也不代表已完成 key metadata 的原子切換；測試保留正確舊 key 以驗證回復後檔案。

CLI 是測試入口，不是使用者功能。先編譯 worker 再跑測試，避免 Windows 父程序載入 DLL 後重打包該檔。程序退出僅驗證指定 checkpoint，不代表任意斷電。

### 加密 migration 故障

再新增 4 項測試，目前本套件共 26 項本機測試通過：

- 在 v1 → v2 新增欄位後與新增索引後，以子程序 exit 73 中止。確認遺留非空 rollback journal，重新用正確 key 開檔後，由 SQLite 恢復至 v1，全部七表內容不變；再試可升級到 v2。
- 把 `max_page_count` 設為 fixture 目前頁數，確認實際引擎回報 `SQLITE_FULL`（13），且在 column checkpoint 之後、index checkpoint 之前失敗。schema 仍 v1、沒有新增欄位／索引、全部權威列未改；換成未受限連線後可再試。
- 加密 DB 的未知 schema 99 不被降版；原始 bytes、資料列與版本均保留。

這些測試使用固定 fixture 與真實 SQLCipher。頁數上限只是可重現的引擎寫入容量錯誤，沒有填滿使用者磁碟；沒有驗證 OS 的 ENOSPC、各種中斷時機或真實斷電。SQLite 自行恢復其 hot journal，與還原切換器遇到未知 sidecar 時停止保留的責任不同。

參考：[SQLite max_page_count](https://www.sqlite.org/pragma.html#pragma_max_page_count)、[SQLITE_FULL](https://www.sqlite.org/rescode.html#full)。

## 未通過的 gate

沒有 Android 裝置測試、secure storage、App 鎖定、平台備份排除／隱私畫面、效能與耗電量測、實際磁碟滿／斷電或安全審查。已加入跨程序加密還原與指定切換中斷的組合驗證，但這仍是 host fixture，不能取代 Android 新安裝／新裝置 gate。

原型產生檔只在忽略的測試目錄。正式打包前仍需整理 SQLCipher／OpenSSL 與其他依賴的 notices；參考 [SQLCipher 4.19.0 授權原文](https://github.com/sqlcipher/sqlcipher/blob/v4.19.0/LICENSE.md)。目前沒有正式發布或宣稱本原型可保存日常資料。

技術來源：[sqlite3 3.6.0 hooks](https://pub.dev/documentation/sqlite3/3.6.0/topics/hook-topic.html)、[SQLCipher API](https://www.zetetic.net/sqlcipher/sqlcipher-api/)、[Drift 加密接入](https://drift.simonbinder.eu/platforms/encryption/)。Drift 文件主要示範 sqlite3mc；本次 SQLCipher source 依據鎖定版本的套件原始碼及實測，不將舊版接入限制直接套用到新版。
