# Foundation Validation — 地基驗證紀錄

**最新實機補充（2026-09-27）**：已在 Samsung SM-A5660／Android 16 通過指定加密／平台 slot、雙路乾淨 App 還原、各自新程序重開與四項平台故障子集，見[實機驗證紀錄](android-device-validation.md)。下方「尚無裝置」保留各原型當時的歷程，不能作為目前狀態；整體安全／升級 gate 仍未完成。

日期：2026-09-26  
狀態：多項 host 機制原型通過；整體架構、安全與 Android gate 尚未通過。最新逐項狀態見[開發進度](work-progress.md)。

依據：[工程契約](foundation-contracts.md)、[驗收案例](foundation-acceptance.md)、[階段 1 計畫](implementation-plan.md)。本文件與測試一起提交，確切修訂以包含本文件的 Git commit 與 CI run 的 head SHA 為準；不引用先前純文件 commit 冒充此次測試版本。

## 執行環境

Windows 本機，Flutter 3.47.5／Dart 3.13.4，`sqlite3` 3.6.0，`test` 1.32.0；完整相依固定於 [pubspec.lock](../prototypes/transaction_boundary/pubspec.lock)。SQLite 使用套件提供的真實原生檔案資料庫，未採用 mock。所有資料均為固定測試值。

## 已觀察結果

本節至原始「下一步」保留第一個 transaction-boundary 原型的範圍；後續項目另列於文末，避免把不同原型的能力混為一體。

在[原型目錄](../prototypes/transaction_boundary/README.md)完成依賴解析、格式化、`dart analyze` 與 `dart test --reporter expanded`。靜態分析無問題，11 項測試全部通過：

- 在 business、第一個 leg、第二個 leg、receipt 四個寫入點注入例外，三張表全部回滾。
- 關閉／重開後，同 operation ID 與相同輸入回傳已保存結果，只有一組 legs。
- 同 ID 改金額拒絕；相同金額的新 ID 可獨立成功。
- 不同 workspace 可使用相同 operation ID，不混用 receipt。
- 無效金額不產生財務資料。
- 子程序在第一個 leg 後以 exit code 73 直接退出，重開資料庫後沒有半筆紀錄。
- 子程序在 commit 後直接退出，結果仍保存；重試回傳 replay，沒有新增第二筆。
- 兩個子程序同時啟動並提交相同操作，只有一個新結果，另一個取得 replay。

各結果另核對資料列數、legs 合計、SQLite foreign key 與 integrity check。兩程序測試驗證同時發起時的結果，不宣稱每次排程都恰好在相同 SQLite 指令上競爭。

Windows 上子程序先以 `dart build cli` 建置，再啟動父測試；避免執行途中重新打包、覆寫父程序已載入的 DLL。這是測試啟動方式，不是產品架構決策。CI 使用同一組步驟，狀態以 PR 的實際 run 為準。

## 可以支持的結論

對應 TX-01／02／03／06 的部分機制：一條 SQLite transaction 可以共同保存固定業務列、兩個 legs 與 operation receipt；提交前失敗回滾，提交後可用持久身份去重。直接程序退出只模擬程序中止，不等同裝置斷電、磁碟故障或 OS kill 的全部情境。

## 不涵蓋的範圍與下一步

本原型不是正式 Ledger，沒有真實 Account、完整 Money／FX、Audit、Drift、跨 Dart 業務套件 adapters、schema migration、資料加密或備份。workspace 測試只驗證 operation identity 範圍，不能替代 VAL-06 的跨帳本關聯驗證。

下一步依序補足正式值型別與資料模型的案例、實際模組共用 transaction adapter，以及 Android 加密／備份還原／migration 原型。TX-04／05、全部完整 LED／EXT／DATA／BACKUP 案例仍待實作；不得把此次 11 項通過轉換成完整驗收清單通過。Architecture Baseline 維持 rc1。

## 後續原型證據

值型別、帳戶、基本 Ledger、共用 Drift transaction、固定舊版 migration 及雙解鎖 envelope 已分項測試，範圍與 SHA 見[開發進度](work-progress.md)。

[Ledger 驗證還原](../prototypes/validated_restore/README.md)將固定 schema 2 的七張權威表接入 envelope；28 項 host 測試驗證新程序的兩條還原路徑、原資料保留、防重複提交、內容與版本拒絕、切換 checkpoint 例外／程序中止以及下次啟動復原。SQLite 本機檔案仍是明文測試資料。未處理的 hot journal 會停止並保留，不能宣稱所有任意中斷已自動復原；實際磁碟滿、斷電、Android 加密與完整新裝置 gate 仍未通過。

[加密儲存接入](../prototypes/encrypted_storage/README.md)另以 SQLCipher 4.19.0 community 的 Windows 成品，完成 12 項加密檔／暫存／還原／交易／WAL／migration 測試。已接上同一財務與 restore 流程，但獨立程序加密中斷恢復、Android 與 secure storage 尚待驗證。這是候選 executor 的證據，不等於整個安全架構完成。

後續新增 10 項獨立程序加密還原測試，涵蓋來源 DB 刪除且不提供來源 key 的密碼／救援路徑、第二個程序核對完整 snapshot／replay／cipher integrity、三個切換 checkpoint 中止恢復、首次還原中止與四種無效備份拒絕。原目標 DB 回復後仍需呼叫者保有正確原 key；正式 key metadata 生命週期、Android 與 secure storage 仍未驗證。

再補 4 項加密 migration 故障測試：v1 → v2 兩處程序退出後的 SQLite journal recovery、頁數上限觸發真實 SQLITE_FULL 13 後的 schema／資料回滾與再試、未知版本拒絕。另新增 generated column 拒絕備份案例，修正 table_info 漏列欄位的問題。結果只涵蓋指定故障點與容量限制，不代表已驗證實際 OS 磁碟滿或斷電。

## Android 接入進度（2026-09-27）

[Android 地基入口](../prototypes/android_foundation/README.md)已接入固定帳務、secure storage adapter 及加密／還原原型。靜態分析與 6 項記憶體 vault 的 host 測試通過，尚未證明平台 Keystore 正常。

debug APK 首次建置缺少 JNI 相依所需的 SDK Platform `android-35`，補齊後另發現 CMake 3.22.1 缺漏；兩者補齊後 ARM64 debug APK 已成功建置。封裝內有 libsqlcipher.so，最終 manifest 的 debug／SDK／備份排除設定已核對，產物 hash 見原型 README。

尚無可用 Android 測試目標，裝置 integration test 未執行；host CI 以 PR checks 為準。裝置、乾淨環境還原及正式 key metadata gate 均保留未完成，不能從建置通過推論執行成功。

## DB／key 配對切換（2026-09-27）

[世代切換原型](../prototypes/storage_generation/README.md)以獨立加密 fixture 與非秘密 SQLite 控制紀錄，驗證單一提交發布 generation／key slot 配對；26 項 Windows host 測試及靜態分析通過。涵蓋七處子程序中止、四種首次安裝中止、錯 key／身份／內容與未知 schema 拒絕、原組合保留及跨程序同操作去重。

第一輪曾發現 file lock 競爭導致第二程序立即失敗，修正等待策略後全數通過。key 檔案僅為不安全的測試 adapter，未接入 Android；schema 1 fixture 也未替換既有財務 schema 2。正式連線租約、超時、清理、平台安全儲存、財務整合與裝置 gate 仍未完成。

## Ledger 與世代整合（2026-09-27）

[Ledger 整合原型](../prototypes/ledger_generation/README.md)以獨立版本接入：本機財務 schema 3 加入已綁定的身份表，format 2 portable snapshot 保留全部七張帳務權威表，在目標重建身份而不攜帶來源 slot。舊 format 1 仍可匯入，新版由舊 codec 拒絕。

23 項 Windows host 案例驗證新舊備份的密碼／救援金鑰獨立程序還原、完整資料與 receipt、還原後新增入帳再備份、七處程序中止、加密身份 migration 回滾與未知版本拒絕。受影響的既有 98 項測試亦已通過；遠端以 PR checks 為準。控制紀錄摘要與 fixture key 尚非正式安全儲存，所有 Android／完整 BACKUP／KEY gate 繼續維持未完成。

後續 Android 入口改接平台逐 slot adapter 與持久目標世代，加入完整 snapshot／配對／財務 replay 核對。11 項新增 slot 行為測試與原 6 項 host 測試通過；新 ARM64 debug APK 已建置並核對 SQLCipher、SDK、禁止系統備份及 debug 設定。這些是 host／封裝證據，實際平台讀寫和重啟仍未執行。尚無可用 Android 裝置，KEY-07 的乾淨平台還原仍未通過。

## 加密控制紀錄（2026-09-27）

[控制紀錄保護](storage-control-protection.md)新增 SQLCipher catalog schema 2，使用與各世代不同的 key，保護原本會以明文保存的 snapshot 去重摘要與參照。18 項控制案例與 2 項 Ledger 新程序雙路還原案例通過；既有世代 26 項、Ledger 23 項及 Android host 17 項也通過，受影響套件合計 86 項。新 APK 建置及封裝檢查通過，遠端結果以 PR checks 為準。

未知格式、key 遺失、store 身份不符、密文破壞與跨模式誤開均拒絕。初次建表 transaction 中止仍停止並保留，不回報可用空帳本。此項不提供整套舊 catalog／DB／key 的防回放能力，也沒有替代 Android 裝置與實際儲存故障 gate。
