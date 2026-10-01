# 控制紀錄加密邊界

狀態：階段 1 限定原型；Windows host 有驗證證據，Android 待裝置測試。補充[資料庫與金鑰生命週期契約](storage-lifecycle-contract.md)、[RC-14](../architecture/architecture-baseline-v1.0-rc1.md#rc-14) 與 [Full Vision Q118](../architecture/full-vision-baseline.md#q118)，不變更已選定的產品範圍。

## 為何需要此項

PR #15～17 的世代控制紀錄保存目前 DB／key slot 參照、切換操作與輸入摘要。金鑰和帳務列不直接放在其中，但財務 snapshot 的 SHA-256 仍可能被比對，不應把它當作可公開的非敏感資訊。這一項把控制 DB 本身納入 SQLCipher 保護，沿用已驗證引擎，沒有另建自製加密格式。

## 實作邊界

- `CatalogProtection` 由 App composition 提供穩定的本機 store ID 與獨立控制金鑰 loader。store ID 不是備份中的帳務 workspace，也不得從匯入資料指定。
- loader 在既有生命週期排他鎖內執行。控制檔已存在而 key 遺失時拒絕；控制檔未建立但已有保存成功的 key 時重用。不能覆寫或以新 key 試開舊檔。
- 舊控制 schema 1 仍僅供明文固定 fixture 回歸。明確選用 protection 才使用加密控制 schema 2；新增內部 `catalog_identity` 與外部 store ID 核對。明文與加密模式不互相自動降級或升級。
- 原 attempts、active 與唯一發布 transaction 維持原語意。安裝去重摘要與 operation 參照現在位於加密控制 DB 及其加密 journal 內；不改可攜帳務 format 2 或財務 schema 3。
- 控制 key 與每個世代的 DB key 分開保存；snapshot 不包含控制 key、store ID 或世代 slot。密碼／救援憑證還原可在新目標建立自己的控制 key。
- Android 使用 `expense_v2_control_probe_v1` namespace 與逐 store 欄位；讀寫沿用已測的 `KeyAccess` 規則，`resetOnError` 與自動演算法 migration 均關閉。目標世代 key 保持另一套獨立 slot。

Android 的固定 fixture 改用 `generation_v2_password`／`generation_v2_recovery`，保留先前 v1 目錄與 key，不就地轉換或清除。這是新測試路徑，**不是**真實舊帳本升級方案。正式多 store 身份發現、舊控制資料轉換及 key 輪替仍需另外驗證。

## 中止與拒絕規則

控制 key 保存後、控制檔建立前中止：下次在確認目錄沒有需保護的既有檔案後重用 key。控制 schema 已提交但尚未發布帳本時中止：下次識別完整空 catalog，繼續原安裝。已存在資料或世代卻遺失控制檔時，不建立空 catalog 掩蓋資料。

PR #18 的首次控制 schema transaction 尚未提交時中止，會保留檔案與 key 並拒絕不完整 schema。後續改為[暫存初始化與發布](storage-catalog-initialization.md)：新的首次建立可接續尚未發布的 stage，既有不完整 `catalog.db` 仍保留並停止。尚未提供損壞正式 catalog 的使用者復原 UI，也未宣稱裝置可用性 gate 通過。

對正常世代切換，沿用提交前維持舊配對、提交後維持新配對的規則。錯誤 key、內外 store ID 不符、未知版本／欄位及驗證失敗會停止；保留檔案與 slot，不回報零餘額或成功還原。

## 驗證與限制

新增 18 項控制紀錄案例：加密與獨立 key、原始控制／journal 不含操作與摘要明文、五處世代程序中止、三處首次控制初始化中止、key／控制檔遺失、store 身份不符、明文與加密模式互拒、未知版本／generated 欄位與密文破壞拒絕。

另新增 2 項 Ledger 整合案例：密碼與救援金鑰各自以新程序還原，完整權威列核對，新增交易後再次備份／還原與 replay。原有切換、帳務與 Android host 測試保留。具體結果、分支與 CI 見[工作進度](../work-progress.md)。

host 的 `fixtureCatalogProtection` 仍把 key 放在明文測試檔，且位於控制目錄之外；不得接到真實 App。Android 已接平台 loader，但本機尚無可用 Android 裝置。APK 建置和 host 記憶體 vault 測試不證明 Keystore／重啟行為。

SQLCipher 保護檔案內容，不代表能抵抗整套有效舊 DB／catalog／key 的回放；本機身份也不是外部可信計數器。後續已補 host 初始建表中止復原與[等待期限／取消](storage-lock-wait.md)；實體斷電、磁碟滿、正式活躍連線租約、清理及完整 Android gate 仍待完成。
