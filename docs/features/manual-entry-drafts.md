# 手動收支草稿與恢復

> 這是舊版 App（`prototypes/`，已於 2026-10-03 移除）時期的規格，留作行為對照。新架構以 [ADR-0001](../adr/0001-target-architecture.md) 與 [STATUS.md](../STATUS.md) 為準。

2026-09-28 更新：下列保留原始單筆收支草稿批次紀錄。後續在同一加密 slot 接入[同幣轉帳](same-currency-transfers.md)、[跨幣轉帳](cross-currency-transfers.md)及[多分類拆分](split-entry-drafts.md)的獨立版本格式；目前正式帳本為 schema 9／snapshot 8。加密、凍結命令與備份 gate 原則繼續適用，具體證據依各批次區分。

來源：M1-02、[RC-02](../architecture/architecture-baseline-v1.0-rc1.md#rc-02)、[Q072](../architecture/full-vision-baseline.md#q072)、[Q155](../architecture/full-vision-baseline.md#q155)。依賴 [安全複製收支](safe-posting-copy.md)／PR #48。

## 當期使用流程

同一個本機帳本維持一份收入／支出草稿。金額、日期保留未完成文字；帳戶、分類、商家與最多 16 個 Tag 保存公開 ID。輸入後依序加密保存，畫面分辨保存中、已保存與失敗；返回帳本前等待保存。鎖定立即清除畫面與控制器，已排入保存的欄位處理完畢後釋放帳本。未開始輸入的乾淨表單不建立空草稿。

重開並解鎖後提供「繼續草稿」與須確認的「捨棄草稿」。有未處理草稿時不另開新表單或覆蓋成交易副本。恢復時已停用／合併的欄位須重新選擇，不能默默導向替代 ID。捨棄草稿不刪除已入帳交易。

正式儲存仍經 Money、日期、Account／Category／Tag／Merchant 與 Ledger 的完整驗證。資料不合法時保留原始輸入，草稿不影響事件列、餘額或正式報表。送出成功後消耗草稿，下一筆保持乾淨。

## 所有權與一致性

- packages/entry_drafts 擁有有界的文字欄位、草稿版本、穩定事件／操作 ID 及不可變送出提案。只依賴公開 Foundation／Ledger 契約。
- App 的 LocalDraftStore 擁有本機加密檔及平台 vault 接口；不用正式 Ledger 列冒充草稿。
- PreviewDrafts 協調驗證、保存、入帳與恢復，不自行計算正式餘額。
- Tag 排序與最多 16 個互異 ID 的規則移到 Ledger 公開契約，既有 persistence 重新匯出同一函式；沒有另寫一套會漂移的排序。
- 單一 App 引擎排他操作、既有跨程序帳本租用及草稿寫入佇列共同維持順序。鎖定會使呼叫者失效，但等待已接受的草稿工作完成後才釋放租用。

真正入帳前，先持久保存完整不可變命令，包括事件／操作 ID、精確 minor units、日期、帳戶幣別與版本，以及分類／Tag／商家版本。之後才使用原有 ACID／receipt 路徑入帳。收到成功結果才保存空完成標記。

若在入帳前中止，重開不自動新增交易，使用者確認後重送同一命令。若入帳後、清除草稿前中止，恢復先查到同一事件，再以原命令核對 receipt，才清除草稿。分類或商家後來改名也不能把重試變成新交易。待確認命令暫停欄位編輯；明確返回編輯前必須證明該事件尚未入帳。

## 加密與本機資料邊界

草稿格式 manual-entry-v1，外層 local-draft-aes256gcm-v1，使用既有鎖定版本的 cryptography AES-256-GCM 與新 nonce；32-byte 隨機金鑰保存在 V2 vault 的獨立 manual_draft_key_PROFILE_ID 命名空間，不進檔案、備份或紀錄。AAD 綁定 V2 profile、帳本 generation、workspace。

manual-draft.pending 只寫密文並 flush、讀回核對，再以同目錄 rename 發布 manual-draft.enc。有既有有效檔時，發布前失敗保留上次確認版本；第一次發布中斷而只剩 pending 時保留並阻擋覆寫，須使用者明確捨棄。版本、形狀、ID、nonce／tag、MAC、文字／檔案上限與 workspace 都驗證；遺失／錯誤金鑰不自動建立新鍵來覆蓋保留資料。

金額最多 128、日期最多 32 個 Dart 字元單位；解密 payload 上限 16 KiB、檔案上限 64 KiB。只有一個有界 slot，不累積鍵擊歷史。明確捨棄同時處理密文、pending 與新金鑰確認。程序強制終止以最後完成發布的版本為準；主機測試不等於 Android 斷電與平台 Keystore 驗收。

## 備份、還原與升級 gate

正式帳本仍為 schema 7／snapshot 6。此批不修改既有攜帶式備份格式，也不宣稱未完成草稿已包含在正式帳務備份內。

**匯出目前帳本或還原前，必須先完成或明確捨棄本機草稿**；不可略過草稿而提示完整備份成功。無法驗證的草稿同樣阻擋，原檔保留。還原後使用新的 generation／workspace 綁定；舊草稿不能誤送到還原後帳本。匯出歷史安全備份仍表示該歷史版本的內容。

升級 gate 也檢查來源版本的草稿；未處理時保持來源帳本，不開始格式切換。來源版本解決草稿後才升級；空完成標記在切換前移除。現有沒有草稿的舊版資料直接沿用原有升級恢復路徑；不先開啟尚待恢復發布狀態的來源 session。回歸已揭露並修正此處與 schema 3 publishing 中斷接續的相容性問題。未來如要把未完成草稿納入跨裝置備份，須另定版本化 bundle 與原子恢復契約，不能偷塞進現有 envelope。

## 驗證與尚未完成範圍

本批共 162 項相關案例與 4 次真實程序退出驗證通過。本機證據記錄於 本批驗證清單，包括純模型、加密與失敗、引擎／升級、窄畫面操作，以及四個真正子程序退出位置。既有備份／還原與鎖定流程必須全 App 回歸。

本批只完成既定手動收入／支出草稿流程。完整 Financial Inbox、OCR／匯入 staging、通用表單狀態框架、多草稿、草稿跨裝置攜帶仍未宣稱完成；M1-02 其餘隱私／無障礙與 M1／M2／M3 後續 CORE 依實作計畫續行。Actions 與實機 gate 分開記錄，不合併 main。


程序退出驗證先建立獨立 CLI bundle，再執行其中程式；避免 Windows 上巢狀 dart run 嘗試替換父程序正在使用的 SQLCipher DLL：

    dart build cli --target tool/draft_crash.dart --output .dart_tool/draft-worker
    .dart_tool/draft-worker/bundle/bin/draft_crash.exe

以上在 prototypes/expense_preview 執行，只建立合成帳本與測試金鑰於忽略的 .dart_tool 目錄，清理先核對路徑邊界；不使用真實帳本、不操作裝置。
