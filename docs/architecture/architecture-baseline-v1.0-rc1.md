# ExpenseTracker V2 — Architecture Baseline v1.0-rc1

日期：2026-09-26  
狀態：Release Candidate／待最終架構審查；尚未 Freeze  
定位：Android 優先、Flutter、Local-first 個人財務管理 App  
配套文件：[Full Vision Baseline](full-vision-baseline.md)

整合閱讀：[架構提案與已選方向](architecture-proposal.md) · [實作計畫](../delivery/implementation-plan.md)。D-001／D-002 為模組協調與業務套件方向；D-003 已採用 1A／2A／3A，本文件同步其呈現口徑、首批備份及交付順序。工程細節仍須驗證。

> **核心能力完整實作；未使用的進階能力保留正確的介面、資料邊界與遷移路徑。UI 保持簡潔。**
>
> 本文件是第一階段的範圍與驗收基準，不代表程式已實作或通過驗證。原始 170 題、完整 v0.9 的 104 節與最新 review 已全部取得並核對。來源與原對話編號更正見 [Full Vision 來源說明](full-vision-baseline.md#source-status)。來源完整不等於已批准 Freeze；本文件仍為 rc1，待最後架構審查。

## 文件使用方式

Full Vision 保存長期產品能力與歷史方向；本文件決定現在要做多少。兩份文件有差異時，**第一階段交付範圍以本文件為準，長期能力不得因延後而從 Full Vision 刪除**。若涉及核心不變條件，必須提出 ADR，不可用範圍縮減繞過財務正確性。

`FV-xxx` 是 Full Vision 的文件條目編號，不是原討論第幾題；`RC-xx` 是本文件的範圍契約。每節的來源連結可追溯長期能力；Full Vision 也會反向連結回本文件。相對連結可連同兩份文件直接放入 GitHub `docs/`。

最新 review 明示的調整視為本次整理依據；本文件為使交付可驗收而補充的細節，以「rc1 細化提案」標示，並集中列入 [Freeze Gate](#rc-22)，不冒稱先前已定案。

## 導覽

- [RC-01 分類與 Capability](#rc-01) · [RC-02 介面與導航](#rc-02)
- [RC-03 Ledger](#rc-03) · [RC-04 Money／FX](#rc-04) · [RC-05 帳戶與分類](#rc-05)
- [RC-06 資料與模組地基](#rc-06) · [RC-07 信用卡](#rc-07) · [RC-08 投資](#rc-08)
- [RC-09 預算與定期交易](#rc-09) · [RC-10 搜尋與條件模型](#rc-10)
- [RC-11 OCR／發票／Matching](#rc-11) · [RC-12 對帳](#rc-12) · [RC-13 報表](#rc-13)
- [RC-14 備份與還原](#rc-14) · [RC-15 安全與復原](#rc-15)
- [RC-16 延後的財務模組](#rc-16) · [RC-17 提醒與 Calendar](#rc-17)
- [RC-18 匯入匯出](#rc-18) · [RC-19 事件與背景工作](#rc-19) · [RC-20 Sync／共用](#rc-20)
- [RC-21 品質門檻](#rc-21) · [RC-22 交付順序與 Freeze Gate](#rc-22)
- [RC-23 後端、設定與平台](#rc-23) · [RC-24 發版與開發治理](#rc-24) · [RC-25 外部入口與操作安全](#rc-25)
- [170 題當期追溯索引](#decision-scope-index)

<a id="rc-01"></a>
## RC-01｜CORE／EXTENSION-READY／OPTIONAL

來源：[產品原則 FV-001](full-vision-baseline.md#fv-001)、[按需載入 FV-002](full-vision-baseline.md#fv-002)、[原始廣域範圍 FV-003](full-vision-baseline.md#fv-003)、[最新原則 FV-078](full-vision-baseline.md#fv-078)、[最新 review](full-vision-baseline.md#review-source)。

**CORE**：第一階段必須完成實作、資料遷移、測試與必要 UI。包括 Ledger、記帳、帳戶、分類、Merchant、Tag、轉帳、拆分、退款、多幣別、基本 FX、信用卡、基本分期、股票／ETF 投資核心、Budget、Recurring、Search、Reports、Security、Backup／Restore、Import／Export、Design System。Provider interfaces、Module APIs、Capability registry、migration framework 是核心地基。

**EXTENSION-READY**：第一階段交付的是可評審的契約與接入路徑。須交代資料擁有者、輸入輸出、錯誤、版本、權限與遷移方式；不要求提前完成 Domain、引擎、空資料表或 UI。不能用永遠回傳成功、零餘額或空集合的假實作表示已支援。

**OPTIONAL**：第一階段以後按需求實作與驗證的能力，例如 OCR、電子發票、Calendar、Forecast、Loan。可預留 EXTENSION-READY 接口，但這不等於 Optional 功能已完成，也不承諾能下載可執行模組。

同一模組可以有 CORE 子集與 OPTIONAL 子集；本文件按具體能力分類，不用整個模組的標籤掩蓋未完成部分。

**rc1 細化提案：將範圍、成熟度與交付方式分開記錄。**

- `scope`：CORE／EXTENSION-READY／OPTIONAL。
- `maturity`：reserved → implemented → verified；`deprecated` 表示退役計畫。
- `enabled`：獨立布林值；正式啟用必須已 verified，且依賴、migration、權限均可用。
- `experimental`：僅 dev／staging；不能冒充正式 verified。
- `delivery`：內建、可下載資源或待平台驗證的正式選配交付機制。
- `uiVisible`：不決定底層是否完成。隱藏 verified 功能是產品選擇，隱藏 unfinished 功能不構成實作完成。

預設只露出已驗證且有需求的功能，不展示未實作選單。核心本機功能不依賴登入、網路或雲端。雲端備份、行情更新本身需要網路，但失敗不得阻止本機記帳。

按需下載優先用於模型、規則資料、reference data 與 assets；必須有版本、完整性驗證與相容性檢查。GitHub APK 路線的程式碼隨 App release 發布。可執行的選配交付留到平台與發布流程驗證後再決定；不建立任意遠端程式碼執行系統。

<a id="rc-02"></a>
## RC-02｜簡潔 UI 與 Design System

來源：[導航 FV-004](full-vision-baseline.md#fv-004)、[首頁 FV-005](full-vision-baseline.md#fv-005)、[錄入 FV-006](full-vision-baseline.md#fv-006)、[原題 169／170](full-vision-baseline.md#question-register)。

**CORE**：底部導航固定「首頁｜帳本｜＋｜報表｜資產」。低頻設定、安全、備份、匯入走次級入口。中央 `＋` 開 Quick Sheet，以金額、收入／支出、帳戶、分類、商家為主要欄位；更多欄位進完整表單。Transfer、換匯、投資、Refund、Reversal、信用卡繳款使用專用流程。

首頁固定當期收支、淨資產／帳戶摘要、最近 5 筆交易。預算摘要、待繳信用卡、一行投資摘要與最近 3 筆即將發生事項可關閉；未啟用的來源不出現。第一階段的即將發生事項僅取已實作的信用卡、分期與 Recurring，不為首頁順便實作 Bills／Loan。

**D-003／1A 已選**：日常以消費為主要口徑，付款安排另看；分期購買總消費歸購買月份，每期應繳／實際付款分開顯示，繳款不重複列消費。退款在退款期反映並連到原消費；任何另列的歷史淨消費分析須標示口徑。依 3A，M1 未實作信用卡／分期時隱藏其專用摘要與入口，不能用一般記帳流程冒充支援。

Design System 統一金額、幣別、日期、隱私遮罩、載入／錯誤／空狀態、表單驗證與風險確認。視覺採暖色、淺背景，避免大量卡片堆疊。金額輸入支援 `+ − × ÷ % ()`，沿用 Money 規則。

**補齊原決策後的 CORE 體驗契約**：Material 3 為底，自建 semantic color、typography、spacing、radius、elevation 與表單／sheet／dialog／list／chart 元件。第一階段繁中、淺色；從第一天採 i18n，locale 的幣別、日期、時區、百分比與負數格式只影響呈現。深色模式預留 tokens，UI 後續開放。無障礙須驗證字體縮放、touch target、screen-reader label、對比、非僅靠顏色辨識、清楚錯誤與 reduced motion。

Onboarding 只引導基準幣別、主要帳戶、信用卡、預設分類、安全與備份，全部可跳過；跳過時提供可用預設或在真正需要時再填，不建立無效財務資料。分類提供精簡完整的起始集合；空狀態引導下一步，不塞假交易。完整表單狀態包含 pristine／dirty／validating／valid／invalid／submitting／failed、跨欄位與非同步驗證、草稿恢復；使用者開始操作後才提示，送出仍做 Domain validation。這是表單草稿能力，不要求先完成通用 Financial Inbox。

儲存後返回來源 Context。新交易預設乾淨表單；「再記一筆類似交易」只複製帳戶、分類、商家、Tag、幣別，不沿用金額、日期時間、備註、附件、發票或 external ID。交易列表依日期分組並列每日收支；swipe 限低風險操作。明細可展開資金流、split、fee／tax、FX、退款與 Activity Timeline，但 raw event／leg／revision ID 只放 Diagnostics。未啟用能力不出現展開項目。

圖表支援 drill-down／tooltip／期間切換；動畫輕量且遵守 Reduce Motion。首頁平時自動更新，下拉只檢查 freshness、按需觸發已啟用的行情／FX／備份工作，不重算整庫；Calendar 未啟用時不執行 Calendar 工作。來源：[FV-085～FV-091](full-vision-baseline.md#fv-085)、[Q152～Q170](full-vision-baseline.md#q152)。

**EXTENSION-READY／延後**：Dashboard 區塊契約可註冊可用能力；自由拖曳、縮放與 Dashboard Builder 留待 OPTIONAL。不為未完成功能建立可點擊入口。

驗收：關閉所有選配摘要後仍能完成日常記帳；一般新增與專用流程都通過同一 Domain 驗證；首頁摘要可追查至正式交易。

<a id="rc-03"></a>
## RC-03｜Ledger、交易與財務不變條件

來源：[Ledger FV-007](full-vision-baseline.md#fv-007)、[Revision FV-008](full-vision-baseline.md#fv-008)、[metadata FV-013](full-vision-baseline.md#fv-013)、[lifecycle FV-014](full-vision-baseline.md#fv-014)、[Split FV-016](full-vision-baseline.md#fv-016)、[Tax／Fee FV-047](full-vision-baseline.md#fv-047)。

**CORE**：Financial Transaction 聚合多個 Ledger Legs。收入、支出、轉帳、Split、部分／全額退款、Reversal、Adjustment、Opening Balance、revision、soft delete、多幣別與結構化 Fee／Tax 必須由 Domain 表達。

核心不變條件：

1. 正式帳戶餘額可由有效 Ledger 與明確事件重建；禁止直接修改 current balance 對平。
2. Transfer 為單一完整事件，所有 legs 與必要 metadata 在同一 ACID 交易提交或全部回滾；不能留下單邊轉帳。
3. 同幣別 Split 子項加總等於母項；尾差按明確 policy 分配，不遺失 minor unit。
4. Refund 必須追溯原交易與可退款部分；Reversal 為新的反向財務事件。一般編輯保留 revision；正式財務意義改變不得覆寫歷史。
5. 一般刪除採 tombstone。已過帳信用卡與投資等具有後續依賴的資料，須透過相應更正流程，不以刪除迴避一致性。
6. Opening Balance 不列一般收入；轉帳本金與信用卡還款不重複計為消費；本金、利息、費用有明確分類。
7. Draft、Staging、尚未確認的未來事項不影響正式餘額與已實現報表；Pending 與 Posted 分開呈現。
8. Note 只放使用者文字；Audit／Activity Timeline 使用獨立模型。

**Charge／Adjustment 接入契約**：依 [Q148](full-vision-baseline.md#q148) 保存費用類型、金額、幣別、收取方、是否已包含於總額、原事件關聯；首版 Fee／Tax／Interest／明確 Adjustment 共用正式 component 語意，避免投資、信用卡、換匯各自發明不可對照的欄位。完整 framework 長期涵蓋 Fee／Tax／Discount／Rebate／Cashback／Interest；但 [Q150](full-vision-baseline.md#q150) 已選折扣採實付額、延後 Cashback 獨立交易，不為折扣或點數提前開發 Reward Engine。第 147 題沒有改選完整 Tax Engine，編號更正見 Full Vision。

**rc1 細化提案**：跨幣別 legs 不可將不同幣別的裸數字相加判斷平衡。每個事件類型必須定義其資金來源／去向、估值、費用與尾差檢核；multi-leg 不等於本文件已選定完整總帳科目體系。Refund 的超額檢核、revision 有效版本與反轉後餘額必須納入 Domain 規格與測試。

**EXTENSION-READY／延後**：multi-account payment、mixed payment、Split template、完整 Tax Rule Provider、Reward／mileage／point system。目前保留多 leg、來源引用與結構化 components；不建完整報稅引擎。折扣採實付額；延後入帳的 Cashback 是獨立回饋／Adjustment。

驗收：新增、編輯、刪除、轉帳、退款與反轉後，重建結果一致；故障注入不產生半筆事件；重複提交不重複扣款；不同日期、幣別與四捨五入邊界有 property tests。

<a id="rc-04"></a>
## RC-04｜Money、多幣別與 FX

來源：[精度 FV-009](full-vision-baseline.md#fv-009)、[多幣別 FV-019](full-vision-baseline.md#fv-019)、[FX FV-020](full-vision-baseline.md#fv-020)、[重估 FV-021](full-vision-baseline.md#fv-021)。

**CORE**：Ledger 使用整數 minor unit；匯率、股價、數量／成本計算用明確精度的 Decimal。核心財務計算禁止 binary floating-point。幣別精度與 rounding policy 由 Domain 管理；Split 最後一項、分期最後一期依 policy 吸收尾差，FX 在指定邊界 round，投資成本保留高精度。

保存原幣、原額、實際成交匯率、費用與 conversion context；每個 workspace 有 base currency。歷史交易不得用今天匯率覆寫；報表顯示幣別的臨時切換是展示／估值，不改交易。

**CORE 契約**：FX Provider 支援指定日期、幣對、來源、取得時間、使用者覆寫與缺值結果。第一階段整合主要來源即可；允許手動輸入歷史或成交匯率。缺匯率時顯示資料不足，不默認 1:1 或悄悄套用現值。

**EXTENSION-READY／延後**：bid／ask／mid 多種報價、官方／市場匯率路由、confidence、完整 FX cost basis、獨立 realized FX P/L、期間重估及 market return／FX return attribution。保留率值來源與時點、valuation context，不提前建完整 FX attribution engine。

驗收：不同 minor-unit 幣別、極小／極大金額、負數、逆向換匯、匯率缺值、尾差與歷史重算；查價失敗不阻止已具備明確交易金額的離線記錄。

<a id="rc-05"></a>
## RC-05｜Account、Category、Tag、Merchant

來源：[Account FV-010](full-vision-baseline.md#fv-010)、[Category／Tag FV-011](full-vision-baseline.md#fv-011)、[Merchant FV-012](full-vision-baseline.md#fv-012)。

**CORE**：帳戶類型涵蓋 Cash、Bank、Digital Bank、Credit Card、E-wallet、Stored Value、Investment、Other Asset、Other Liability。開戶時間、Opening Balance event、關戶驗證、剩餘餘額處理、reopen 與 archive 具明確 lifecycle。第一階段不開放任意自訂帳戶類型。

Category 固定 Parent → Subcategory；收入與支出在產品上分開。Tag 是平面情境 metadata。Merchant 為 canonical identity 與基本 alias 的正式 Entity，支援交易歷史；不可只是散落文字，也不自動合併重要實體。

**EXTENSION-READY／延後**：自訂帳戶類型、Merchant branch／location、rule memory、OCR／地址／機構代碼／symbol／ISIN 的進階 Entity Resolution。透過 Entity ID 與 alias 接入，保持歷史引用穩定；與 Person／Organization 關係圖的擴充見 [RC-16](#rc-16)。

帳戶另保存是否計入總資產的明確設定；淨資產仍限金融資產／金融負債。已被交易引用的 Account／Category／Merchant 採 Archive + Merge／Replace；替代關聯需可追溯，不強刪歷史。關閉帳戶前處理餘額與未結項目，opening event 不計一般收入。

**rc1 細化提案**：原 [Q061](full-vision-baseline.md#q061) 的 FinancialInstitution 與自訂帳戶群組先保留契約，UI／完整 entity 延後；Institution 將承載機構識別、Logo、import rules、connector，Group 僅作整理，不能改 Ledger 計算。原 [Q027](full-vision-baseline.md#q027) 的商家規則記憶、[Q068](full-vision-baseline.md#q068) 的結構化地點及 [Q069](full-vision-baseline.md#q069) 的分店辨識也採同一分期提案：保留 alias／EntityRef／PlaceRef，不提前做預測、位置追蹤或場所辨識引擎。啟用後仍只能建議，不自行入帳。

驗收：關戶不遺失歷史；archive 後仍能查舊交易；分類與 Merchant 合併／更正不造成孤兒引用；帳戶餘額不由帳戶表獨立寫入。

<a id="rc-06"></a>
## RC-06｜時間、資料、Workspace 與模組邊界

來源：[時間 FV-015](full-vision-baseline.md#fv-015)、[資料庫 FV-061](full-vision-baseline.md#fv-061)、[Riverpod FV-062](full-vision-baseline.md#fv-062)、[模組 FV-063](full-vision-baseline.md#fv-063)、[ID FV-068](full-vision-baseline.md#fv-068)、[lifecycle FV-069](full-vision-baseline.md#fv-069)、[Workspace FV-070](full-vision-baseline.md#fv-070)、[Audit FV-071](full-vision-baseline.md#fv-071)。

**CORE**：Flutter、Riverpod、Drift + SQLite、Modular Monolith。呼叫方向為 UI → Controller／Notifier → Use Case → Repository Interface → Data Source → Drift／SQLite。Domain 不依賴 Drift model；Riverpod 處理 UI／async state、DI、orchestration 與 cache invalidation，業務規則留在 Domain。

Public／Domain ID 採 UUID v7；SQLite internal row ID 不離開 Data Layer。核心實體保存 `publicId`、`workspaceId`、`createdAt`、`updatedAt`、`deletedAt`、`version`，並具 actor／device／source／correlation metadata。按需求加 archivedAt；不全面 temporal 化。

時間模型可表達 occurredAt、authorizedAt、postedAt、settledAt、valueDate、importedAt；缺值保持缺值，不把不同語意日期硬填相同值。保存必要時區／offset 語意；日期型業務值與瞬間時間須區分。時間與 rounding 的具體序列化規格列入 Freeze Gate。

第一階段只建立唯一 `defaultWorkspace`，UI 為「我的帳本」，並有 base currency。所有屬於帳本的資料及 repository query 必須維持 workspace 範圍；全域 reference data 的例外要明示。

**CORE**：schema versioning、migration、ACID Unit of Work、Audit、encrypted storage。模組只能使用對外 Application API／Facade、事件及已定義的 read contract；不可直接存取其他模組的 internal repository／table。

Data Evolution 分別管理 DB schema、Domain、Event、Backup、Import 的版本與相容性；Sync protocol 的版本命名先保留，Engine 延後。一般 migration 採 transaction；重大 migration 採 Shadow／Copy：old DB → new schema → transform → invariant／checksum／verification → atomic switch，驗證完成前保留舊 DB，失敗走 rollback／recovery。此處的完整性不因其他進階功能減重而降低。來源：[Q041](full-vision-baseline.md#q041)、[FV-094](full-vision-baseline.md#fv-094)。

帳本設定與 Device Settings 分離：base currency、budget rule、report preference 屬帳本；PIN、生物辨識、Widget、Screen Security、通知權限、Calendar 連線屬裝置。Backup／未來 Sync 不以另一裝置設定覆寫本機安全狀態。多 Profile UI 延後。來源：[Q102](full-vision-baseline.md#q102)。

**EXTENSION-READY**：Module API 描述型別、錯誤、權限、版本、事件與 migration ownership；新模組新增自己的資料，不把所有未來欄位提前塞入核心。可以保存來源 module ID／external reference，但核心財務金額、時間與關聯不得藏在無規格 JSON。

<a id="module-extension-rules"></a>
### 框架先行的模組接入規則

依據：[使用者後續確認](full-vision-baseline.md#framework-first)。以下為落實此原則的架構約束；具體 API 與資料結構仍須經設計驗證。

1. **責任與依賴先確定**：每個模組列出擁有的資料、可呼叫的公開契約與禁止的依賴；不得形成循環依賴。UI 依賴 Use Case，Domain 不依賴畫面、資料庫套件或外部 provider。共用層只收 Money／ID／Time 等已有跨模組需求的穩定概念，不能成為所有業務邏輯的集中處。
2. **正式財務寫入有統一邊界**：信用卡、投資及後續 Loan 等模組，透過明確的 Ledger 寫入契約表達財務結果，不自行修改餘額或繞過不變條件。若模組狀態與 Ledger 必須一起成功，由 Application 層透過 Unit of Work 協調同一交易；非同步事件不能取代必要的原子性。
3. **讀取與外部整合有接入點**：報表使用已定義的 read contract／projection；Provider 的變動由 adapter 隔離。新增功能的路由、依賴注入與 Capability 在組裝入口接入，核心 Domain 不散落依功能名稱分支的判斷，也不建立任意動態插件框架。
4. **資料演進可驗證**：新模組擁有自己的 schema 與 migration；涉及既有資料、備份格式或公開契約時，明列版本、相容範圍及失敗復原方式。停用功能不應破壞已存在的 Ledger 紀錄與基本餘額重建；完整解除安裝與資料清除另行設計。
5. **擴充影響可檢查**：每項功能開工前列出要新增／修改的模組、契約與資料；完成時驗證新功能及受影響的既有流程。若一般擴充需要修改多個無關模組，先檢查責任邊界；若確實改變核心語意，提出 ADR 與遷移方案，不以「已留接口」假設相容。

<a id="a-plus-coordination"></a>
### D-001｜A＋：模組主責與小型操作協調

**狀態：使用者已選 A＋並授權優化；尚未實作驗證。** 來源與方案取捨：[Full Vision D-001](full-vision-baseline.md#decision-a-plus)。以下將 A＋具體化，不引入通用流程引擎，不替其他待決 ADR 預先下結論。

**1. 每種資料只有一個權威擁有者。** Ledger 擁有正式資金 legs 與財務 revision；Accounts 擁有帳戶設定與 lifecycle；Investment 擁有交易與 lot 的業務規則及權威紀錄。投資持倉摘要、帳戶餘額快取與報表為可重建投影，不另成一套事實。跨模組用穩定 ID 關聯；報表可保存有來源與版本的衍生資料，但不得反過來改寫正式財務紀錄。其他模組的完整資料歸屬仍由後續責任設計細化。

**2. 協調流程只管整個操作如何完成。** 它負責呼叫順序、交易邊界、跨模組結果對應與錯誤回傳。投資成本公式留在 Investment，Ledger 一致性留在 Ledger；兩者不互相重寫對方的公式。跨模組契約須核對同一操作的金額、幣別與來源關聯，不能因各模組各自合法，就假定組合後一定正確。

**3. 按業務操作拆分，不按每個步驟拆框架。** 買入、信用卡繳款等各有可追查的 Use Case，不建立包辦所有功能的巨型 Coordinator。單一主責模組的流程放在其 Application 層；沒有自然主責的跨模組流程放在 App 的組裝／workflow 層。模組 Domain 不反向依賴該流程，參與接口不再啟動另一個頂層流程。一般單模組操作直接走自己的 Use Case，無須額外繞一層。

**4. 一個操作只有一個本機提交邊界。** 頂層 Use Case 開啟 Unit of Work；參與模組透過 transaction-scoped 接口操作同一 SQLite transaction，不各自開連線提交，也不把資料庫 handle 暴露給 Domain。正式 Ledger、必要業務紀錄、Audit、操作結果及必須可靠排程的 job／outbox 一起提交；失敗一起回滾。這不要求全部報表摘要同步計算。遠端 API 不在本機 transaction 中執行。

**5. 防止預覽到提交之間資料改變。** 預覽結果不具入帳效力。提交時在交易內重新讀取或檢查相關版本，重新驗證帳戶狀態、可操作數量、原交易關聯與使用的估值條件；不得直接保存過期預覽。影響使用者已確認金額或條件的改變須回傳衝突並重新確認，不能偷偷套用新行情或匯率。

**6. 相同操作重試只產生一次財務效果。** 每次使用者意圖有穩定的 operation ID，配合 workspace、操作類型及標準化輸入指紋做持久去重；同一次重試沿用原 ID，新的一筆相同金額交易使用新 ID。去重紀錄與正式結果在同一 transaction 寫入，透過唯一性約束處理競爭；相同 ID／相同輸入回傳原結果，相同 ID／不同輸入明確拒絕。成功但回覆遺失時能查回原結果；不同 ID 的匯入重複仍需另用來源身份檢查，不能以此取代 RC-18 的來源去重。

**7. 必要後續工作不依賴一次記憶體通知。** 影響當次寫入正確性的資料在同一交易內處理；可延後的報表投影使用持久待更新紀錄／版本與可重建機制。確實需要可靠外送的流程才寫必要 job／outbox，沿用 [RC-19](#rc-19)。通知、報表或外部服務失敗不撤銷已完成的財務交易，也不讓 UI 誤報為整筆未存而誘發再次入帳；結果區分「財務已提交」與「後續工作待完成」。

**8. 接口保持具體，擴充按真實需求發生。** 使用型別明確的命令、結果與可辨識錯誤，不傳任意 map／JSON 讓各模組自行猜測。UI 只接收適合呈現的操作結果，不依賴內部資料表。Ledger 不因每新增一個來源模組就多一套專屬入口；能用既有財務語意表達時重用契約，新增財務語意則經 ADR 演進，不能強塞進萬用欄位。先有具體流程，再從已證實重複的行為抽出共用部分。

**買入範例**：Use Case 接收已確認的買入命令與 operation ID → 在同一 Unit of Work 內檢查去重、讀取有效狀態 → Investment 驗證交易並產生買入結果及資金需求 → Ledger 驗證資金 legs，流程核對來源與金額對應 → 參與模組保存各自權威紀錄與必要後續工作 → 統一提交 → 回傳正式結果。投資與 Ledger 任一步失敗，均不留下單邊紀錄。行情若需要網路取得，先在 transaction 外完成，再由提交流程驗證使用者確認的條件。

**驗收門檻**：注入任一提交前步驟失敗，不留下半筆買入／扣款；提交後程序中斷，再以相同 operation ID 重試，回傳同一結果且不新增交易；相同 ID 的不同輸入被拒絕；預覽後相關資料改變不靜默覆蓋；漏接記憶體事件後投影仍可恢復；新增來源模組走既有契約時無須修改無關模組；依賴檢查阻止跨模組 internal 存取及循環依賴。這些是後續程式驗證要求，不宣稱目前已通過。

**成本與界線**：需要設計明確的參與接口、錯誤、operation ID 保存與相容規則；新增真實財務語意仍可能修改核心。此版不建立通用 Command Bus、DAG、Saga、可執行流程 DSL；業務套件與內部拆分依後續已選定的 [D-002](#module-enforcement-options)。操作結果保存／清理與備份還原後的去重相容性，在具體資料模型定案時補齊，不能直接套用任意短期 TTL。

<a id="module-enforcement-options"></a>
### D-002｜按業務拆套件，業務內按需要再拆：已選定

**狀態：使用者已選定，尚未建立程式或驗證。** 使用者原答：「可以那就按照業務來拆，甚至業務內有必要也可以再拆」。採用下方 D，並明確允許業務內部有必要時繼續拆分；完整主模組清單、各套件公開契約與具體內部拆分仍須設計。來源：[Full Vision D-002](full-vision-baseline.md#decision-module-enforcement)。

此決策延續 [Q034](full-vision-baseline.md#q034) 的 Modular Monolith 與 [D-001](#a-plus-coordination) 的 A＋。原助手「不要過度拆 package」的實作建議不構成限制；套件數量不作為設計好壞的主要判準。架構方向定清楚前不建立程式骨架，不提前實作延後模組。

**落實規則（依已選方向細化）**：

1. **按業務責任建立套件**：例如 Ledger、Accounts、Credit Cards、Investment、Budget、Reports；例子不是完整套件清單。每個模組列明自己擁有的資料與規則、公開入口、允許依賴及必要測試。套件隨該功能進入實作才建立，延後能力先保存邊界與接入設計。
2. **業務內可以再拆**：當子能力有清楚責任、可說明的接口，而且拆分有助於獨立變更／驗證／重用或隔離外部依賴時，可再拆子模組或套件。不設固定套件數上限，也不規定每個模組只能一個套件。若只是整理檔案且沒有獨立依賴需求，仍可用內部資料夾。
3. **拆分要記錄收益與代價**：每次拆分說明主責、資料歸屬、輸入輸出、依賴、測試及 migration 責任。拆分後若常見業務修改總要同時修改多個子套件，重新檢查邊界；不是禁止跨套件修改，而是避免沒有實際隔離收益的拆分。
4. **核心規則維持獨立**：業務套件內 Domain 不依賴 UI、資料庫或外部 provider 實作；必要時可將 Domain、契約或 adapter 拆成子套件。App 負責組裝與跨模組流程；不用巨型 common／shared 套件收納不知歸屬的業務規則。
5. **內部拆分不增加外部負擔**：對外提供明確且精簡的業務接口；其他模組不能因內部拆出子套件，就直接依賴未公開的實作。由具體依賴圖決定接口所在位置，禁止循環依賴；不把所有模組接口再集中成彼此耦合的總套件。
6. **拆套件不拆原子提交**：仍採同一 repository 組裝發布的單一 App。套件不等於獨立服務、獨立資料庫或可下載功能；需要一起成功的本機財務操作，仍共同參與同一 SQLite transaction。業務及子套件的 schema 變更依資料擁有者提出，由 App migration 流程協調執行，不能各自遷移或提交而留下半套狀態。
7. **邊界靠可執行檢查維護**：CI 檢查公開接口、依賴方向、循環依賴及跨套件 internal 存取；同時跑受影響的模組與整合驗證。套件拆開不等於已通過架構驗收，也不取消契約與資料一致性檢查。

**先前方案比較（保留決策理由；目前採 D）**：

**A｜單一 App 專案，模組以目錄隔離，檢查規則守邊界。** 各模組仍有自己的 Domain／Application／Data／Presentation 與公開入口。優點是移動與調整方便、設定最少；缺點是隔離主要依賴自動檢查，漏掉規則時較容易產生不當引用。

**B｜只將共用基礎與 Ledger Domain 隔離為少量本機套件，其餘模組留在 App 目錄。** 共用基礎限 Money／ID／Time 等已確認概念；Ledger 套件只含 Domain 規則與必要契約，資料庫實作、UI 與跨模組流程在外部透過接口接入。同一 repository、同一次 App 發布，套件不代表按需下載。優點是優先約束最關鍵核心的依賴，核心測試可針對不依賴畫面與儲存套件的規則執行；缺點是多一些套件設定與接口設計，跨模組值型別放錯位置可能造成循環依賴。未來其他模組是否拆套件由實際需要決定，不預建空套件。

**C｜所有已實作模組的 Domain 集中到一個純業務套件，UI 與儲存實作放外面。** 業務套件內仍按模組分工並檢查內部依賴。優點是統一隔離業務規則與 UI／儲存，套件數量也少；缺點是各業務模組之間仍靠內部邊界檢查，共用業務套件可能隨功能成長而變大。

**D｜按業務模組拆本機套件，隨功能實作逐項建立（已選，並允許業務內按需要再拆）。** Ledger、Accounts、Investment 等已實作模組各有套件與公開契約，App 負責組裝；每個模組內如何隔離 Domain 與平台實作依具體責任決定。優點是各模組的公開入口、依賴與測試責任較明確；缺點是套件設定與跨套件接口變更多，需特別管理共用型別及同一 transaction 的參與接口。此案仍是單一 App 的 Modular Monolith，不等同微服務。

**驗收方向**：明列允許的依賴方向，CI 檢查循環依賴、跨模組 internal 引用、Domain 對 UI／儲存／外部 provider 的不當依賴，以及公開契約洩漏內部資料型別。拆 package 本身不代表已完全阻止越界，仍須檢查實際引用與依賴鏈。Domain 的隔離不改變共用 SQLite transaction、模組資料主責或 A＋的提交規則。

先前建議 B 未獲使用者選定；移除錯誤前提並討論按業務拆分後，使用者才明確選定本方案。不得以先前的 B 建議取代此後續決定。

驗收：既有版本 fixture 能升級，migration 失敗可保留原資料並進安全流程；新功能接入測試不需 UI 直接碰資料庫。Workspace／Sync 的完整引擎依 [RC-20](#rc-20) 延後。

<a id="rc-07"></a>
## RC-07｜信用卡與基本分期

來源：[信用卡 FV-017](full-vision-baseline.md#fv-017)、[Financing FV-018](full-vision-baseline.md#fv-018)。

**CORE**：正式信用卡 Domain；結帳日、繳款日、pending／posted、本期帳單、繳款狀態、基本額度資訊與基本分期。購買、待入帳、正式入帳、帳單歸屬與還款不得混為一個負數帳戶欄位。繳款走 Ledger Transfer，退款／更正保留來源關聯。

**Card FX 基本子集**：保留授權原幣金額、正式入帳金額、海外費用、settlement date 與 pending → posted 差異；一般 UI 顯示原幣／實際入帳／手續費。匯率／費用缺值不得偽裝為零，正式入帳依 statement／使用者確認結果更正，不保留兩筆重複消費。卡組織／issuer rate rules、複雜價差拆解與自動擷取延後，接口保留來源與生效日。來源：[Q128](full-vision-baseline.md#q128)。

**基本分期細化**：先支援期數、首期與週期、固定本金分攤、零利率或明列固定費用、最後一期尾差。D-003／1A 已決定購買月份記總消費，各期應繳與繳款分開；購買負債與各期投影的精確規格仍須完成，不能重複認列消費。未支援的計息條件明示 unsupported，不估成零利率。

**EXTENSION-READY／延後**：Issuer Adapter、特殊 APR、循環利息、statement installment 進階規則、提前清償／部分預付、主附卡共額、臨時額度、installment occupancy、pending holds、credit balance／overpayment 及 release timing 的完整 Limit Engine。保留 issuer policy contract 與 statement／payment／installment 關聯，暫不建通用融資平台。

驗收：跨月結帳、退款跨帳期、pending 轉 posted、部分繳款、尾差及更正均不重複計費。複雜額度語意未實作時不顯示成精確可用額度。

<a id="rc-08"></a>
## RC-08｜股票／ETF 投資與行情

來源：[Investment FV-022](full-vision-baseline.md#fv-022)、[Tax Lot FV-023](full-vision-baseline.md#fv-023)、[績效 FV-024](full-vision-baseline.md#fv-024)、[Instrument FV-025](full-vision-baseline.md#fv-025)、[行情 FV-026](full-vision-baseline.md#fv-026)。

**CORE**：股票／ETF、買賣、股息、fee／tax、多券商／帳戶、持倉、多幣別、取得 lot、部分處分與成本、已實現／未實現損益。保留原始交易、數量、取得日、成本與費用資訊，不只儲存平均單價。

正式驗證 Average Cost 與 FIFO；Corporate Action 先完成基本 stock split。績效先完成 Total Return、Realized／Unrealized、Dividend、XIRR。XIRR 必須區分可解、無解與不收斂，不把錯誤顯示為 0%。現金流方向、期間與估值來源須納入計算規格。

**CORE**：`MarketDataProvider` 與 `MarketDataRouter`。整合實際需要的主要股票／ETF 與 FX 來源；路由契約可 fallback，只有一個可用來源時回報來源失敗，不假裝已有第二個來源。快取、來源／時點、過期標示、rate limit 及 retry／backoff 按已接入來源落實。可用手動價格或最後已知價格呈現有日期的估值。

**EXTENSION-READY／OPTIONAL**：LIFO／Specific Lot Strategy；lot transfer 進階處理；CorporateActionHandler 的 reverse split、stock distribution、DRIP、Rights、Spin-off、Merger、Tender offer、Complex distribution；TWR、Benchmark、Attribution、Volatility、Max Drawdown、FX contribution；Funds、Bonds、REIT、Commodity、Crypto、Options 等商品 adapter。通用 Instrument 模型保留，未驗證商品不可誤套股票計算。

驗收：部分賣出、跨幣別費用、FIFO／平均成本、split 前後數量與總成本、股息與現金帳戶一致；行情缺值不偽造損益。供應商與授權尚未選定，不在本文件承諾特定市場覆蓋率。

<a id="rc-09"></a>
## RC-09｜Budget 與 Recurring

來源：[Budget FV-027](full-vision-baseline.md#fv-027)、[Recurring FV-028](full-vision-baseline.md#fv-028)、[Commitment FV-043](full-vision-baseline.md#fv-043)。

最新 review 將 Budget／Recurring 列為 CORE；以下最小子集是 **rc1 細化提案**。

**CORE Budget**：期間金額、雙層分類條件、帳戶／Tag 篩選、已用與剩餘、簡單門檻提示。共用 [RC-10](#rc-10) 的 AND 條件。報表與預算對 Transfer、Opening Balance、Refund 的計入方式必須一致且可解釋。重疊預算可各自顯示，但總覽不能直接相加造成雙算。

**D-003／1A、3A 已選**：消費預算採消費口徑，分期總消費歸購買月份，還款不再扣一次預算，退款在退款期反映。Budget／Recurring 於 M1 日常記帳之後的 M2 交付，仍屬第一階段 CORE。

**CORE Recurring**：日／週／月／年與每 N 期、開始／結束／次數上限、固定金額與使用者確認。月末缺日的策略須固定並可測試；補跑以 occurrence identity 去重。定期規則／候選項不等於已入帳交易；正式建立交易時才更新 Ledger。

**EXTENSION-READY／延後**：自訂 budget period、rollover、project／one-time budget 的完整 Domain、overlap priority；variable amount、prior-period reference、holiday adjustment、多步驟 automation、bill／statement linkage。保留規則版本、period／schedule policy、Predicate 與 occurrence contract；不為這些功能提前建 Workflow Engine。

驗收：月底、閏年、時區切換、離線補跑與多次 retry 不重複產生交易；修改 recurring rule 不回頭覆寫已入帳歷史。自動入帳是否首版開放列入 Freeze Gate，未定案前以確認流程為基準。

<a id="rc-10"></a>
## RC-10｜Search 與共用 Predicate

來源：[Rules FV-029](full-vision-baseline.md#fv-029)、[Search FV-048](full-vision-baseline.md#fv-048)。

**CORE**：versioned serializable 條件模型，先支援 AND、date、account、category、tag、merchant、amount、currency、transaction type；搜尋、Budget 與 Rule 的適用部分共用語意。商家／備註可提供基礎文字查找，不因此先建立自然語言編譯器。

Repository 負責將白名單條件轉為查詢，Domain 定義欄位、比較與範圍語意。未支援的條件或版本必須回報，不可默默省略條件而擴大結果。

**EXTENSION-READY／延後**：OR／NOT／nested expression、完整 AST compiler、規則 Priority + Specificity、衝突 Inbox、Saved Query／Custom Report、SQLite FTS、fuzzy／ranking、OCR text、進階 status／attachment 搜尋、Natural Language → Predicate AST。保留 Predicate version 與 search／projection interface，不先建立 Search Projection Framework。

驗收：搜尋與預算對同一條件集合選出一致交易；修改／刪除／退款後結果正確；日期與金額邊界、空條件與未知版本有明確行為。

<a id="rc-11"></a>
## RC-11｜Financial Inbox、附件、OCR、電子發票與 Matching

來源：[Inbox FV-030](full-vision-baseline.md#fv-030)、[OCR FV-031](full-vision-baseline.md#fv-031)、[Invoice FV-032](full-vision-baseline.md#fv-032)、[Matching FV-033](full-vision-baseline.md#fv-033)、[Attachment Storage FV-072](full-vision-baseline.md#fv-072)。

**CORE 子集**：Import／Export 所需的 Staging、preview、validation、重複候選與使用者確認，由 [RC-18](#rc-18) 實作。Staging 不進 Ledger／Balance／Reports。

**EXTENSION-READY**：AttachmentRef、來源 ID、candidate／match result／confidence／confirmation contract、交易與外部附件的關聯界線。將來正式附件儲存採 content-addressed blob、MIME／metadata、thumbnail、OCR／backup state，revision 引用同一 blob；首版沒有附件功能時不建空 blob store 或 OCR 表。

**OPTIONAL／第二階段起**：Receipt attachment → Local OCR → QR Invoice → 通用 Matching Engine → 使用者主動 Cloud OCR fallback。順序是接入建議，不是已承諾日期。完整 Financial Inbox、批次確認／忽略／分類／Tag、one-to-many／many-to-one、fuzzy、人工確認排序學習均延後；高風險候選仍需逐筆確認。

Invoice 未來保留號碼、日期、商家、金額、幣別、驗證、交易連結、QR payload、carrier metadata 與 API adapter。OCR 只預填，不能直接 posting；Cloud OCR 僅傳指定附件，不傳整份 Ledger。

接入驗收：一張收據與信用卡交易不能重複入帳；停用 OCR 不影響已確認交易；下載模型失敗不影響手動記帳。附件啟用時，同一 slice 必須完成加密、backup／restore、完整性與清理規則。

<a id="rc-12"></a>
## RC-12｜Reconciliation

來源：[Reconciliation FV-034](full-vision-baseline.md#fv-034)、[信用卡 FV-017](full-vision-baseline.md#fv-017)。

最新 review 沒有把完整 Reconciliation 列入第一階段核心清單，因此 **rc1 細化提案** 將正式引擎設為 EXTENSION-READY。

**CORE 子集**：Ledger 的明確 Adjustment、信用卡的 statement／payment 關聯、匯入的重複檢查與基本差異呈現；禁止直接改餘額。

**EXTENSION-READY／OPTIONAL**：statement cutoff、cleared／uncleared、snapshot／history、missing／duplicate detection、完整對帳精靈與進階修復工具。保留對帳狀態與外部對照引用的模型語意，避免 UI 的「已核對」覆蓋真正過帳狀態；資料表等實際啟用時才增加。

接入驗收：對帳結果可追溯當時交易版本；修正差異只生成受審計的財務事件；重跑不重複產生 Adjustment。

<a id="rc-13"></a>
## RC-13｜Reports 與少量 Projection

來源：[Analytics FV-049](full-vision-baseline.md#fv-049)、[Warehouse FV-050](full-vision-baseline.md#fv-050)、[Projection FV-051](full-vision-baseline.md#fv-051)。

**CORE**：Ledger 為 source of truth。先實作 `AccountBalanceProjection`、`DailyBalanceSnapshot`、`MonthlyCategorySummary`；投資需要時加 `InvestmentPositionProjection`。其他報表優先用 SQLite query + indexes，涵蓋收支、分類、帳戶餘額、淨資產與投資核心績效，並能 drill down 至來源交易。

Projection 必須有名稱／version、rebuild()、失效範圍與更新契約；必要的增量更新不演變成通用引擎。清楚呈現 stale／updating，不能把過期 projection 當作剛提交交易後的精確餘額。

**沿用已定案方向，不重複投票**：[Q124](full-vision-baseline.md#q124) 已選依資料用途區分一致性：帳戶餘額與關鍵 Ledger summary 在提交後立即一致；搜尋索引與常用報表可稍後更新；重型分析與歷史趨勢可背景處理。當畫面仍使用舊結果時，必須能辨認更新中／過期狀態。最新 review 延後的是通用 Consistency Tier 平台，不取消這些正確性要求。首版為實際使用的讀取模型逐項寫明更新契約即可；具體更新時間須經效能驗證，不能把來源中的「幾秒」當作已實測保證。

**rc1 細化提案**：影響寫入驗證或立即餘額的資料須在同一 transaction 更新，或直接讀 authoritative Ledger；可延後的摘要採可重跑更新。核帳與健康檢查可用獨立重建結果核對。

**EXTENSION-READY／延後**：完整 Analytics Warehouse Framework、通用 Incremental Projection Engine、checkpoint／dirty-range 管理平台、統一 Consistency Tier framework、Saved Query、Custom Report／Dashboard、Benchmark infrastructure。按真實查詢瓶頸逐項升級，不預建所有組合投影。

驗收：投影刪除後可從 Ledger 重建相同結果；revision／soft delete／refund／migration 後更新正確；報表 FX 來源與日期明示。

<a id="rc-14"></a>
## RC-14｜Backup、Restore 與長期封存

來源：[Backup FV-052](full-vision-baseline.md#fv-052)、[Restore FV-053](full-vision-baseline.md#fv-053)、[Archive FV-054](full-vision-baseline.md#fv-054)、[Encryption FV-055](full-vision-baseline.md#fv-055)。

**CORE**：Local-first + Cloud Backup，登入選配。完成版本化、加密、checksum／manifest、schema compatibility、revision／tombstone／audit metadata 保全、備份歷史、手動／自動備份、最後成功時間與 Restore。Cloud adapter 不綁核心 Domain；至少選定一條真實可驗證的雲端備份路徑後，才能宣稱雲端備份完成。沒有登入仍可本機備份與還原。

還原程序：

1. 驗證容器、解密及 manifest／checksum／版本；拒絕未知的不相容格式。
2. 在暫存區 dry-run，執行必要 migration、Ledger invariants、引用及已啟用附件驗證。
3. 重建 projection，確認核心資料可讀且一致。
4. 保留現有資料的安全備份；通過驗證後才以可回復的替換流程啟用還原資料。
5. 任一步失敗保留現有正式資料，不執行半套覆寫。

重大 migration 前必須有可用安全備份；只有生成檔案而從未驗證可還原，不算 Backup／Restore 完成。

**rc1 細化提案／必要安全門檻**：本機裝置保護與可攜備份解鎖是不同需求。跨裝置／重新安裝還原的備份，不能只靠原裝置上不可取得的密鑰。加密格式、KDF／密鑰取得方式與異機還原流程須在 Freeze 前確定並通過實測；checksum 不是密碼學驗證的替代品。未選定具體密碼套件，不在本版虛構實作已安全。

**CORE 匯出**：CSV／JSON 的基本資料輸出見 [RC-18](#rc-18)。Runtime DB、Backup Package、Canonical Archive 分離；一般 CSV 匯出不可稱為完整可還原備份。

**EXTENSION-READY**：先寫 Canonical Archive specification，定義 manifest、accounts／transactions／ledger_entries JSONL、entities、investments、metadata、attachments、schema、README、checksums 的責任與版本；先不完成全部 exporter／importer。

**D-003／2A 已選，首個可用版本必做**：最小 Key Envelope、備份密碼＋文字 Recovery Key、另行保存引導；在乾淨環境分別以兩條路徑驗證真實還原。App PIN／生物辨識與可攜備份解鎖分開；文字救援材料不自動與備份放在一起。實作格式與密碼套件須經 ADR-04 與實測，不能因選項已確認就宣稱安全。

**OPTIONAL／延後**：完整 Canonical Archive round-trip、超出密碼與文字 Recovery Key 的額外 wrapping providers、QR、完整 rotation／Recovery Health Check／獨立 test unlock 管理 UI。延後獨立工具不取消首批真實雙路還原驗證。未來 QR 不自動存相簿。這取代先前 review 將最小 envelope／文字 Recovery Key 一併延後的當期安排，長期願景不變。

驗收：乾淨環境／異機還原、損毀與截斷檔、錯誤解鎖資訊、不相容版本、空間不足及中斷場景；還原後餘額、歷史與投資持倉相符。

<a id="rc-15"></a>
## RC-15｜Security、Privacy、資料生命週期與 Safe Mode

來源：[Security FV-056](full-vision-baseline.md#fv-056)、[Privacy FV-057](full-vision-baseline.md#fv-057)、[Presentation Privacy FV-058](full-vision-baseline.md#fv-058)、[Lifecycle FV-073](full-vision-baseline.md#fv-073)、[Delete FV-074](full-vision-baseline.md#fv-074)、[Recovery FV-076](full-vision-baseline.md#fv-076)。

**CORE**：App PIN、Biometrics、automatic lock、encrypted local DB、平台安全儲存整合、encrypted backup；logout 不刪除本機財務資料。登入雲端失效與本機解鎖分開處理。

Privacy Capability contract 記錄使用何種資料、是否離開裝置、retention、是否可選與可撤銷。僅在啟用功能時請求對應權限；撤銷權限有可預期降級。Camera／Location／Calendar／Cloud OCR 尚未啟用時不提前要求授權。

共用 Presentation Privacy 支援 normal、hide amounts、minimal、background privacy shield；首版所有已存在畫面與通知沿用。Recent Apps preview 的保護要納入平台驗收。Widget／Shortcut 與分級 Screen Security 的完整擴展保留接口。

**CORE Safe Mode**：DB／Ledger health check 失敗就停止一般財務寫入；允許在資料可讀且安全時查看、匯出經去識別的診斷、重建可衍生 projection、以已驗證備份還原。重建／還原是受控復原寫入，不是允許一般交易繼續寫。無法安全讀取時不假裝可完整瀏覽。

啟動做 fast health check；migration／restore／異常關閉後及使用者要求時做 deep check，檢查已實作範圍的 Ledger invariant、orphan、revision chain、projection 與已啟用附件。進階 snapshot compare／repair workflow 延後；任何修改正式 Ledger 的 repair 均須先顯示影響並由使用者確認。預設本機 structured diagnostics，禁止記錄交易金額、merchant、account name、raw note、OCR 原文、附件內容與密鑰。遠端 Crash Reporting 預設關閉、opt-in，首版只留接口。來源：[FV-079](full-vision-baseline.md#fv-079)、[FV-096](full-vision-baseline.md#fv-096)。

**CORE 子集**：正式資料優先保留，限制暫存／診斷保留期間，做必要 integrity check。**EXTENSION-READY／延後**：統一 Storage Lifecycle Engine、attachment GC、revision compaction、tombstone purge、完整 Recovery Center 與逐筆 revision-chain 修復。關聯仍被歷史或備份需要時不可任意清理。

Delete／Purge 全文現已補齊：Workspace 刪除須有 PIN／biometric、impact preview、備份提示與 cooling-off；完整 purge 涵蓋正式資料、revision／tombstone、projection／index、無引用 blob、雲端副本與密鑰材料。rc1 將一般 soft delete／風險確認保留為 CORE，完整永久清除流程列 OPTIONAL，詳見 RC-25；不展示未完成的清除入口。

驗收：上鎖／背景切換／通知遮罩一致；日誌不泄漏敏感內容或密鑰；健康檢查失敗不繼續交易；重建失敗不破壞 source of truth。

<a id="rc-16"></a>
## RC-16｜延後的財務 Domain 與最小接入契約

以下能力均保留長期願景，**本階段 EXTENSION-READY，正式功能為 OPTIONAL**。本階段只完成必要的 API／資料邊界規格，不建立空 Domain 資料表或假 Service。共同接入點為 Financial Event／multi-leg、Account、Money、Time、Workspace、Repository、Migration 與 Audit；新模組透過 Application API posting。

- **Bills／Payables**：[FV-035](full-vision-baseline.md#fv-035)。延後 issued／due／paid、部分付款、逾期／late fee、auto-pay、correction 與附件。保留「Bill 不入 Ledger、Payment 才入 Ledger」與 payment reference；接入 Reminder／Forecast／Calendar。
- **Receivable／Lending**：[FV-036](full-vision-baseline.md#fv-036)。延後到期日、分次還款、分期／利息、展延／write-off、matching。核心可表達應收資產與還款，不能把借出本金當一般消費。
- **Shared Expense**：[FV-037](full-vision-baseline.md#fv-037)。延後多人、多付款者、等分／金額／比例、多幣別、部分還款與淨額結算；保留 obligation 與 settlement reference，不先做家庭權限。
- **Expense Claim**：[FV-038](full-vision-baseline.md#fv-038)。延後一單多筆、submitted／returned／approved／partial approval／paid、FX 與憑證完整性。代墊／應收／收款能在 Ledger 表達，審批狀態不直接改餘額。
- **Person／Organization／Institution Relationship Graph**：[FV-039](full-vision-baseline.md#fv-039)。延後雇主、商家歸屬、關係圖；保留 canonical entity reference，Merchant 核心照常完成。
- **Loan Engine**：[FV-040](full-vision-baseline.md#fv-040)。延後房貸／信貸／車貸、固定／浮動利率、rate history、grace period、repayment schedule、提前／額外本金償還。核心以負債帳戶與本金／利息／費用 legs 表達；不將房車等非金融資產納入既定淨資產範圍。
- **Goal**：[FV-041](full-vision-baseline.md#fv-041)。連基本 target／due date／linked account／progress／monthly suggestion 都依最新 review 延後；priority、自動提撥與預測也保留。未來讀取餘額，真正提撥仍走 Ledger。
- **Forecast／Scenario／Plan Execution**：[FV-042](full-vision-baseline.md#fv-042)、[FV-043](full-vision-baseline.md#fv-043)。延後 recurring／bill／card／loan／commitment 預測、支出／投資／FX／提前還貸情境及轉成計畫。保留 read model／assumption version／確認後命令邊界；Scenario 永不直接改 Ledger，Planned／Scheduled／Committed／PendingExternalConfirmation 在 Posted 前不算正式餘額。
- **Subscription Management**：[FV-044](full-vision-baseline.md#fv-044)。延後試用、續訂、價格歷史、使用狀態、偵測與專用提醒；以 recurring reference 接入，不把訂閱續約與扣款綁成同一已入帳事件。
- **Insurance**：[FV-045](full-vision-baseline.md#fv-045)。依最新 review 連基本保單管理也延後；保留 insurer／policy／premium／cycle／effective／expiry／next payment／attachment／status 的長期欄位方向。已發生保費仍可用一般交易記錄。
- **Income Source／Payroll**：[FV-046](full-vision-baseline.md#fv-046)。正式來源檔案與完整薪資引擎延後；一般薪資／接案／兼職收入可先記帳。保留 Organization、expected amount、pay cycle、account 的擴展方向；不先建薪資計算表。
- **Tax Engine**：[FV-047](full-vision-baseline.md#fv-047)。延後 jurisdiction／effective date／version／source／override 的 Tax Rule Provider 與完整稅務計算；實際交易 fee／tax components 是 CORE。下載規則資料不等於稅務引擎已完成。

每一個未來 slice 必須提交來源 FV ID、module contract、schema migration、Ledger mapping、rollback／停用策略、權限及測試。不得以「預留擴充」承諾所有未來功能零成本；目標是局部新增與遷移，不重寫財務地基。

<a id="rc-17"></a>
## RC-17｜Reminder、通知與 Google Calendar

來源：[Notification／Calendar FV-059](full-vision-baseline.md#fv-059)。

**rc1 細化提案**：CORE 只包含已實作信用卡／分期／Recurring 所需的簡單站內與系統通知 preset；排程使用 [RC-19](#rc-19) 的 persistent queue。通知失敗不能阻止記帳，通知內容沿用隱私遮罩。

**EXTENSION-READY／OPTIONAL**：通用 rule-based Reminder Engine、Google Calendar controlled bidirectional integration。保留 Reminder sink／external ID／correlation／difference contract。Calendar 外部修改只生成差異提示，不能直接改財務規則或 Ledger。未來可靠外送採同一 transaction 建立必要 outbox／job，且有去重與 retry。

驗收：同一 occurrence 不重複提醒；撤銷通知授權有站內降級；Calendar 未開發時不出現同步宣稱或 OAuth 入口。

<a id="rc-18"></a>
## RC-18｜Import／Export

來源：[Import／Export FV-060](full-vision-baseline.md#fv-060)、[Inbox FV-030](full-vision-baseline.md#fv-030)、[Archive FV-054](full-vision-baseline.md#fv-054)。

**CORE**：Adapter → Parser → Staging → Validation → 基本 duplicate check → Preview／mapping → Confirm → Ledger；批次具有來源與 correlation，可驗證與回滾。匯入不得繞過 Ledger use case、Money、Time、Workspace 或 Audit。

**rc1 細化提案**：第一階段完成自有 CSV／JSON 的 documented import／export schema，並提供至少一組真實 fixture 的 round-trip。匯入失敗在 transaction 中回滾；已正式提交後的撤銷若涉及後續依賴，須走受審計更正，不直接抹除歷史。

**EXTENSION-READY／OPTIONAL**：Excel、bank／card／broker statement、其他記帳 App adapters、可下載 parser definitions、通用 fuzzy Matching 與高階批次 Inbox。各 parser 輸出相同 staging contract；外部交易 ID／來源檔 fingerprint 與記錄身份用於去重，不把不同格式各做一套 posting。

基本資料匯出應告知涵蓋資料與損失限制；CSV／JSON 不自動等於完整 backup 或 Canonical Archive。完整 revision／tombstone／所有模組的可還原性由 [RC-14](#rc-14) 保證。

驗收：重複匯入、欄位缺值、錯誤幣別／日期、跨列不一致、部分失敗及再次重試不重複入帳；preview 不影響任何餘額。

<a id="rc-19"></a>
## RC-19｜Domain Event 與 Persistent Job Queue

來源：[跨模組 FV-064](full-vision-baseline.md#fv-064)、[transaction FV-065](full-vision-baseline.md#fv-065)、[Inbox／Outbox FV-066](full-vision-baseline.md#fv-066)、[Jobs FV-067](full-vision-baseline.md#fv-067)。

**CORE**：同步操作走 Application API／Facade；狀態變化使用 Domain Event，例如 TransactionPosted、RefundCreated、StatementClosed、InvestmentTradeExecuted。保留必要事件與 Audit，但不採 Full Event Sourcing。

背景工作先實作 **Persistent Job Queue + Idempotency + Retry／Backoff**，供已啟用的 Backup、Market refresh、Recurring、Reminder、health check 使用。程序重啟後可接續；工作需區分待執行、執行中、成功、可重試失敗與終止失敗，並能呈現必要錯誤。到達 retry 上限後停止自動重試，可人工處理，不需先建完整 DLQ UI。

本機財務 use case 以 ACID + Unit of Work 保證完整提交。外部 API 不放進 Ledger transaction。當業務確實要求 commit 後可靠執行副作用時，在同一 transaction 寫入必要 job／outbox，避免 commit 與排程之間遺失工作。

至少一次交付必須搭配 consumer 的 idempotency；對外服務使用可用的去重鍵與結果確認。不承諾所有外部 API exactly-once。工作 payload 與 handler 的相容性需要版本規則。

**EXTENSION-READY／延後**：全面 Transactional Inbox framework、通用 DAG、dependencies／priority orchestration、長任務 checkpoint framework、Saga、DLQ 管理 UI、通用 job migration platform。未來 Sync 出現真實需求再增補，不用相同複雜框架包住所有同步 use case。

驗收：在提交前／後與外部結果返回前／後中斷再啟動，最終不重複財務效果、不永久遺失必要工作；錯誤可辨識，重試有上限。

<a id="rc-20"></a>
## RC-20｜Sync、Multi-workspace 與 Family Sharing

來源：[Workspace FV-070](full-vision-baseline.md#fv-070)、[Identity FV-068](full-vision-baseline.md#fv-068)、[lifecycle FV-069](full-vision-baseline.md#fv-069)、[Sync review FV-075](full-vision-baseline.md#fv-075)。

**CORE 地基**：UUID、version、updatedAt、deletedAt、deviceId／actor metadata、defaultWorkspace、provider-neutral Repository／cloud adapter；Backup 保存 revision metadata。

**EXTENSION-READY**：Sync contract 記錄變更身份、版本、刪除與來源；只定義未來 adapter 邊界與 migration path，不執行同步。保留 Workspace Module 可新增帳本隔離、base currency、成員／權限的空間。

**OPTIONAL／全部延後**：multi-device state machine、field merge、conflict resolution UI、sync inbox／outbox、server change log、遠端雙向同步；多帳本切換、跨 workspace linked transfer、Member／Role／Invitation、Owner／Editor／Viewer、共享權限與 Approval flow。首版不建立這些空表。

Cloud Backup 是版本化快照保存與明確 Restore，不是多裝置同步，也不得自動合併兩份帳本。日後上線 Sync 仍需衝突、因果關係、刪除保留、安全與 migration 的專項設計；現有 metadata 只是準備，不代表已解決這些問題。

接入驗收：第二個 workspace 的資料隔離、conflict 不靜默丟失財務事件、權限撤銷與離線行為，屬於該 Optional slice 的正式 gate。

<a id="rc-21"></a>
## RC-21｜測試、效能與交付品質

來源：[Performance review FV-077](full-vision-baseline.md#fv-077)、[Ledger FV-007](full-vision-baseline.md#fv-007)、[Restore FV-053](full-vision-baseline.md#fv-053)。

**CORE**：Ledger 的 unit／property／fuzz tests，重要 use case 的 integration tests，migration fixture、backup／restore round-trip、故障重試與投影重建比對。UI flow 驗收至少涵蓋日常記帳、轉帳、退款、信用卡付款、投資買賣與復原。

保留 Repository Contract、determinism、random financial transaction generation、long-run simulation 與 disaster recovery 的測試方向；Sync conflict／進階 Reconciliation 的完整測試隨能力啟用，不在未實作模組建立假測試。CORE 金融邏輯採最高必要強度，一般 UI 採合理強度。來源：[FV-095](full-vision-baseline.md#fv-095)。

Query／Index governance 的第一階段交付：列出重要查詢模式、量測 query plan／延遲與寫入成本、記錄必要的慢查詢診斷，索引變更隨 migration review，重大 migration 前後做回歸比對。partial／covering index 依證據採用；FTS 未啟用不先建索引。完整 unused-index／index-size history 平台延後，避免無限制加索引。來源：[FV-093](full-vision-baseline.md#fv-093)、[Q113](full-vision-baseline.md#q113)。

產品目標保留 10～20 年、100k+ transactions。初期 benchmark 涵蓋 cold start、新增交易、載入一個月交易、首頁、月報、100k 查詢、backup／restore。測試資料需包含 revision、split、multi-currency 與投資，不能只測單一簡單表。

**rc1 細化提案**：第一階段 CI 跑靜態檢查、核心單元／整合、重要 migration 與可負擔的 smoke benchmarks；效能樣本記錄裝置、資料集、版本、冷／熱快取、量測方法。具體時間與記憶體門檻須有基線後在 ADR 核定，不在此虛構毫秒數。

**EXTENSION-READY／延後**：完整 performance history、nightly regression、巨大 Performance Platform、每個 PR 全量長時間 benchmark。必要測試不能因平台尚未建立而跳過。

原始 CI/CD 與 Codex 規範已補齊，正式要求 PR、Acceptance Criteria、Tests、Architecture／Migration Gate、Static Analysis、Security Check、exact SHA 與 release artifact traceability；禁止直接 push main。執行範圍與發版契約見 [RC-24](#rc-24)。

<a id="rc-22"></a>
## RC-22｜交付順序、待決事項與 Freeze Gate

<a id="framework-delivery"></a>
### 先確認整體框架，再逐功能交付

依據：[Full Vision 後續確認](full-vision-baseline.md#framework-first)。第一階段的 CORE 清單維持不變，但不要求一次完成全部 CORE 才驗證成果。

正式功能開發前，先形成可審查的框架設計：模組責任與依賴圖、核心資料關係與擁有者、財務寫入／讀取契約、交易邊界、錯誤處理，以及版本／migration／備份策略。需用跨幣別轉帳與費用、跨期退款、分期認列、投資交易更正等代表情境檢查契約是否足以承載未來能力；此階段不等於先完成這些功能。未知事項列入 ADR，以必要原型驗證，不提前建立所有未來資料表。

框架確認後，以下各 slice 再拆成逐項功能。每項依序完成「行為與驗收情境 → 影響範圍 → Domain／資料／必要 UI → 遷移與相關回歸驗證」，通過後才標示完成。需要依賴尚未完成能力時，明列依賴或縮成可成立的子功能，不提供假成功的入口。

第一條端到端驗證路徑為：建立帳戶與期初餘額 → 收入／支出 → 轉帳／退款 → 可核對的餘額與基本報表 → 備份 → 乾淨環境還原。這是提早驗證地基的路徑，不取代其他 CORE 的交付責任。具體功能順序可按依賴調整，整體框架變更仍須遵循 [RC-06](#module-extension-rules) 與 ADR。

**D-003／3A 已選的順序**；具體工作單與通過條件見[實作計畫](../delivery/implementation-plan.md)，不是各 Optional 能力的預定日期。

1. **規格與地基驗證**：先完成模型、接口及工程 ADR；再於後續實作階段驗證 Money／Time／ID／Workspace、跨模組 Unit of Work、migration／加密及最小雙路備份還原，通過相關 gate 才建立正式架構基線。
2. **M1 日常記帳版本**：Account／Category／Tag／Merchant、收入支出、multi-leg／Transfer／Split／Refund／Revision、多幣別基礎、Audit、Search、基本 Reports／Projection、CSV／JSON 與必要 UI；密碼＋文字救援金鑰、真實乾淨環境還原、安全／隱私／Safe Mode 與 migration 是本批必要條件。
3. **M2 日常管理與信用卡版本**：可靠 jobs 與真實雲端手動／自動備份、Budget／Recurring／提醒、信用卡／基本分期；M1 先以本機可攜加密備份檔提供保護，不能誤稱已完成雲端備份。M2 驗證升級及所有新增資料的備份還原。
4. **M3 投資與完整 CORE 版本**：股票／ETF／lot／成本／股息／基本 split、FX／行情與績效；逐項核對 rc1 全部 CORE、平台／更新發布、效能、跨版本 migration 與全模組 restore。信用卡與投資均仍是本版 CORE。
5. **每批交付都驗證**：品質、安全、備份與 UI 檢查隨功能完成；M3 的整體驗收不代替 M1／M2 必須先通過的資料保護門檻。

### Freeze 前必須結案

**決策方式調整**：使用者已選定 [1A 日常呈現口徑](architecture-proposal.md#choice-1)、[2A 首批備份解鎖範圍](architecture-proposal.md#choice-2)、[3A 分批交付](architecture-proposal.md#choice-3)，並要求先檢視實作安排。下列 ADR 的工程規格由助手整合與驗證，不再逐項變成使用者問卷。選項定案不代替安全、資料與架構 gate。

- **FRAME-01**：完成並審查上述模組／資料／契約設計與代表情境，確認擴充接入方式及影響範圍；文件原則已確認不等於框架設計或驗證已完成。
- **D-001（方向已選，驗證待完成）**：採用 [A＋](#a-plus-coordination)；模組主責、小型操作協調與統一提交為既定方向。具體接口、完整資料歸屬、operation ID 保存／還原相容規則與失敗驗證仍須完成，不以本項選定代替 ADR-01／ADR-07 的結案。
- **D-002（方向已選，結構設計待完成）**：採用[按業務拆套件，業務內按需要再拆](#module-enforcement-options)。完成實際主模組清單、依賴圖、資料與 migration 歸屬、對外接口及有必要的內部分拆理由；仍遵守先定方向再開始寫程式。
- **D-003（產品方向已選，尚未開工）**：1A／2A／3A 已同步至本文件；來源見 [Full Vision](full-vision-baseline.md#decision-product-delivery)。實作計畫供使用者檢視，不宣稱已有功能或已通過驗證。
- **SRC-01（已完成）**：170／170 題原答與 v0.9 104／104 節已核對；Q147～Q149 的來源編號錯誤已按後續更正處理。見 [逐題登錄](full-vision-baseline.md#question-register)。
- **ADR-01**：確認 Ledger 事件類型、有效 revision、退款上限、soft delete／reversal 交界，以及跨幣別守恆規則；不能把 multi-leg 自動解讀為已決定某個雙式科目表。
- **ADR-02**：確認幣別精度／rounding、Decimal 序列化、時間／日期／時區與月末策略。
- **ADR-03**：確認基本分期與負債／費用認列、退款跨期；確認投資策略、split 與 XIRR 的邊界。
- **ADR-04**：確認本機加密與可攜備份的密鑰取得、重裝／異機還原；完成真實 restore prototype 與威脅模型。
- **ADR-05**：確認本次細化的 Budget／Recurring 子集、人工確認或自動 posting、基礎提醒、Reconciliation 與 CSV／JSON／Excel 的首版界線。
- **ADR-06**：選定市場／FX／雲端備份 provider 及支援範圍；驗證平台整合與最低發布路徑。未選 provider 不是提前省略 CORE 行為的理由。
- **ADR-07**：確認 Capability 的多軸狀態、核心 projection 一致性策略與 job／outbox 原子性。
- **ADR-08**：將已核實的 CI/CD／發版／Codex 規範轉成可執行檢查，定義測試／效能基線、release channel metadata 與簽章管理。規範本身已確認，不重問既有選擇。

以上待決項須有文件決議或可驗證結果，不要求重新回答所有已做過的產品選擇。來源完整性已通過；ADR 未結案時可進行不受影響的設計／原型，不可宣稱整體架構已 Freeze。

### 第一階段完成定義

- 每個 CORE 子集有真實實作、必要 UI、migration 與相應測試；無以 stub 冒充 completed。
- Ledger 可重建、資料可備份及真實還原，Safe Mode 可阻止擴大損壞。
- 每個延後項目仍可從本文件連至 Full Vision；每個接入點有 ownership、輸入輸出／錯誤、版本與遷移說明。
- 非 CORE 不因文件存在而自動進入首版 backlog；改 scope 時同步更新兩份文件與 ADR。
- 已定案的財務、安全與資料不變條件不因 UI 隱藏而降低標準。

### 變更管理

保留 FV／RC ID，不重新編號；刪除或取代決策時保留 superseded 記錄與新決策引用。升級 Optional 能力時，逐項確認資料 migration、Domain invariants、權限、備份、停用後資料可讀性、效能與測試，再由 reserved／implemented 升為 verified／enabled。每次變更註記來源、理由、影響與審查結果。

本版整理來源為「重新開始記帳APP」的全部 170 題、完整 v0.9、減重 review 與本次後續明確決策。依後續指示已建立私人 [ExpenseTracker-V2](https://github.com/swz0103/ExpenseTracker-V2)，文件走分支／PR；環境狀態見[前置準備](../delivery/development-readiness.md)。兩份 Baseline 與配套文件一起保留於同一 `docs/` 目錄以維持引用，repository 建立不代表 Architecture Freeze。

<a id="rc-23"></a>
## RC-23｜Backend、Secrets、Config、平台與降級

來源：[FV-080](full-vision-baseline.md#fv-080)、[FV-082](full-vision-baseline.md#fv-082)、[FV-083](full-vision-baseline.md#fv-083)、[FV-084](full-vision-baseline.md#fv-084)、[FV-098](full-vision-baseline.md#fv-098)、[Q088](full-vision-baseline.md#q088)。

**CORE**：Vendor-neutral Hybrid Backend。登入、雲端儲存／metadata service 由 adapter 提供，Domain 只認 Repository／Service Interface；Supabase 是來源中的候選例子，不是已選定且不可替換的依賴。不得讓 Supabase／Firebase SDK 滲入 Domain，也不為首版建完整同步後端。

Secrets 分級不可延後：User OAuth token 放平台 secure store；public client identifier 才能進 app config；private provider key 放 backend secret store；server credential 僅供 server 使用。依憑證特性記錄 rotation／version／revocation，App 不內嵌應保密的供應商金鑰。選配 provider 尚未接入時不提前要求憑證。

Build Flavor 明確分 dev／staging／prod，隔離 endpoint、credentials、資料與 update channel。**CORE** 使用具版本及安全預設的設定；**EXTENSION-READY／OPTIONAL** 為完整 Runtime Config 發送系統。未來動態設定限非敏感、可安全調整項目，具簽章、版本與 fallback defaults；不能用遠端旗標繞過 Ledger invariant、migration／verification gate 或載入任意程式碼。

Android 優先但核心不綁 Android；SecureStorage、Biometrics、Calendar、Notifications、Update、Location 均經 platform interface。CORE 只實作本期已啟用功能的 Android adapters；iOS／未啟用平台能力只保留契約，不建假 adapter。

**CORE 服務降級**：已接入 provider 必須有 timeout、retry／backoff、失敗狀態與核心隔離。行情使用標示日期的最後快取，備份失敗不阻斷 Ledger；Optional OCR／Calendar 啟用後各自保留本機手動或站內降級路徑。需要可靠外送時沿用 RC-19。**rc1 細化提案**：完整跨 provider health／Circuit Breaker／自動 fallback 平台延後，首版只落實所用 adapters 的錯誤隔離與必要路由；單一 provider 不能宣稱有實際多源容錯。

驗收：離線、供應商失敗、憑證撤銷與錯誤設定不影響已可離線完成的核心；prod 不讀 dev credentials；未簽章／不相容遠端設定不可啟用；換 adapter 不需改 Ledger Domain。

<a id="rc-24"></a>
## RC-24｜Update／Release、GitHub 與 Codex 治理

來源：[FV-097](full-vision-baseline.md#fv-097)、[FV-104](full-vision-baseline.md#fv-104)、[FV-105](full-vision-baseline.md#fv-105)、[FV-106](full-vision-baseline.md#fv-106)、[FV-108](full-vision-baseline.md#fv-108)、[Q040](full-vision-baseline.md#q040)、[Q043](full-vision-baseline.md#q043)。

**CORE 交付規範**：新 repository，main + feature／slice branches；禁止直接 push main。每個 PR／slice 必須有 acceptance criteria、測試結果、Architecture Gate、Migration Gate、Static Analysis、Security Check 與 exact commit SHA。私人 repository 已建立，當前交付為文件；沒有宣告任何程式 gate 已通過。

**後續工作指示**：使用者已要求先建立新的 GitHub 專案，並先完成必要登入／準備。允許以私人 repository 與初始 README 保存專案，再將架構文件走分支／PR；不等待整體 Freeze 才建立 repository，但正式 Architecture Baseline 仍須通過既定 gate。建立與環境狀態見[前置準備](../delivery/development-readiness.md)。

Release artifact 可追溯 commit、版本／build／channel、checksum、minimum version、migration level、rollback marker；App 更新檢查與 GitHub Release 使用一致的版本來源。確認對應平台／channel、artifact 完整性與簽章後才進正式安裝流程；migration 不相容時不能只降級 binary。具體簽章保管、更新交付與失敗復原流程在 ADR 中細化，測試升級與中斷情境。

一般 UI 只顯示目前版本，以及有更新時的最新版本；build、commit SHA、checksum 等留 Diagnostics。首次可用 release 就需有基本可驗證 metadata，不能拿「UI 簡潔」當作省略發版追溯的理由。

Codex 可實作、在批准邊界內重構、補測試、優化與修 bug；不能自行改 Ledger invariant、Domain boundary、schema strategy、Money representation、Sync semantics、Security model、Migration policy。禁止 UI 直接碰 DB、Provider 承載核心業務、外部 SDK 滲入 Domain、hidden feature 用 stub 冒充完成。架構變更先有 ADR 與 review，再進實作。

**EXTENSION-READY／延後**：第二發布平台／更多 channel 的運維、自動發版平台的非必要管理 UI、完整 nightly 效能歷史系統。不能延後核心 PR gate、資料安全與已發布 artifact 的可追溯性。

Freeze 前依序完成 Architecture Consistency、Domain Boundary、Ledger Invariant、Data Model、Security／Privacy、Sync／Backup、Capability／Optional Module、UI IA、Over-engineering、Missing Requirement Review。最後才建立 Architecture Baseline commit，記錄 exact SHA；源資料讀齊或 Markdown 檢查通過都不是 Architecture Freeze。

<a id="rc-25"></a>
## RC-25｜外部入口、匯出風險與永久清除

來源：[FV-099](full-vision-baseline.md#fv-099)、[FV-100](full-vision-baseline.md#fv-100)、[FV-101](full-vision-baseline.md#fv-101)、[FV-102](full-vision-baseline.md#fv-102)、[FV-074](full-vision-baseline.md#fv-074)、[Q123](full-vision-baseline.md#q123)。

**CORE**：低風險操作可直接執行並提供安全 Undo；Medium 確認一次；High 顯示 impact 與二次確認；Critical 使用 PIN／Biometrics。已 Posted 的財務行為依情境走 revision／reversal，不能用 Undo 抹掉歷史。套用在本期的 restore、匯入確認／撤銷、帳戶關閉、匯出與刪除；完整可配置 Policy Engine 為 EXTENSION-READY。

匯出依敏感度分級：報表圖片、部分 CSV、完整交易資料、Canonical Archive／全量備份分開處理。CORE 對已實作的 CSV／JSON／backup 明示範圍、加密狀態與風險，高風險額外確認，極高風險再驗證 PIN／Biometrics。尚未實作的圖像或 Canonical exporter 不因這份分類而提前開發；依目的地／附件／投資資料動態評分的 Export Policy Engine 延後。

**CORE 接口**：已實作通知等入口共用 Action Link 的目標識別與狀態驗證；link 不放敏感資料。任何會修改 Ledger 的 action 先進 App，檢查狀態、必要時解鎖並確認，不允許外部 URL 靜默 posting。**rc1 細化提案／OPTIONAL**：完整 open／review／resolve／confirm-flow routing、Android Shortcut／Home Widget 隨對應能力與 slice 開放；掃描收據、Inbox 或 Calendar 還未實作時，不建立失效入口。所有 Widget／Shortcut 沿用 Privacy Presentation。

**rc1 細化提案／OPTIONAL**：整個 Workspace 的永久清除需先完成 impact preview、PIN／biometric、backup prompt、cooling-off、取消與真正 purge 的一致流程。真正執行時處理正式資料、revision、tombstone、projection、search index、無引用 blob、雲端副本與密鑰材料，最後做 integrity check；來源採 Crypto-erasure 方向，不宣稱可靠覆寫 flash 實體區塊。共享 blob 或密鑰仍被其他資料需要時不能直接移除。離線無法清除雲端副本時須有明確 pending／完成狀態，不誤稱全部清除。

首版保留一般 soft delete；沒有完整 purge 實作時不提供「全部永久清除」的假入口。上述 OPTIONAL 項目原本在廣域 V1 願景中，這是 rc1 的分期提案，須在最終 scope review 一併確認，原目標仍保存在 Full Vision。

驗收：外部入口不能繞過解鎖／Domain validation；通知／Widget 不泄漏被遮罩資料；匯出風險提示與實際內容一致；安全 Undo 不丟失歷史。永久清除的失敗、取消與密鑰隔離測試在該能力上線前完成。


## Full Vision 主題來源索引

以下保留全部 108 個 FV 節點的 rc1 對應；其中 104 節為完整 v0.9，另 4 節為 review 補錄。與逐題登錄是不同索引，不用章節數代替題數。

- [RC-01](#rc-01)：[FV-001](full-vision-baseline.md#fv-001)、[FV-002](full-vision-baseline.md#fv-002)、[FV-003](full-vision-baseline.md#fv-003)、[FV-078](full-vision-baseline.md#fv-078)、[FV-084](full-vision-baseline.md#fv-084)、[FV-107](full-vision-baseline.md#fv-107)。
- [RC-02](#rc-02)：[FV-004](full-vision-baseline.md#fv-004)、[FV-005](full-vision-baseline.md#fv-005)、[FV-006](full-vision-baseline.md#fv-006)、[FV-078](full-vision-baseline.md#fv-078)、[FV-085](full-vision-baseline.md#fv-085)、[FV-086](full-vision-baseline.md#fv-086)、[FV-087](full-vision-baseline.md#fv-087)、[FV-088](full-vision-baseline.md#fv-088)、[FV-089](full-vision-baseline.md#fv-089)、[FV-090](full-vision-baseline.md#fv-090)。
- [RC-03](#rc-03)：[FV-007](full-vision-baseline.md#fv-007)、[FV-008](full-vision-baseline.md#fv-008)、[FV-013](full-vision-baseline.md#fv-013)、[FV-014](full-vision-baseline.md#fv-014)、[FV-016](full-vision-baseline.md#fv-016)、[FV-047](full-vision-baseline.md#fv-047)。
- [RC-04](#rc-04)：[FV-009](full-vision-baseline.md#fv-009)、[FV-019](full-vision-baseline.md#fv-019)、[FV-020](full-vision-baseline.md#fv-020)、[FV-021](full-vision-baseline.md#fv-021)。
- [RC-05](#rc-05)：[FV-010](full-vision-baseline.md#fv-010)、[FV-011](full-vision-baseline.md#fv-011)、[FV-012](full-vision-baseline.md#fv-012)。
- [RC-06](#rc-06)：[FV-015](full-vision-baseline.md#fv-015)、[FV-061](full-vision-baseline.md#fv-061)、[FV-062](full-vision-baseline.md#fv-062)、[FV-063](full-vision-baseline.md#fv-063)、[FV-068](full-vision-baseline.md#fv-068)、[FV-069](full-vision-baseline.md#fv-069)、[FV-071](full-vision-baseline.md#fv-071)、[FV-078](full-vision-baseline.md#fv-078)、[FV-094](full-vision-baseline.md#fv-094)。
- [RC-07](#rc-07)：[FV-017](full-vision-baseline.md#fv-017)、[FV-018](full-vision-baseline.md#fv-018)。
- [RC-08](#rc-08)：[FV-022](full-vision-baseline.md#fv-022)、[FV-023](full-vision-baseline.md#fv-023)、[FV-024](full-vision-baseline.md#fv-024)、[FV-025](full-vision-baseline.md#fv-025)、[FV-026](full-vision-baseline.md#fv-026)。
- [RC-09](#rc-09)：[FV-027](full-vision-baseline.md#fv-027)、[FV-028](full-vision-baseline.md#fv-028)。
- [RC-10](#rc-10)：[FV-029](full-vision-baseline.md#fv-029)、[FV-048](full-vision-baseline.md#fv-048)。
- [RC-11](#rc-11)：[FV-030](full-vision-baseline.md#fv-030)、[FV-031](full-vision-baseline.md#fv-031)、[FV-032](full-vision-baseline.md#fv-032)、[FV-033](full-vision-baseline.md#fv-033)、[FV-072](full-vision-baseline.md#fv-072)。
- [RC-12](#rc-12)：[FV-034](full-vision-baseline.md#fv-034)。
- [RC-13](#rc-13)：[FV-049](full-vision-baseline.md#fv-049)、[FV-050](full-vision-baseline.md#fv-050)、[FV-051](full-vision-baseline.md#fv-051)、[FV-091](full-vision-baseline.md#fv-091)、[FV-103](full-vision-baseline.md#fv-103)。
- [RC-14](#rc-14)：[FV-052](full-vision-baseline.md#fv-052)、[FV-053](full-vision-baseline.md#fv-053)、[FV-054](full-vision-baseline.md#fv-054)、[FV-055](full-vision-baseline.md#fv-055)。
- [RC-15](#rc-15)：[FV-056](full-vision-baseline.md#fv-056)、[FV-057](full-vision-baseline.md#fv-057)、[FV-058](full-vision-baseline.md#fv-058)、[FV-073](full-vision-baseline.md#fv-073)、[FV-074](full-vision-baseline.md#fv-074)、[FV-076](full-vision-baseline.md#fv-076)、[FV-079](full-vision-baseline.md#fv-079)、[FV-096](full-vision-baseline.md#fv-096)。
- [RC-16](#rc-16)：[FV-035](full-vision-baseline.md#fv-035)、[FV-036](full-vision-baseline.md#fv-036)、[FV-037](full-vision-baseline.md#fv-037)、[FV-038](full-vision-baseline.md#fv-038)、[FV-039](full-vision-baseline.md#fv-039)、[FV-040](full-vision-baseline.md#fv-040)、[FV-041](full-vision-baseline.md#fv-041)、[FV-042](full-vision-baseline.md#fv-042)、[FV-043](full-vision-baseline.md#fv-043)、[FV-044](full-vision-baseline.md#fv-044)、[FV-045](full-vision-baseline.md#fv-045)、[FV-046](full-vision-baseline.md#fv-046)。
- [RC-17](#rc-17)：[FV-059](full-vision-baseline.md#fv-059)。
- [RC-18](#rc-18)：[FV-060](full-vision-baseline.md#fv-060)。
- [RC-19](#rc-19)：[FV-064](full-vision-baseline.md#fv-064)、[FV-065](full-vision-baseline.md#fv-065)、[FV-066](full-vision-baseline.md#fv-066)、[FV-067](full-vision-baseline.md#fv-067)。
- [RC-20](#rc-20)：[FV-070](full-vision-baseline.md#fv-070)、[FV-075](full-vision-baseline.md#fv-075)、[FV-081](full-vision-baseline.md#fv-081)。
- [RC-21](#rc-21)：[FV-077](full-vision-baseline.md#fv-077)、[FV-092](full-vision-baseline.md#fv-092)、[FV-093](full-vision-baseline.md#fv-093)、[FV-095](full-vision-baseline.md#fv-095)。
- [RC-22](#rc-22)：[FV-077](full-vision-baseline.md#fv-077)、[FV-078](full-vision-baseline.md#fv-078)、[FV-106](full-vision-baseline.md#fv-106)、[FV-108](full-vision-baseline.md#fv-108)。
- [RC-23](#rc-23)：[FV-080](full-vision-baseline.md#fv-080)、[FV-082](full-vision-baseline.md#fv-082)、[FV-083](full-vision-baseline.md#fv-083)、[FV-098](full-vision-baseline.md#fv-098)。
- [RC-24](#rc-24)：[FV-097](full-vision-baseline.md#fv-097)、[FV-104](full-vision-baseline.md#fv-104)、[FV-105](full-vision-baseline.md#fv-105)。
- [RC-25](#rc-25)：[FV-074](full-vision-baseline.md#fv-074)、[FV-099](full-vision-baseline.md#fv-099)、[FV-100](full-vision-baseline.md#fv-100)、[FV-101](full-vision-baseline.md#fv-101)、[FV-102](full-vision-baseline.md#fv-102)。

<a id="decision-scope-index"></a>
## 170 題當期追溯索引

每一行連到 Full Vision 的原題、使用者原答、選項與定案說明，再連到本文件的實作契約。

- **CORE**：本期完整實作與驗收。
- **CORE 子集＋延後進階**：基本行為本期完成；進階能力保留 EXTENSION-READY 契約，後續 OPTIONAL 實作。
- **EXTENSION-READY／OPTIONAL**：本期交付接入契約；功能本身延後。

上述分期不表示任何程式已完成。最新 review 未明定的進一步 scope 切分，在各 RC 節標為「rc1 細化提案」，由最終 review 確認。

### Q001～Q010

- [Q001 完整個人財務產品定位](full-vision-baseline.md#q001)：CORE 子集＋延後進階；[RC-01](#rc-01)。
- [Q002 Local-first 與雲端備份](full-vision-baseline.md#q002)：CORE 子集＋延後進階；[RC-14](#rc-14)、[RC-20](#rc-20)。
- [Q003 高標準 Ledger](full-vision-baseline.md#q003)：CORE；[RC-03](#rc-03)。
- [Q004 帳戶類型與擴充](full-vision-baseline.md#q004)：CORE 子集＋延後進階；[RC-05](#rc-05)。
- [Q005 雙層分類](full-vision-baseline.md#q005)：CORE；[RC-05](#rc-05)。
- [Q006 拆分類與未來多帳戶付款](full-vision-baseline.md#q006)：CORE 子集＋延後進階；[RC-03](#rc-03)。
- [Q007 信用卡與分期 Domain](full-vision-baseline.md#q007)：CORE 子集＋延後進階；[RC-07](#rc-07)。
- [Q008 完整多幣別 Ledger](full-vision-baseline.md#q008)：CORE；[RC-04](#rc-04)。
- [Q009 投資完整願景與漸進 UI](full-vision-baseline.md#q009)：CORE 子集＋延後進階；[RC-08](#rc-08)。
- [Q010 Budget Rule Engine](full-vision-baseline.md#q010)：CORE 子集＋延後進階；[RC-09](#rc-09)。

### Q011～Q020

- [Q011 Recurring／Automation](full-vision-baseline.md#q011)：CORE 子集＋延後進階；[RC-09](#rc-09)。
- [Q012 分析引擎與一般報表](full-vision-baseline.md#q012)：CORE 子集＋延後進階；[RC-13](#rc-13)。
- [Q013 交易資訊與正式 Merchant](full-vision-baseline.md#q013)：CORE 子集＋延後進階；[RC-03](#rc-03)、[RC-05](#rc-05)、[RC-11](#rc-11)。
- [Q014 強化且保持平面的 Tag](full-vision-baseline.md#q014)：CORE；[RC-05](#rc-05)。
- [Q015 Revision 與 soft delete](full-vision-baseline.md#q015)：CORE；[RC-03](#rc-03)。
- [Q016 OCR 輔助記帳](full-vision-baseline.md#q016)：EXTENSION-READY／OPTIONAL；[RC-11](#rc-11)。
- [Q017 進階搜尋與自然語言預留](full-vision-baseline.md#q017)：CORE 子集＋延後進階；[RC-10](#rc-10)。
- [Q018 版本化雲端備份與未來同步準備](full-vision-baseline.md#q018)：CORE 子集＋延後進階；[RC-14](#rc-14)、[RC-20](#rc-20)。
- [Q019 登入選配](full-vision-baseline.md#q019)：CORE；[RC-14](#rc-14)、[RC-15](#rc-15)。
- [Q020 App 安全與本機加密](full-vision-baseline.md#q020)：CORE；[RC-15](#rc-15)。

### Q021～Q030

- [Q021 資料匯入／移轉 Framework](full-vision-baseline.md#q021)：CORE 子集＋延後進階；[RC-18](#rc-18)。
- [Q022 介於極簡與完整之間的首頁](full-vision-baseline.md#q022)：CORE；[RC-02](#rc-02)。
- [Q023 五個底部導航位置](full-vision-baseline.md#q023)：CORE；[RC-02](#rc-02)。
- [Q024 快速輸入與情境式特殊交易](full-vision-baseline.md#q024)：CORE；[RC-02](#rc-02)。
- [Q025 金額欄內建計算器](full-vision-baseline.md#q025)：CORE；[RC-02](#rc-02)、[RC-04](#rc-04)。
- [Q026 完整財務時間、簡潔 UI](full-vision-baseline.md#q026)：CORE；[RC-06](#rc-06)。
- [Q027 規則式商家記憶與智慧預測預留](full-vision-baseline.md#q027)：EXTENSION-READY／OPTIONAL；[RC-05](#rc-05)。
- [Q028 完整 Reconciliation](full-vision-baseline.md#q028)：EXTENSION-READY／OPTIONAL；[RC-12](#rc-12)。
- [Q029 規則提醒與 Google Calendar channel](full-vision-baseline.md#q029)：CORE 子集＋延後進階；[RC-17](#rc-17)。
- [Q030 受控雙向 Google Calendar](full-vision-baseline.md#q030)：EXTENSION-READY／OPTIONAL；[RC-17](#rc-17)。

### Q031～Q040

- [Q031 供應商可替換的混合後端](full-vision-baseline.md#q031)：CORE；[RC-23](#rc-23)。
- [Q032 Drift + SQLite](full-vision-baseline.md#q032)：CORE；[RC-06](#rc-06)。
- [Q033 Thin Riverpod、Thick Domain](full-vision-baseline.md#q033)：CORE；[RC-06](#rc-06)。
- [Q034 Modular Monolith](full-vision-baseline.md#q034)：CORE；[RC-06](#rc-06)。
- [Q035 Application API 與 Domain Event](full-vision-baseline.md#q035)：CORE；[RC-19](#rc-19)。
- [Q036 重要事件持久化、不做 Full Event Sourcing](full-vision-baseline.md#q036)：CORE；[RC-19](#rc-19)。
- [Q037 Revision 與衝突偵測的同步](full-vision-baseline.md#q037)：EXTENSION-READY／OPTIONAL；[RC-20](#rc-20)。
- [Q038 低風險 merge、財務衝突人工確認](full-vision-baseline.md#q038)：EXTENSION-READY／OPTIONAL；[RC-20](#rc-20)。
- [Q039 核心財務高強度測試](full-vision-baseline.md#q039)：CORE；[RC-21](#rc-21)。
- [Q040 嚴格 PR Gate 與架構治理](full-vision-baseline.md#q040)：CORE；[RC-24](#rc-24)。

### Q041～Q050

- [Q041 完整 Data Evolution](full-vision-baseline.md#q041)：CORE；[RC-06](#rc-06)。
- [Q042 本機 Diagnostics 與 Observability 預留](full-vision-baseline.md#q042)：CORE 子集＋延後進階；[RC-15](#rc-15)、[RC-21](#rc-21)。
- [Q043 完整 Update Channel、極簡版本顯示](full-vision-baseline.md#q043)：CORE；[RC-24](#rc-24)。
- [Q044 Android 優先、平台接口預留 iOS](full-vision-baseline.md#q044)：CORE 子集＋延後進階；[RC-23](#rc-23)。
- [Q045 Material 3 與自建 Design System](full-vision-baseline.md#q045)：CORE；[RC-02](#rc-02)。
- [Q046 淺色優先、深色模式預留](full-vision-baseline.md#q046)：CORE 子集＋延後進階；[RC-02](#rc-02)。
- [Q047 高標準無障礙](full-vision-baseline.md#q047)：CORE；[RC-02](#rc-02)、[RC-21](#rc-21)。
- [Q048 繁中優先與完整 i18n](full-vision-baseline.md#q048)：CORE；[RC-02](#rc-02)、[RC-06](#rc-06)。
- [Q049 整數 minor unit 與高精度 Decimal](full-vision-baseline.md#q049)：CORE；[RC-04](#rc-04)。
- [Q050 按 Domain 定義 rounding](full-vision-baseline.md#q050)：CORE；[RC-04](#rc-04)。

### Q051～Q060

- [Q051 手動、比例與百分比分攤](full-vision-baseline.md#q051)：CORE 子集＋延後進階；[RC-03](#rc-03)。
- [Q052 Ledger 唯一真相與可重建投影](full-vision-baseline.md#q052)：CORE；[RC-13](#rc-13)。
- [Q053 Archive、Merge／Replace 與引用保全](full-vision-baseline.md#q053)：CORE；[RC-05](#rc-05)。
- [Q054 Account Lifecycle 與 Opening Balance](full-vision-baseline.md#q054)：CORE；[RC-05](#rc-05)。
- [Q055 信用卡手動／帳單匯入及擷取來源](full-vision-baseline.md#q055)：CORE 子集＋延後進階；[RC-07](#rc-07)、[RC-18](#rc-18)。
- [Q056 多 Provider 行情架構](full-vision-baseline.md#q056)：CORE 子集＋延後進階；[RC-08](#rc-08)。
- [Q057 Market Data Pipeline](full-vision-baseline.md#q057)：CORE 子集＋延後進階；[RC-08](#rc-08)。
- [Q058 Tax Lot Engine](full-vision-baseline.md#q058)：CORE 子集＋延後進階；[RC-08](#rc-08)。
- [Q059 Benchmark 與 Attribution 願景](full-vision-baseline.md#q059)：CORE 子集＋延後進階；[RC-08](#rc-08)。
- [Q060 通用投資商品模型](full-vision-baseline.md#q060)：CORE 子集＋延後進階；[RC-08](#rc-08)。

### Q061～Q070

- [Q061 金融機構與自訂帳戶群組](full-vision-baseline.md#q061)：EXTENSION-READY／OPTIONAL；[RC-05](#rc-05)、[RC-16](#rc-16)。
- [Q062 Canonical Entity、Alias 與 Resolution](full-vision-baseline.md#q062)：CORE 子集＋延後進階；[RC-05](#rc-05)、[RC-11](#rc-11)。
- [Q063 統一 Matching Engine](full-vision-baseline.md#q063)：CORE 子集＋延後進階；[RC-11](#rc-11)、[RC-18](#rc-18)。
- [Q064 完整交易生命週期](full-vision-baseline.md#q064)：CORE 子集＋延後進階；[RC-03](#rc-03)、[RC-07](#rc-07)。
- [Q065 多種金融日期語意](full-vision-baseline.md#q065)：CORE；[RC-06](#rc-06)。
- [Q066 Content-addressed 附件儲存](full-vision-baseline.md#q066)：EXTENSION-READY／OPTIONAL；[RC-11](#rc-11)。
- [Q067 本機 OCR 與主動雲端 fallback](full-vision-baseline.md#q067)：EXTENSION-READY／OPTIONAL；[RC-11](#rc-11)。
- [Q068 結構化地點與智慧地點預留](full-vision-baseline.md#q068)：EXTENSION-READY／OPTIONAL；[RC-05](#rc-05)、[RC-11](#rc-11)。
- [Q069 Merchant、Branch 與 Place Resolution](full-vision-baseline.md#q069)：EXTENSION-READY／OPTIONAL；[RC-05](#rc-05)、[RC-11](#rc-11)。
- [Q070 Receipt／Invoice 與台灣發票能力](full-vision-baseline.md#q070)：EXTENSION-READY／OPTIONAL；[RC-11](#rc-11)。

### Q071～Q080

- [Q071 QR 掃描與 Matching](full-vision-baseline.md#q071)：EXTENSION-READY／OPTIONAL；[RC-11](#rc-11)。
- [Q072 Financial Inbox 與 Staging Workflow](full-vision-baseline.md#q072)：CORE 子集＋延後進階；[RC-11](#rc-11)、[RC-18](#rc-18)。
- [Q073 Inbox 批次處理與規則自動化預留](full-vision-baseline.md#q073)：EXTENSION-READY／OPTIONAL；[RC-11](#rc-11)。
- [Q074 Rule Engine 與完整 Automation 預留](full-vision-baseline.md#q074)：CORE 子集＋延後進階；[RC-10](#rc-10)。
- [Q075 Priority 與 Specificity 衝突規則](full-vision-baseline.md#q075)：EXTENSION-READY／OPTIONAL；[RC-10](#rc-10)。
- [Q076 共用 Predicate／Expression DSL](full-vision-baseline.md#q076)：CORE 子集＋延後進階；[RC-10](#rc-10)。
- [Q077 可序列化 AST 與版本化 schema](full-vision-baseline.md#q077)：CORE 子集＋延後進階；[RC-10](#rc-10)。
- [Q078 Storage Lifecycle Engine](full-vision-baseline.md#q078)：CORE 子集＋延後進階；[RC-15](#rc-15)。
- [Q079 可驗證 Restore](full-vision-baseline.md#q079)：CORE；[RC-14](#rc-14)。
- [Q080 分層 Health Check](full-vision-baseline.md#q080)：CORE；[RC-15](#rc-15)。

### Q081～Q090

- [Q081 Recovery Center](full-vision-baseline.md#q081)：CORE 子集＋延後進階；[RC-15](#rc-15)。
- [Q082 Durable Job Engine](full-vision-baseline.md#q082)：CORE 子集＋延後進階；[RC-19](#rc-19)。
- [Q083 Dead Letter／Recovery Queue](full-vision-baseline.md#q083)：EXTENSION-READY／OPTIONAL；[RC-19](#rc-19)。
- [Q084 分級 Secrets](full-vision-baseline.md#q084)：CORE；[RC-23](#rc-23)。
- [Q085 Build Flavor 與 Runtime Config](full-vision-baseline.md#q085)：CORE 子集＋延後進階；[RC-23](#rc-23)。
- [Q086 Feature Capability System](full-vision-baseline.md#q086)：CORE；[RC-01](#rc-01)。
- [Q087 Privacy Capability Layer](full-vision-baseline.md#q087)：CORE；[RC-15](#rc-15)。
- [Q088 Graceful Degradation 與 Circuit Breaker](full-vision-baseline.md#q088)：CORE 子集＋延後進階；[RC-23](#rc-23)。
- [Q089 長期資料量目標與壓力測試](full-vision-baseline.md#q089)：CORE；[RC-21](#rc-21)。
- [Q090 Performance Regression System](full-vision-baseline.md#q090)：CORE 子集＋延後進階；[RC-21](#rc-21)。

### Q091～Q100

- [Q091 Opt-in Crash Reporting](full-vision-baseline.md#q091)：EXTENSION-READY／OPTIONAL；[RC-15](#rc-15)、[RC-21](#rc-21)。
- [Q092 Local Analytics Warehouse 與分析匯出](full-vision-baseline.md#q092)：CORE 子集＋延後進階；[RC-13](#rc-13)、[RC-18](#rc-18)。
- [Q093 Incremental Projection Engine](full-vision-baseline.md#q093)：CORE 子集＋延後進階；[RC-13](#rc-13)。
- [Q094 Search Projection Engine](full-vision-baseline.md#q094)：EXTENSION-READY／OPTIONAL；[RC-10](#rc-10)。
- [Q095 Privacy Presentation Layer](full-vision-baseline.md#q095)：CORE；[RC-15](#rc-15)。
- [Q096 分級 Screen Security](full-vision-baseline.md#q096)：CORE 子集＋延後進階；[RC-15](#rc-15)。
- [Q097 通知敏感等級](full-vision-baseline.md#q097)：CORE 子集＋延後進階；[RC-15](#rc-15)、[RC-17](#rc-17)。
- [Q098 Android Shortcut 與 Home Widget](full-vision-baseline.md#q098)：EXTENSION-READY／OPTIONAL；[RC-25](#rc-25)。
- [Q099 Action Link System](full-vision-baseline.md#q099)：CORE 子集＋延後進階；[RC-25](#rc-25)。
- [Q100 安全 Undo 與財務 Revision／Reversal](full-vision-baseline.md#q100)：CORE；[RC-03](#rc-03)、[RC-25](#rc-25)。

### Q101～Q110

- [Q101 風險分級確認與 Policy 預留](full-vision-baseline.md#q101)：CORE 子集＋延後進階；[RC-25](#rc-25)。
- [Q102 帳本設定與裝置設定分離](full-vision-baseline.md#q102)：CORE 子集＋延後進階；[RC-06](#rc-06)、[RC-20](#rc-20)。
- [Q103 多 Workspace 地基、單帳本 UI](full-vision-baseline.md#q103)：CORE 子集＋延後進階；[RC-20](#rc-20)。
- [Q104 受控跨 Workspace Transfer](full-vision-baseline.md#q104)：EXTENSION-READY／OPTIONAL；[RC-20](#rc-20)。
- [Q105 Membership 與家庭權限擴展](full-vision-baseline.md#q105)：EXTENSION-READY／OPTIONAL；[RC-20](#rc-20)。
- [Q106 Audit Principal](full-vision-baseline.md#q106)：CORE；[RC-06](#rc-06)。
- [Q107 本機 ACID 與外部副作用](full-vision-baseline.md#q107)：CORE 子集＋延後進階；[RC-19](#rc-19)。
- [Q108 Transactional Inbox／Outbox Framework](full-vision-baseline.md#q108)：CORE 子集＋延後進階；[RC-19](#rc-19)。
- [Q109 At-least-once 與冪等 consumer](full-vision-baseline.md#q109)：CORE；[RC-19](#rc-19)。
- [Q110 UUID v7](full-vision-baseline.md#q110)：CORE；[RC-06](#rc-06)。

### Q111～Q120

- [Q111 Internal Integer ID 與 Public UUID](full-vision-baseline.md#q111)：CORE；[RC-06](#rc-06)。
- [Q112 核心 lifecycle 與按需有效期間](full-vision-baseline.md#q112)：CORE；[RC-06](#rc-06)。
- [Q113 Query／Index Governance](full-vision-baseline.md#q113)：CORE 子集＋延後進階；[RC-21](#rc-21)。
- [Q114 Transactional 與重大 Shadow Migration](full-vision-baseline.md#q114)：CORE；[RC-06](#rc-06)。
- [Q115 Backup Package 與 Canonical Export](full-vision-baseline.md#q115)：CORE 子集＋延後進階；[RC-14](#rc-14)。
- [Q116 人類可讀與機器可讀 Canonical Archive](full-vision-baseline.md#q116)：EXTENSION-READY／OPTIONAL；[RC-14](#rc-14)。
- [Q117 Canonical Data 與加密容器解耦](full-vision-baseline.md#q117)：CORE 子集＋延後進階；[RC-14](#rc-14)。
- [Q118 Key Envelope](full-vision-baseline.md#q118)：EXTENSION-READY／OPTIONAL；[RC-14](#rc-14)。
- [Q119 Recovery Key 輪替與 Health Check](full-vision-baseline.md#q119)：EXTENSION-READY／OPTIONAL；[RC-14](#rc-14)。
- [Q120 Recovery Key 文字與 QR](full-vision-baseline.md#q120)：EXTENSION-READY／OPTIONAL；[RC-14](#rc-14)。

### Q121～Q130

- [Q121 刪除保護與冷卻期](full-vision-baseline.md#q121)：CORE 子集＋延後進階；[RC-15](#rc-15)、[RC-25](#rc-25)。
- [Q122 完整 Purge 與 Crypto-erasure](full-vision-baseline.md#q122)：EXTENSION-READY／OPTIONAL；[RC-15](#rc-15)、[RC-25](#rc-25)。
- [Q123 匯出敏感度分級](full-vision-baseline.md#q123)：CORE 子集＋延後進階；[RC-18](#rc-18)、[RC-25](#rc-25)。
- [Q124 Consistency Tier](full-vision-baseline.md#q124)：CORE 子集＋延後進階；[RC-13](#rc-13)。
- [Q125 FX Rate Engine](full-vision-baseline.md#q125)：CORE 子集＋延後進階；[RC-04](#rc-04)。
- [Q126 Workspace Base Currency 與 Display Currency](full-vision-baseline.md#q126)：CORE；[RC-04](#rc-04)。
- [Q127 FX Revaluation](full-vision-baseline.md#q127)：EXTENSION-READY／OPTIONAL；[RC-04](#rc-04)。
- [Q128 Card FX Settlement Model](full-vision-baseline.md#q128)：CORE 子集＋延後進階；[RC-07](#rc-07)。
- [Q129 Credit Limit Engine](full-vision-baseline.md#q129)：EXTENSION-READY／OPTIONAL；[RC-07](#rc-07)。
- [Q130 Financing Engine](full-vision-baseline.md#q130)：CORE 子集＋延後進階；[RC-07](#rc-07)。

### Q131～Q140

- [Q131 Liability／Loan Engine](full-vision-baseline.md#q131)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q132 淨資產限金融資產與金融負債](full-vision-baseline.md#q132)：CORE；[RC-13](#rc-13)、[RC-16](#rc-16)。
- [Q133 財務目標與 Goal Planning 預留](full-vision-baseline.md#q133)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q134 Cash-flow Forecast Engine](full-vision-baseline.md#q134)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q135 Scenario Engine](full-vision-baseline.md#q135)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q136 Scenario 轉計畫與 Plan Execution 預留](full-vision-baseline.md#q136)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q137 Commitment Model](full-vision-baseline.md#q137)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q138 Subscription Management](full-vision-baseline.md#q138)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q139 Billing／Payable Engine](full-vision-baseline.md#q139)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q140 Receivable／Personal Lending](full-vision-baseline.md#q140)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。

### Q141～Q150

- [Q141 Person／Counterparty 與 Contact Resolution](full-vision-baseline.md#q141)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q142 Shared Expense Engine](full-vision-baseline.md#q142)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q143 Expense Claim Engine](full-vision-baseline.md#q143)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q144 Organization 與 Relationship Graph](full-vision-baseline.md#q144)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q145 基本保單與 Insurance Domain 預留](full-vision-baseline.md#q145)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q146 Income Source 與 Payroll 預留](full-vision-baseline.md#q146)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q147 結構化 Tax Component、預留 Tax Engine](full-vision-baseline.md#q147)：CORE 子集＋延後進階；[RC-03](#rc-03)、[RC-16](#rc-16)。
- [Q148 統一 Charge／Adjustment Component](full-vision-baseline.md#q148)：CORE 子集＋延後進階；[RC-03](#rc-03)。
- [Q149 Versioned Tax Rule Provider](full-vision-baseline.md#q149)：EXTENSION-READY／OPTIONAL；[RC-16](#rc-16)。
- [Q150 折扣、Cashback 與 Reward 簡化](full-vision-baseline.md#q150)：CORE；[RC-03](#rc-03)。

### Q151～Q160

- [Q151 純文字備註與獨立 Activity Timeline](full-vision-baseline.md#q151)：CORE；[RC-03](#rc-03)。
- [Q152 可跳過的引導式 Onboarding](full-vision-baseline.md#q152)：CORE；[RC-02](#rc-02)。
- [Q153 精簡完整的預設分類](full-vision-baseline.md#q153)：CORE；[RC-02](#rc-02)、[RC-05](#rc-05)。
- [Q154 引導型 Empty State](full-vision-baseline.md#q154)：CORE；[RC-02](#rc-02)。
- [Q155 完整表單狀態與不打擾式驗證](full-vision-baseline.md#q155)：CORE；[RC-02](#rc-02)。
- [Q156 儲存後保留來源 Context](full-vision-baseline.md#q156)：CORE；[RC-02](#rc-02)。
- [Q157 安全複製交易與模板預留](full-vision-baseline.md#q157)：CORE 子集＋延後進階；[RC-02](#rc-02)。
- [Q158 日期分組與每日收支摘要](full-vision-baseline.md#q158)：CORE；[RC-02](#rc-02)。
- [Q159 有限 Swipe Action](full-vision-baseline.md#q159)：CORE；[RC-02](#rc-02)。
- [Q160 簡潔交易明細與可展開資金流](full-vision-baseline.md#q160)：CORE；[RC-02](#rc-02)。

### Q161～Q170

- [Q161 Bottom Quick Sheet](full-vision-baseline.md#q161)：CORE；[RC-02](#rc-02)。
- [Q162 互動圖表與 Drill-down](full-vision-baseline.md#q162)：CORE；[RC-13](#rc-13)。
- [Q163 輕量動畫與 Reduce Motion](full-vision-baseline.md#q163)：CORE；[RC-02](#rc-02)。
- [Q164 自動刷新與下拉重新整理](full-vision-baseline.md#q164)：CORE；[RC-02](#rc-02)、[RC-13](#rc-13)。
- [Q165 首頁最近五筆交易](full-vision-baseline.md#q165)：CORE；[RC-02](#rc-02)。
- [Q166 首頁整體預算與一至兩項提醒](full-vision-baseline.md#q166)：CORE；[RC-02](#rc-02)。
- [Q167 首頁一行投資摘要](full-vision-baseline.md#q167)：CORE；[RC-02](#rc-02)。
- [Q168 信用卡待繳總額與最近到期卡](full-vision-baseline.md#q168)：CORE；[RC-02](#rc-02)。
- [Q169 首頁最近三筆重要事項](full-vision-baseline.md#q169)：CORE；[RC-02](#rc-02)。
- [Q170 首頁區塊可隱藏、不自由重排](full-vision-baseline.md#q170)：CORE；[RC-02](#rc-02)。
