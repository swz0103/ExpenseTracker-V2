# 跨幣轉帳、實際本金與可追溯換算

2026-09-28；依賴 [PR #54](https://github.com/swz0103/ExpenseTracker-V2/pull/54) 的[同幣轉帳](same-currency-transfers.md)。對應 [M1-03](implementation-plan.md)、[RC-03 Ledger](architecture-baseline-v1.0-rc1.md#rc-03)、[RC-04 Money／FX](architecture-baseline-v1.0-rc1.md#rc-04) 與 [Full Vision](full-vision-baseline.md)；完整核心範圍仍以 Baseline 為準。

## 使用流程與財務規則

新版「轉帳」入口可選不同幣別帳戶。先填轉出本金，再填目的幣別的實際轉入本金；手續費仍以轉出幣別另列。同幣帳戶不增加第二個金額欄，必須本金相等。來源與目的必須不同、同工作區且可入帳，日期不得早於任一帳戶起始日。

例如轉出 20.00 TWD、收到 95 JPY、費用 1.25 TWD：來源扣 21.25 TWD，目的增加 95 JPY；費用支出 1.25 TWD，本金不列收入或消費。兩幣數字不加總。日圓只接受整數，任何手動金額超過幣別精度直接拒絕；計算器依既有明確套用規則工作。兩邊本金都必須正數，費用可為零；本金加費用、兩帳戶最終餘額都須符合 Money 範圍。

`ActualConversion` 保存 `actual-principals-v1` 依據，以及由兩邊本金產生的精確 `FxRate` 分子／分母（主幣單位比例，納入各幣 scale）。上述比例為 19/4 JPY per TWD。費用不參與比例；不經 double、不將循環小數先取位、不以行情重新覆寫成交金額，也不冒充外部 quote、觀測日或供應商。UI 列出原幣本金、來源費用與總扣款，並明示換算依據；金額與朗讀標籤共用隱私遮罩。

目前支援「兩邊實際本金已知」的手動流程。第三幣費用、從外部匯率自動預填、匯率差異歸因、基準幣報表與即時／歷史供應商接入仍待後續；已有 FxObservation 值型別不代表供應商已接通。本流程不自動取得網路行情。

## 同一交易保存與重試

Ledger 沿用來源／目的 principal legs 和可選來源 fee leg。新增 `event_fx` 擁有每筆跨幣事件唯一的換算 context；事件、legs、context、receipt、audit 與兩邊餘額驗證使用同一 ACID 交易。任一步失敗全部回滾；來源或目的幣別、版本、日期、金額或容量不符不能只入帳其中一邊。

新 receipt 使用 `fx-posting-v1` 包裝既有 posting 與精確 context，兩邊實際金額都參與操作身分。相同 ID／相同命令重送回原結果，任何金額不同則衝突。舊同幣與一般收支 receipt 保持原格式，可在升級後重送。

列表單一查詢取得目的本金的實際金額／currency／scale；不拿來源本金當目的金額。App 也略過轉帳不適用的分類／Tag／Merchant 讀取，每筆減少三次查詢。回查同幣 snapshot 驗證也補上「本金加費用」範圍檢查，使還原與新寫入接受同一金額界線。

## 草稿與背景鎖定

`manual-fx-transfer-v1` 保存兩邊原始文字、來源費用、帳戶與日期；`manual-entry-v1`、`manual-transfer-v1` 不改。未完成算式仍可加密保存，但不能入帳。送出前先保存兩帳戶版本、兩金額與同一 operation／event 的凍結命令；重開後查 receipt 或重送，仍只有一次財務效果。

切換帳戶會清除轉入金額，要求重新確認目的幣別；一般重開／鎖定恢復則保留原字串。背景鎖定與 dispose 清除新金額 controller，既有浮層和舊 session 回呼防護繼續生效。未解決的舊草稿仍先在來源版本處理，再進行升級。

## 升級與還原

實體 schema 9／portable snapshot 8，manifest 新增 `ledger_fx_transfers: 1`。低版本 reader 拒讀；只支援既有版本的檔案不假裝已包含 FX context。schema 8 → 9 使用 `ledger-8-to-9-v1`：驗證來源身分、產生且讀回密碼與救援雙憑證安全備份、建立新 generation、完整驗證後原子發布，來源 DB／key 保留。較舊 V2 按既有路線逐段升級。

Snapshot 驗證兩邊 leg 的帳戶幣別、實際本金正負與金額、來源費用、精確換算 context 及 receipt；缺少、孤立或竄改的關係不能發布。目標還原不依賴原裝置 key。這是 V2 內部格式演進，不讀取或匯入舊 App `com.wzet.app`。

容量仍為暫定 32 帳戶／5,000 事件，新增表與 receipt 也計入 row／byte 上限；全體 50,000 rows／16 MiB 上限保留，不宣稱已完成 M3 最終容量。

## 驗證結果與未完成 gate

[完整主機證據](test-results/cross-currency-transfers-host-2026-09-28.json)：18 套件／754 個獨立案例全數通過，新增 31 項，包含 11 處 schema 8 → 9 真正程序退出。全量後只有列表讀取優化，相關 10 個 UI 案例與分析通過，重跑不累計；266 檔指紋分別保留完整回歸與最終版本。初期靜態分析的括號規則提示已修正，最終分析通過；本批執行的測試無失敗。

[大量資料](test-results/cross-currency-transfers-scale-2026-09-28.json)：5,000 事件含 4,997 雙向跨幣轉帳、4,998 次重送，33,745 rows／10,932,466 bytes。獨立預期餘額為 TWD 2,165,705 最小單位、JPY 2,144,604 最小單位；來源費用分別 TWD 2,498、JPY 4,996 最小單位，沒有跨幣裸加。第 5,001 筆新事件拒絕且 snapshot 不變。原 DB／key 刪除後，密碼與救援分別在乾淨 profile 還原、重開、核對全部 snapshot 與每路 5,000 筆完整分頁。全流程主機耗時 341465 ms，含寫入／重送／備份／刪除／雙路還原，不當成實機延遲或 M3 100k+ 能力。

另有 [4 處草稿真正程序退出](test-results/cross-currency-transfers-process-2026-09-28.json)通過；變更兩本金的草稿發布保持原子性，prepared／committed 後只產生一次財務效果。[0.10.0+14 開發包](installable-preview.md)通過身份、簽章與 ARM64 Flutter／SQLCipher 核心核對，只留本機。

兩個 GitHub Actions workflow 仍停用，雲端未執行；手機未操作。實機 Keystore、生命週期、TalkBack 與平台還原 gate 等使用者回來，不能用本機結果取代。main 不合併，需雲端 gate 的分支不收斂；其餘 CORE 保留。
