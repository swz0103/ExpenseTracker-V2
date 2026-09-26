# Foundation Validation — 地基驗證紀錄

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
