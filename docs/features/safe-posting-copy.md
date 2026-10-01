# 安全複製日常收支

2026-09-28 更新：[多分類拆分](split-entry-drafts.md)已延伸複製契約：保留 2～16 項分類結構，停用分類留空待選，所有金額及日期重新填寫。以下為 0.5.1 原始批次紀錄；目前格式與後續草稿／隱私進度以[最新進度](../work-progress.md)為準。

**狀態：實作、本機回歸及 0.5.1 封裝核對通過；雲端與實機未驗收。**

接續 [商家 PR #47](https://github.com/swz0103/ExpenseTracker-V2/pull/47)（`053b476342b0929f974d1541cc52f1b77e30d128`）。來源：[M1-02](../delivery/implementation-plan.md)、[RC-02](../architecture/architecture-baseline-v1.0-rc1.md#rc-02)、[FV-088](../architecture/full-vision-baseline.md#fv-088)、[Q157](../architecture/full-vision-baseline.md#q157)。

## 行為

收入／支出列表的「交易操作」選單可選「再記一筆類似交易」。只沿用目前可用的帳戶、幣別、單一分類、Tag 與商家，以及收支方向。金額與日期清空，必須重新輸入；原交易的 operation／event ID、備註、附件、發票及外部身份不複製。

封存或已合併的分類、Tag、商家不偷偷導向另一身份，該欄清空並提示重新選擇；改名仍是原身份，使用目前版本。失去可用帳戶、期初事件或不存在的來源均拒絕。未來 split 多分類資料不能直接轉成目前單分類表單；會清空並提示，不能把原金額分攤帶入。

普通「記一筆」仍是乾淨表單。準備複製、取消與重複開啟均不寫入帳本；確認金額日期後才走既有 Domain validation、原子提交及重試機制，產生新操作與新事件。

## 接口與回查

`LedgerSession.entry(workspace, id)` 只讀取指定 workspace 的既存事件；列表與單筆查詢共用同一列轉換，避免讀取邏輯分歧。不存在或跨帳本 ID 回傳空，已關閉工作階段拒絕呼叫。

`PreviewEngine.preparePostingCopy(id)` 以已解鎖、已升級至 schema 5 以上的工作階段讀取權威資料，不信任畫面傳回的交易物件。回傳不可變的 `PostingCopy`，型別不含金額、交易日期或操作身份；沿用原有排他與鎖定 epoch 檢查。進階自訂複製模板依 rc1 保留，本批沒有新增通用模板引擎。

本批不新增資料表、schema 或備份格式；仍為 schema 7／snapshot 6。財務寫入、加密與還原程式未修改，沿用 #47 的完整 16 套件 626 項與兩組五千筆資料證據，不把既有驗證冒稱為本批重跑。

## 驗證與後續

新增案例涵蓋工作階段與 workspace 隔離、現行版本、封存合併不轉向、重複準備不新增事件、準備前後完整 snapshot 不變，以及 360×740 上完整複製／拒絕空金額日期／新舊交易核對。[本批清單](../test-results/2026-09-27/safe-posting-copy-host-2026-09-27.json)記錄 7 項 Ledger 工作階段、66 項完整 App 回歸、格式／分析及實際架構掃描通過，新增共 6 項。最後補強的同一 widget 另核對非預設來源帳戶，不重複累加測試數。

表單自動保存／恢復草稿、隱私遮罩與其餘 M1-02 細節仍待接續；其他 M1／M2／M3 CORE 及實機 gate 仍保留。Actions 不啟動、main 不合併，沒有操作手機。
