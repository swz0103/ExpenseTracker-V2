# ExpenseTracker V2 — Full Vision Baseline

日期：2026-09-26  
版本：Full Vision Baseline v1.0／完整決策保存版  
狀態：170／170 原題與使用者答案已核對；待最終架構審查，尚未 Freeze  
配套文件：[Architecture Baseline v1.0-rc1](architecture-baseline-v1.0-rc1.md)

整合閱讀：架構提案與已選方向 · 實作計畫。三組產品取捨已選 1A／2A／3A，見 D-003；工程細節仍須規格與驗證，未開始開發。

> **縮減的是當前 implementation scope，不是產品願景。**
>
> 本文件保存原對話的 170 項產品／架構決策、完整 v0.9 的 104 節內容，以及最新減重 review。延後能力仍保留目標與接入方向；第一階段工作範圍以 rc1 為準。

## 閱讀與治理規則

Full Vision 回答「長期要支援什麼、哪些決策不能遺忘」；[rc1](architecture-baseline-v1.0-rc1.md) 回答「這一期做多少、哪些只準備接口」。原文中的 V1、底層先做完整、UI 隱藏等語句保存為歷史決策；最新 review 已將實作時程改為 **Core-first, Extension-ready**，不得直接將歷史廣域 V1 當成本期開工清單。

CORE 必須完整且可驗證；未使用的進階能力可只保留 Interface／Provider contract／資料邊界／migration path。不得用 stub 假裝 implemented，也不得因 UI 隱藏降低品質。只有 verified 且依賴符合條件的能力才能正式啟用。

<a id="framework-first"></a>
### 後續確認：先定框架，再逐項完成功能

2026-09-26，使用者於本次文件整理對話確認：「一個功能一個功能做，但是要先想好整個程式框架，才不會加一個功能會變很複雜或影響很多」。此為原 170 題之後的補充決策，不更動原題編號與歷史內容。

先確定全程式的模組責任、依賴方向、資料擁有者、共用財務規則、跨模組契約，以及 migration／備份相容性；再以一個可使用、可驗證的功能為單位，完成規則、儲存、必要 UI 與測試。未來能力保留接入位置，不要求提前完成全部引擎、資料表或抽象框架。

新增功能的目標是讓變更集中在所屬模組、明確的接入點與必要遷移，並可檢查既有功能是否受影響；不承諾所有擴充都零修改。若需要變更核心財務語意或公開契約，必須先提出 ADR、影響範圍與相容方案。

落實位置：[RC-06 模組接入規則](architecture-baseline-v1.0-rc1.md#module-extension-rules)、[RC-22 框架先行與逐功能交付](architecture-baseline-v1.0-rc1.md#framework-delivery)。此確認不等於其餘 rc1 細化提案全部定案，也不代表 Architecture Freeze 已完成。

<a id="decision-a-plus"></a>
### 架構補充決策 D-001：採用 A＋並優化

2026-09-26，使用者於本次對話明確選擇：「算了不用視窗我直接回，選A+，但要更優化」。後續決策改用文字回覆；未回答的議題維持待決，不自動採用推薦方案。

**已選方向**：每個模組負責自己的規則與資料；跨模組操作使用小而明確的 Application 協調流程，必要的本機財務變動在同一交易一起成功或取消。此決策延續 [Q034](#q034) 的 Modular Monolith 與 [FV-064](#fv-064) 的公開接口，不採通用流程引擎，也不把全部業務規則集中到單一管理層。

**本次授權的優化細化**：限制協調流程的職責、區分權威資料與可重建投影、避免模組巢狀提交、以操作識別處理重試、在提交時重新檢查狀態與版本、可靠保存必要後續工作，並以失敗情境驗證。具體規則、操作範例與取捨見 [RC-06 A＋](architecture-baseline-v1.0-rc1.md#a-plus-coordination)。上述為設計要求，尚未實作或驗證；不表示其餘 ADR 已結案或整體架構已 Freeze。

**保留的取捨**：原 A 容易起步，但缺少職責限制時協調層容易膨脹；A＋需先定義資料主責與契約，換取較集中且可驗證的變更範圍；通用流程引擎雖可管理大量相似流程，目前成本與不確定性較高，維持延後。A＋不保證所有新功能都能零修改核心，新的財務語意仍須評估契約與 migration。

<a id="decision-module-enforcement"></a>
### 架構補充決策 D-002：按業務拆套件，業務內按需要再拆

使用者要求繼續把方向定清楚，再開始開發。本題延續 [Q034](#q034) 與 [D-001](#decision-a-plus)，比較 A「單一 App 內以模組目錄與自動檢查隔離」、B「只先隔離共用基礎與 Ledger Domain 為少量本機套件」、C「所有已實作模組的 Domain 集中到一個業務套件」、D「按業務模組拆本機套件，隨功能實作逐項建立」。完整優缺點與共同約束見 [RC-06 D-002](architecture-baseline-v1.0-rc1.md#module-enforcement-options)。

**狀態：使用者已選定 D，並明確允許業務內部按需要再拆。** 2026-09-26 使用者原答：「可以那就按照業務來拆，甚至業務內有必要也可以再拆」。按業務責任建立本機套件；有明確責任及隔離收益的子能力，可再拆子模組／套件。套件數量不設為主要限制；仍需維持公開契約、無循環依賴、資料主責與 A＋的同一交易提交。具體主模組清單及內部分拆尚待設計，不表示已建立程式或完成驗證。

**決策歷程與歸因更正**：先前 B 是整理者建議，未被採用。使用者指出並未決定「不要過度拆套件」；核對 Q034 後確認，該句是原助手的實作建議，不能當成使用者選定的限制。撤回該前提、補入 D 並討論拆分方式後，才取得上述明確選擇；不能把先前質疑本身當成批准。沿用 Modular Monolith、既定模組資料主責與 A＋；架構方向定清楚前不建立程式骨架。另確認 [Q124](#q124) 的分級一致性方向已定案，沿用至 [RC-13](architecture-baseline-v1.0-rc1.md#rc-13)，不要求使用者重選。

<a id="decision-product-delivery"></a>
### 架構補充決策 D-003：採用 1A／2A／3A，先提出實作安排

2026-09-26 使用者原答：「可以就1A2A3A這樣，然後你先規劃實作安排給我看」。本次為三組選項的明確採用，不只是同意繼續討論。

- **1A**：日常首頁、消費報表與消費預算以消費為主；分期購買在購買月份記總消費，每期應繳與實際付款分開，繳款不重複列消費。退款在退款期列減項並追溯原消費，另有標示的歷史淨消費分析不覆寫原紀錄。
- **2A**：首個可用版本交付備份密碼與文字救援金鑰，包含最小 Key Envelope、另行保存引導與兩條解鎖路徑的乾淨環境還原驗證。這是對最新 review 延後範圍的明確調整；QR、完整輪替與定期 health check 仍依後續能力交付。
- **3A**：日常記帳先交付可用版本，再補 Budget／Recurring／提醒與信用卡／基本分期，最後完成股票／ETF 核心。各批均有必要安全、migration 與完整備份還原；首批不等於全部 rc1 CORE 完成。

對應：架構提案三組比較、[RC-02](architecture-baseline-v1.0-rc1.md#rc-02)、[RC-07](architecture-baseline-v1.0-rc1.md#rc-07)、[RC-09](architecture-baseline-v1.0-rc1.md#rc-09)、[RC-14](architecture-baseline-v1.0-rc1.md#rc-14)、[RC-22](architecture-baseline-v1.0-rc1.md#rc-22)。

使用者本輪要求先檢視實作計畫；選項採用不等於已實作、技術驗證通過、Architecture Freeze 或授權立即建立／發布程式。原始 170 題及先前 A＋、業務套件拆分方向不變。

<a id="development-start"></a>
### 後續工作指示：先建立 GitHub 專案與完成必要準備

使用者在採用 1A／2A／3A 並檢視實作安排後，明確要求開始工作、直接建立新的 GitHub 專案，並先讓其完成必要準備。此指示更新 D-003 當時「先只看計畫」的工作狀態；repository 可在 Freeze 前先保存文件，初始文件 commit 不代表 Architecture Freeze。

功能實作仍從規格、代表案例及必要技術驗證開始；需要使用者完成的登入／設定應先集中提出。當下準備與建立狀態見開發前置準備。此指示不改變既有財務規則、套件邊界或原始 170 題。

### 追溯 ID

- `Q001～Q170`：原對話題號；逐題保留使用者原答、定案說明、提問選項與 rc1 映射。
- `FV-001～FV-074`：v0.9 第 1～74 節。
- `FV-075～FV-078`：先前草稿的 review 補錄 ID，為保持引用穩定而保留。
- `FV-079～FV-108`：本次補齊的 v0.9 第 75～104 節；各節明示原始節次。
- `RC-01～RC-25`：rc1 的實作契約；不是題號，也不是已完成功能的標記。
- `D-001` 起：本次架構細化的後續決策，獨立於原始 170 題；[D-001：A＋](#decision-a-plus)。

任何 scope 降級都保留 Q／FV 項目。真正取消或改變規則須有 ADR 與 superseded 記錄；不得用刪掉文字表示延期。

<a id="source-status"></a>
## 來源與完整性

來源：[重新開始記帳APP](https://chatgpt.com/c/6ab77709-f5d0-83e9-9b8a-1ba39df6c835)，conversation ID：`6ab77709-f5d0-83e9-9b8a-1ba39df6c835`。原對話需有權限的帳戶才能查看；本文件已內嵌決策摘錄，閱讀規格不依賴重新登入來源。

已逐段核對原始題目、使用者回答與後續更正，完成 **170／170** 決策核對，並保存完整 v0.9 **104／104** 節與完整最新 review。

- **S1**：v0.9 Product & Architecture Baseline，完整 104 節。FV 各節保留原文；補取部分僅將網頁排版轉為 Markdown。
- **S2**：完整減重 review，包含 14 項 review、實際 CORE 清單與 GO／NO-GO 結論，保存在[review 附錄](#review-source)。
- **S3**：原始逐題討論 Q001～Q170，見[決策登錄](#question-register)。每題均有提問與使用者回答，早期 Q001／Q002 的原文以「第一題／第二題」稱呼。
- **S4**：使用者同意同時輸出兩份文件，並要求未來能力不得因減重遺失；本文件與 rc1 共同落實此規則。
- **S5**：本次文件整理對話的後續確認：先定整體框架，再逐項實作功能，控制擴充的複雜度與影響範圍。見[框架先行原則](#framework-first)。
- **S6**：本次對話選定 A＋並要求進一步優化，同時改以文字回答後續選擇。見 [D-001](#decision-a-plus)。
- **S7**：本次對話明確選定按業務拆套件，業務內有必要時可以再拆；仍先定架構方向再開始開發。見 [D-002](#decision-module-enforcement)。
- **S8**：使用者反映架構選擇過於密集，並同意先由助手整合框架，將真正需其選擇的取捨集中為最多三組；見整合提案。此同意是整理方式的授權，不代表已接受提案中的候選答案，也不授權提前開發功能。
- **S9**：使用者其後明確採用 1A／2A／3A，要求先提出實作安排；見 [D-003](#decision-product-delivery)。S8 記錄的是先前同意整理的時點，候選答案於 S9 才定案。

來源是產品決策紀錄，不是目前外部服務價格、API 資格或平台政策的保證。來源中涉及供應商與平台的敘述保留歷史上下文；真正整合時仍需驗證當時的官方契約。

### 原對話編號更正：Q147～Q149

原回覆曾誤把回答 Fee 題目的 C 當成 Q147 改選完整 Tax Engine，接著把 Tax Rule Provider 又稱作 Q148；後續回覆已明確校正：

- **Q147：B，結構化 Tax Component；預留完整 Tax Engine。**
- **Q148：C，統一 Charge／Adjustment Component Framework。**
- **Q149：C，Versioned Tax Rule Provider。**

本文件採校正後編號；錯誤中間回覆不構成另一項有效決策，也不將 Q147 改成 C。詳見 [Q147](#q147)、[Q148](#q148)、[Q149](#q149)。

## 導覽

- [170 題決策登錄](#question-register)：原答、目標、範圍與雙向追溯。
- [FV-001](#fv-001)～[FV-074](#fv-074)：產品、Ledger、Domain、資料、安全與儲存。
- [FV-075](#fv-075)～[FV-078](#fv-078)：最新 review 補錄。
- [FV-079](#fv-079)～[FV-108](#fv-108)：完整後端、安全、體驗、品質、發版與治理。
- [完整減重 review](#review-source)。

<a id="fv-001"></a>
## FV-001｜核心產品原則

來源：S1 第 1 節「核心產品原則」。  
當期對應：[RC-01](architecture-baseline-v1.0-rc1.md#rc-01)。  
rc1 處置：核心正確性不變；未使用的進階功能改為先保留 extension point。成熟度與範圍分開。

### 保存的願景正文

ExpenseTracker V2 不以「功能數量最多」為目標，而是：

**底層完整、財務正確、資料可靠；UI 保持簡單，只露出目前真正有用的功能。**

一項能力存在於程式碼中，不代表一定要立即出現在 UI。

進階能力可以：

1. 先完成 Domain / Data / Service 層。
2. 完成完整測試與 invariant 驗證。
3. 暫時不在正式 UI 顯示。
4. 待真正需要時才透過 Capability 開啟。
5. 大型資源、模型、規則資料可採按需下載。
6. 適合的平台功能可進一步採 Optional / Deferred Component。
7. 不允許因為「目前 UI 沒用到」就寫成假的、stub、TODO 或不完整實作。

**Hidden ≠ unfinished。**

如果 Capability 被標記為 `implemented`，其底層行為就必須是正確、可測試、可 migration、可維護的。

同時必須區分：

- `reserved`：只有架構與 extension point，尚未宣稱完成。
- `implemented`：功能已實作。
- `verified`：測試與 architecture gate 已通過。
- `enabled`：正式開放給使用者。
- `optional`：可依需求另外載入。
- `experimental`：只允許 dev / staging。
- `deprecated`：準備淘汰。

只有 `verified` 的 Capability 才能進入正式 UI。

<a id="fv-002"></a>
## FV-002｜選配能力與按需載入

來源：S1 第 2 節「Optional Capability / 按需載入原則」。  
當期對應：[RC-01](architecture-baseline-v1.0-rc1.md#rc-01)。  
rc1 處置：核心內建；按需下載以資料／模型／資源優先。未完成能力不可假裝可選配安裝。

### 保存的願景正文

V2 採 Progressive Capability Architecture。

#### Core

一定存在、一定可離線使用：

- Ledger
- Transaction
- Account
- Category
- Transfer
- 基本多幣別
- Search
- Backup 基礎
- Security
- Core Reports

#### Built-in but hidden

程式已完整存在，但 UI 可先不顯示，例如：

- 進階 Corporate Action
- Benchmark Attribution
- Tax Lot 進階操作
- Scenario 進階設定
- 高階 Automation
- Advanced Reconciliation Tools
- Multi-workspace UI

#### Downloadable resources

可真正按需下載：

- OCR model
- 市場資料 package
- 大型 reference data
- Tax rules
- Institution metadata
- Provider metadata
- Import parser definitions
- ML / prediction models
- 非核心 assets

#### Optional executable modules

只有在平台正式支援、安全且 release pipeline 可以驗證時才使用。

Android 若使用 Play 發布，可評估 Flutter Deferred Components / Dynamic Feature。

若採 GitHub APK 為主要發佈方式，原則上：

**程式碼仍隨 App release 發布；按需下載主要用於資料、模型與資源。**

不自行建立任意 remote-code plugin system。

<a id="fv-003"></a>
## FV-003｜完整產品範圍

來源：S1 第 3 節「V1 產品範圍」。  
當期對應：[RC-01](architecture-baseline-v1.0-rc1.md#rc-01)。  
rc1 處置：原 v0.9 廣域 V1 範圍完整保留為長期願景；第一階段以 rc1 CORE 清單取代。

### 保存的願景正文

V1 定位為完整個人財務 App，而非只有簡單記帳。

核心範圍包含：

- 收入 / 支出
- 多帳戶
- 轉帳
- 雙層分類
- Tag
- Merchant
- Receipt / Invoice
- OCR
- 多幣別
- FX
- 預算
- 定期交易
- 帳單
- 信用卡
- 分期
- 投資
- 貸款
- Goals
- Forecast
- Search
- Reports
- Backup / Restore
- Import / Export
- Reconciliation
- Financial Inbox

但「完整 Domain」不等於「V1 UI 全部攤開」。

<a id="fv-004"></a>
## FV-004｜主導航

來源：S1 第 4 節「Navigation」。  
當期對應：[RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

底部主導航固定為：

**首頁｜帳本｜＋｜報表｜資產**

設定、安全、備份、匯入等低頻能力不占主 navigation。

中央 `＋` 是最高頻操作。

<a id="fv-005"></a>
## FV-005｜首頁

來源：S1 第 5 節「首頁原則」。  
當期對應：[RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

首頁介於極簡與完整 Dashboard 之間。

固定核心：

- 當期收支 / Cash Flow
- 淨資產 / 帳戶總覽
- 最近 5 筆交易

可顯示但可關閉：

- 整體預算 + 最需要注意的 1～2 項
- 信用卡待繳總額 + 最近到期卡
- 一行投資摘要
- 最近 3 筆即將發生事項

V1 可以隱藏區塊，但不提供自由拖曳 Dashboard Builder。

避免：

**大量卡片堆疊。**

整體採暖色、淺背景、具有層次但保持乾淨。

<a id="fv-006"></a>
## FV-006｜新增交易流程

來源：S1 第 6 節「新增交易 UX」。  
當期對應：[RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

中央 `＋`：

先打開 Quick Sheet。

高頻欄位：

- 金額
- 收入 / 支出
- 帳戶
- 分類
- 商家

更多功能再進完整表單：

- Tag
- 附件
- Receipt
- Split
- FX
- Fee
- 進階時間
- 其他 metadata

特殊財務事件走專用 Flow：

- Transfer
- FX conversion
- Investment
- Refund
- Reversal
- Credit-card payment

不把所有功能硬塞進一張表單。

金額欄內建：

`+ − × ÷ % ()`

且核心金額計算禁止使用 binary floating-point。

<a id="fv-007"></a>
## FV-007｜Ledger 核心

來源：S1 第 7 節「Ledger 核心」。  
當期對應：[RC-03](architecture-baseline-v1.0-rc1.md#rc-03)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

採：

**High-standard Ledger Model**

但不是使用者可見的正式會計軟體。

一個 Financial Transaction 可以包含多個 Ledger Legs。

Ledger 必須滿足：

- balance 可由 Ledger 重建
- 不直接修改 current balance
- transfer 是單一完整事件
- refund 可追溯原交易
- reversal 是明確事件
- adjustment 必須留痕
- 多幣別 leg 原生支援
- split transaction 原生支援
- 未來 multi-account payment 不需 redesign

正式財務資料不能靠 UI hack 維持一致。

<a id="fv-008"></a>
## FV-008｜交易修訂與刪除

來源：S1 第 8 節「Transaction Revision」。  
當期對應：[RC-03](architecture-baseline-v1.0-rc1.md#rc-03)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

一般編輯：

**Revision History**

一般刪除：

**Soft Delete / Tombstone**

正式財務意義變更：

- Refund
- Reversal
- Posted credit-card correction
- Investment cancellation

不得直接覆寫歷史。

必須建立對應 Financial Event。

<a id="fv-009"></a>
## FV-009｜金額與精度

來源：S1 第 9 節「金額與精度」。  
當期對應：[RC-04](architecture-baseline-v1.0-rc1.md#rc-04)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

Ledger 金額：

**Integer Minor Unit**

例如 USD 12.34：

`1234`

匯率、股價、Cost Basis：

**High Precision Decimal**

核心財務運算：

**禁止 double。**

Rounding rule 由各 Domain 明確定義。

例如：

- FX 最後一步才 round
- Split 最後一項吸收 remainder
- Installment 最後一期吸收尾差
- Investment cost basis 保留高精度

<a id="fv-010"></a>
## FV-010｜帳戶模型

來源：S1 第 10 節「Account Model」。  
當期對應：[RC-05](architecture-baseline-v1.0-rc1.md#rc-05)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

預設 Account Type：

- Cash
- Bank
- Digital Bank
- Credit Card
- E-wallet
- Stored Value
- Investment
- Other Asset
- Other Liability

V1 不開放任意 Custom Account Type，但 model 保留擴充能力。

Account Lifecycle：

- openedAt
- opening balance event
- closedAt
- closing validation
- remaining balance transfer
- reopen
- archived

Opening Balance 不計入一般 Income Report。

<a id="fv-011"></a>
## FV-011｜分類與標籤

來源：S1 第 11 節「Category / Tag」。  
當期對應：[RC-05](architecture-baseline-v1.0-rc1.md#rc-05)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

Category：

固定雙層。

`Parent → Subcategory`

Income 與 Expense 在產品上分開。

Tag：

Flat contextual metadata。

例如：

`餐飲 > 晚餐`

Tag：

`日本旅遊`
`朋友聚餐`

Category 回答：

**這筆錢是什麼。**

Tag 回答：

**這筆錢屬於什麼情境。**

<a id="fv-012"></a>
## FV-012｜商家與實體識別

來源：S1 第 12 節「Merchant / Entity」。  
當期對應：[RC-05](architecture-baseline-v1.0-rc1.md#rc-05)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

Merchant 為正式 Entity，不是純文字。

支援：

- alias
- canonical ID
- branch
- location
- rule memory
- transaction history

Entity Resolution Engine 可使用：

- alias
- OCR
- 地址
- 歷史資料
- 機構代碼
- symbol / ISIN

進行候選匹配。

不自動合併重要 Entity，需確認。

<a id="fv-013"></a>
## FV-013｜交易 metadata

來源：S1 第 13 節「Transaction Metadata」。  
當期對應：[RC-03](architecture-baseline-v1.0-rc1.md#rc-03)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

正式 Transaction 可包含：

- Amount
- Currency
- Account
- Category
- Merchant
- Tags
- Notes
- Attachments
- Receipt / Invoice
- Location
- Fee / Tax components
- Source
- Status
- Financial timestamps

Note 保持單純文字。

系統歷程另用：

**Activity Timeline**

不把 Audit 資訊塞進 Note。

<a id="fv-014"></a>
## FV-014｜交易生命週期

來源：S1 第 14 節「Transaction Lifecycle」。  
當期對應：[RC-03](architecture-baseline-v1.0-rc1.md#rc-03)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

狀態與 Financial Event 分離。

可包含：

- Authorized
- Pending
- Posted
- Cleared
- Reconciled
- Voided

Refund / Reversal 不只是狀態。

而是新的 Financial Event。

<a id="fv-015"></a>
## FV-015｜財務日期與時區

來源：S1 第 15 節「Financial Date Model」。  
當期對應：[RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

資料模型可保存：

- occurredAt
- authorizedAt
- postedAt
- settledAt
- valueDate
- importedAt

正常 UI 只顯示使用者需要的日期與時間。

時間保存完整 timezone / offset semantics。

<a id="fv-016"></a>
## FV-016｜交易拆分

來源：S1 第 16 節「Split Transaction」。  
當期對應：[RC-03](architecture-baseline-v1.0-rc1.md#rc-03)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

V1 支援：

一個付款帳戶 + 多分類拆分。

支援：

- 手動金額
- 平均分
- 百分比
- 固定比例

尾差依 rounding policy 處理。

底層預留：

- multi-account payment
- partial refund
- full refund
- mixed payment
- split template

<a id="fv-017"></a>
## FV-017｜信用卡 Domain

來源：S1 第 17 節「Credit Card Domain」。  
當期對應：[RC-07](architecture-baseline-v1.0-rc1.md#rc-07)。  
rc1 處置：基本信用卡是 CORE；完整額度與發卡行規則保留為 EXTENSION-READY／OPTIONAL。

### 保存的願景正文

信用卡為正式 Domain，不只是負數帳戶。

支援：

- statement cycle
- close date
- due date
- credit limit
- pending amount
- posted amount
- payment state
- installment
- statement matching
- reconciliation

Credit Limit Engine 支援：

- supplementary cards
- temporary limit
- installment occupancy
- pending holds
- credit balance
- overpayment
- release timing

<a id="fv-018"></a>
## FV-018｜融資與分期

來源：S1 第 18 節「Financing」。  
當期對應：[RC-07](architecture-baseline-v1.0-rc1.md#rc-07)。  
rc1 處置：基本分期是 CORE；進階融資與特殊利息規則延後。

### 保存的願景正文

支援：

- purchase installment
- statement installment
- 0% plan
- fixed fees
- APR
- interest
- principal
- early settlement
- partial prepayment

可透過 Issuer Adapter 處理金融機構特殊規則。

<a id="fv-019"></a>
## FV-019｜多幣別與換匯

來源：S1 第 19 節「Multi-currency / FX」。  
當期對應：[RC-04](architecture-baseline-v1.0-rc1.md#rc-04)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

帳戶與 Ledger Leg 均可有自己的 Currency。

換匯可表示：

TWD account  
→ USD account  
→ fee

保留：

- original amount
- original currency
- actual transaction rate
- fee
- conversion context

歷史交易永遠不使用今天匯率重算。

<a id="fv-020"></a>
## FV-020｜FX 引擎

來源：S1 第 20 節「FX Engine」。  
當期對應：[RC-04](architecture-baseline-v1.0-rc1.md#rc-04)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

FX Rate Engine 支援：

- 多 Provider
- historical rates
- bid / ask / mid
- official rate
- market rate
- user override
- provider confidence
- fallback
- gap policy

每個 Workspace 有正式 Base Currency。

Report / Asset UI 可臨時切換 Display Currency。

<a id="fv-021"></a>
## FV-021｜匯率重估與損益

來源：S1 第 21 節「FX Revaluation」。  
當期對應：[RC-04](architecture-baseline-v1.0-rc1.md#rc-04)。  
rc1 處置：原額與匯率來源是 CORE；完整 FX 損益歸因與重估延後。

### 保存的願景正文

支援：

- realized FX P/L
- unrealized FX P/L
- period-end valuation
- FX cost basis
- fee allocation
- market return vs FX return

一般 UI 用「匯率影響」呈現，不要求使用者理解會計術語。

<a id="fv-022"></a>
## FV-022｜投資 Domain

來源：S1 第 22 節「Investment Domain」。  
當期對應：[RC-08](architecture-baseline-v1.0-rc1.md#rc-08)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

Investment 從一開始採完整 Portfolio Model。

支援：

- Buy
- Sell
- Dividend
- Fee
- Tax
- Holdings
- Multiple brokers
- Multiple accounts
- Cost basis
- Realized / unrealized P&L
- Corporate actions
- Split / reverse split
- Stock distribution
- Dividend reinvestment

Advanced UI 可延後。

<a id="fv-023"></a>
## FV-023｜Tax Lot 與成本策略

來源：S1 第 23 節「Tax Lot」。  
當期對應：[RC-08](architecture-baseline-v1.0-rc1.md#rc-08)。  
rc1 處置：保留 lot 資料，首版驗證 Average Cost／FIFO；LIFO／Specific Lot 透過 Strategy 延後。

### 保存的願景正文

完整 Tax Lot Engine：

- acquisition date
- quantity
- cost
- fee allocation
- FX cost
- partial disposal
- lot transfer
- corporate-action adjustment

支援：

- Average
- FIFO
- LIFO
- Specific Lot

V1 UI 可以只突出平均成本。

<a id="fv-024"></a>
## FV-024｜投資績效分析

來源：S1 第 24 節「Investment Analytics」。  
當期對應：[RC-08](architecture-baseline-v1.0-rc1.md#rc-08)。  
rc1 處置：Total Return、損益、Dividend、XIRR 為 CORE；其他績效分析延後。

### 保存的願景正文

底層支援：

- Total Return
- XIRR
- TWR
- Realized P/L
- Unrealized P/L
- Dividend contribution
- FX contribution
- Benchmark
- Attribution
- Volatility
- Max drawdown

V1 UI 先露出一般人真正會看的內容。

<a id="fv-025"></a>
## FV-025｜金融商品模型

來源：S1 第 25 節「Instrument」。  
當期對應：[RC-08](architecture-baseline-v1.0-rc1.md#rc-08)。  
rc1 處置：通用模型保留；正式驗證股票／ETF；其餘商品延後。

### 保存的願景正文

使用通用 Instrument Model。

可擴充：

- Stocks
- ETF
- Fund
- Bond
- Cash
- REIT
- Commodity
- Crypto
- Options

V1 UI 先優先常見投資商品。

<a id="fv-026"></a>
## FV-026｜市場資料

來源：S1 第 26 節「Market Data」。  
當期對應：[RC-08](architecture-baseline-v1.0-rc1.md#rc-08)。  
rc1 處置：多 Provider 介面保留，只整合主要來源；不要求首版接多家相同類型供應商。

### 保存的願景正文

採 Multi-provider Architecture。

統一介面：

`MarketDataProvider`

Provider 可以依：

- 市場
- 商品類型
- quote
- history
- corporate action

做 primary / fallback。

Market Data Pipeline 支援：

- cache
- TTL
- stale-while-revalidate
- trading hours
- batch quote
- rate limit
- retry/backoff
- data-source metadata

<a id="fv-027"></a>
## FV-027｜預算

來源：S1 第 27 節「Budget」。  
當期對應：[RC-09](architecture-baseline-v1.0-rc1.md#rc-09)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

底層為完整 Budget Rule Engine。

支援：

- Parent Category
- Subcategory
- Account
- Tag
- custom period
- rollover
- project budget
- one-time budget
- exclusions
- overlapping priority
- thresholds

V1 UI 先保持簡單。

<a id="fv-028"></a>
## FV-028｜定期交易與自動化

來源：S1 第 28 節「Recurring / Automation」。  
當期對應：[RC-09](architecture-baseline-v1.0-rc1.md#rc-09)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

完整 Recurring Rule Engine。

支援：

- Daily
- Weekly
- Monthly
- Yearly
- Every N
- Month end
- Start / End
- Count limit
- Variable amount
- Prior-period reference
- holiday adjustment
- multi-step flow
- bill / statement linkage

V1 UI 只先開放常用規則。

<a id="fv-029"></a>
## FV-029｜共用規則與條件模型

來源：S1 第 29 節「Rules」。  
當期對應：[RC-10](architecture-baseline-v1.0-rc1.md#rc-10)。  
rc1 處置：CORE 先支援 versioned AND 條件；完整 Boolean／AST compiler 與衝突處理延後。

### 保存的願景正文

Rule Engine 使用統一 Predicate / Expression DSL。

可供：

- Search
- Analytics
- Budget
- Automation

共同使用。

底層：

Versioned Serializable AST。

支援：

- AND
- OR
- NOT
- comparison
- range
- set membership

Priority：

明確 Priority + Specificity。

若仍衝突：

進 Financial Inbox。

<a id="fv-030"></a>
## FV-030｜待確認資料收件匣

來源：S1 第 30 節「Financial Inbox」。  
當期對應：[RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。  
rc1 處置：匯入需要的 staging／確認是 CORE 子集；通用 Financial Inbox 與多來源批次處理延後。

### 保存的願景正文

所有尚未確認的資料先進 Staging。

例如：

- OCR
- QR invoice
- bank import
- card statement
- duplicate candidate
- recurring candidate
- draft
- unmatched transaction

Inbox Item：

**不影響 Ledger、不影響 Balance、不進 Report。**

只有 Confirm 後才轉為正式 Financial Event。

支援批次：

- confirm
- ignore
- category
- Tag
- account
- matching

高風險項目仍逐筆確認。

<a id="fv-031"></a>
## FV-031｜OCR 與憑證

來源：S1 第 31 節「OCR / Receipt」。  
當期對應：[RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。  
rc1 處置：OPTIONAL，第二階段起；本機優先，雲端由使用者選擇。

### 保存的願景正文

Attachment 支援：

- image
- PDF
- receipt
- invoice

OCR：

**Local-first**

本機辨識 confidence 不足時，可由使用者主動選擇 Cloud OCR。

Cloud OCR：

- 只處理指定附件
- 不傳整份 Ledger
- 非核心依賴

OCR 只預填。

永遠不直接 Posting。

<a id="fv-032"></a>
## FV-032｜收據與台灣電子發票

來源：S1 第 32 節「Receipt / Taiwan Invoice」。  
當期對應：[RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。  
rc1 處置：OPTIONAL，第二階段起；保留來源／交易關聯，QR 不直接入帳。

### 保存的願景正文

Receipt / Invoice 為正式 Entity。

支援：

- invoice number
- date
- merchant
- amount
- currency
- attachment
- OCR
- verification
- linked transaction

台灣電子發票預留：

- QR payload
- invoice identifier
- carrier metadata
- future API adapter

QR 掃描後先進 Matching Engine。

<a id="fv-033"></a>
## FV-033｜Matching 引擎

來源：S1 第 33 節「Matching Engine」。  
當期對應：[RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。  
rc1 處置：CORE 只完成匯入必要的重複檢查；通用 Matching 延後。

### 保存的願景正文

所有來源共用 Matching Pipeline：

- manual vs import
- OCR vs card statement
- bank CSV vs ledger
- broker statement vs investment
- invoice vs transaction

支援：

- exact
- fuzzy
- one-to-many
- many-to-one
- confidence
- merge suggestion

人工確認歷史可改善候選排序。

<a id="fv-034"></a>
## FV-034｜對帳

來源：S1 第 34 節「Reconciliation」。  
當期對應：[RC-12](architecture-baseline-v1.0-rc1.md#rc-12)。  
rc1 處置：rc1 提案：保留核心更正與帳單關聯；完整 Reconciliation 為 EXTENSION-READY。

### 保存的願景正文

完整 Reconciliation：

- statement cutoff
- cleared / uncleared
- reconciliation snapshot
- reconciliation history
- import matching
- missing / duplicate detection
- explicit adjustment

禁止直接修改 balance 來「對平」。

<a id="fv-035"></a>
## FV-035｜帳單與應付

來源：S1 第 35 節「Bills / Payables」。  
當期對應：[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。  
rc1 處置：完整 Domain 延後為 OPTIONAL；本階段只保留 EXTENSION-READY 邊界，詳見 RC-16 對應能力。

### 保存的願景正文

正式 Billing Engine。

Bill 本身不影響 Ledger。

Payment 才影響 Ledger。

支援：

- issued
- due
- paid
- partial payment
- overdue
- late fee
- auto-pay
- correction
- attachments
- Forecast
- Reminder
- Calendar

<a id="fv-036"></a>
## FV-036｜借貸與應收

來源：S1 第 36 節「Receivable」。  
當期對應：[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。  
rc1 處置：完整 Domain 延後為 OPTIONAL；本階段只保留 EXTENSION-READY 邊界，詳見 RC-16 對應能力。

### 保存的願景正文

Personal Lending / Receivable 支援：

- lending
- due date
- partial repayment
- installment
- interest
- extension
- write-off
- matching
- Forecast
- Calendar

借出去的錢屬於 Receivable Asset，不當成一般消費。

<a id="fv-037"></a>
## FV-037｜共同支出

來源：S1 第 37 節「Shared Expense」。  
當期對應：[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。  
rc1 處置：完整 Domain 延後為 OPTIONAL；本階段只保留 EXTENSION-READY 邊界，詳見 RC-16 對應能力。

### 保存的願景正文

支援：

- split among people
- multiple payers
- equal / amount / percentage
- partial repayment
- multi-currency
- net settlement

UI 先維持：

「誰付錢 / 誰欠多少 / 是否已還」。

<a id="fv-038"></a>
## FV-038｜代墊與核銷

來源：S1 第 38 節「Reimbursement」。  
當期對應：[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。  
rc1 處置：完整 Domain 延後為 OPTIONAL；本階段只保留 EXTENSION-READY 邊界，詳見 RC-16 對應能力。

### 保存的願景正文

Expense Claim Engine 底層支援：

- multiple expenses per claim
- submitted
- returned
- approved
- partial approval
- paid
- FX
- receipt completeness
- Organization

V1 UI 先簡化為：

「代墊 → 已提交 → 待核銷 → 已收到」。

<a id="fv-039"></a>
## FV-039｜組織與人員關係

來源：S1 第 39 節「Organization / Person」。  
當期對應：[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。  
rc1 處置：完整 Domain 延後為 OPTIONAL；本階段只保留 EXTENSION-READY 邊界，詳見 RC-16 對應能力。

### 保存的願景正文

正式 Entity：

- Person
- Organization
- Financial Institution
- Merchant

底層可建立 Relationship Graph。

例如：

Person → works for → Organization  
Merchant → belongs to → Organization

V1 UI 不顯示複雜 graph。

<a id="fv-040"></a>
## FV-040｜貸款

來源：S1 第 40 節「Loans」。  
當期對應：[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。  
rc1 處置：完整 Domain 延後為 OPTIONAL；本階段只保留 EXTENSION-READY 邊界，詳見 RC-16 對應能力。

### 保存的願景正文

完整 Liability / Loan Engine：

- fixed / floating rate
- rate history
- grace period
- principal
- interest
- repayment schedule
- early repayment
- extra principal
- fees

支援：

- mortgage
- personal loan
- auto loan

但淨資產不納入房產、車輛等非金融資產。

<a id="fv-041"></a>
## FV-041｜財務目標

來源：S1 第 41 節「Goals」。  
當期對應：[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。  
rc1 處置：完整 Domain 延後為 OPTIONAL；本階段只保留 EXTENSION-READY 邊界，詳見 RC-16 對應能力。

### 保存的願景正文

V1：

- target amount
- due date
- linked account
- progress
- monthly suggestion

底層預留：

- priority
- automated contribution
- forecast integration
- achievement prediction

<a id="fv-042"></a>
## FV-042｜預測與情境

來源：S1 第 42 節「Forecast / Scenario」。  
當期對應：[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。  
rc1 處置：完整 Domain 延後為 OPTIONAL；本階段只保留 EXTENSION-READY 邊界，詳見 RC-16 對應能力。

### 保存的願景正文

Cash Flow Forecast 支援：

- recurring
- bills
- credit card
- installment
- loans
- commitments
- planned transactions

底層 Scenario Engine 可模擬：

- spending change
- investment change
- loan prepayment
- FX assumption
- postponed expense

Scenario 不直接改 Ledger。

可逐項轉成：

- Goal
- Budget
- Recurring
- Reminder
- Planned Transaction

<a id="fv-043"></a>
## FV-043｜未來財務承諾

來源：S1 第 43 節「Commitment Model」。  
當期對應：[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。  
rc1 處置：完整 Domain 延後為 OPTIONAL；本階段只保留 EXTENSION-READY 邊界，詳見 RC-16 對應能力。

### 保存的願景正文

未來財務事項可區分：

- Planned
- Scheduled
- Committed
- PendingExternalConfirmation

可以進 Forecast。

在 Posted 前不能影響正式 Balance。

<a id="fv-044"></a>
## FV-044｜訂閱管理

來源：S1 第 44 節「Subscription」。  
當期對應：[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。  
rc1 處置：完整 Domain 延後為 OPTIONAL；本階段只保留 EXTENSION-READY 邊界，詳見 RC-16 對應能力。

### 保存的願景正文

完整 Subscription Domain 底層能力：

- billing cycle
- trial
- renewal
- price history
- recurring detection
- multi-currency
- usage state
- renewal reminder

UI 先保持 Subscription Profile 的簡潔形式。

<a id="fv-045"></a>
## FV-045｜保險

來源：S1 第 45 節「Insurance」。  
當期對應：[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。  
rc1 處置：完整 Domain 延後為 OPTIONAL；本階段只保留 EXTENSION-READY 邊界，詳見 RC-16 對應能力。

### 保存的願景正文

V1 做基本 Policy Model：

- insurer
- policy number
- premium
- cycle
- effective date
- expiry
- next payment
- attachment
- status

完整 Insurance Domain 僅預留。

<a id="fv-046"></a>
## FV-046｜收入來源與薪資

來源：S1 第 46 節「Income Source」。  
當期對應：[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。  
rc1 處置：完整 Domain 延後為 OPTIONAL；本階段只保留 EXTENSION-READY 邊界，詳見 RC-16 對應能力。

### 保存的願景正文

V1 有正式 Income Source：

- salary
- freelance
- part-time
- recurring income

包含：

- Organization
- expected amount
- pay cycle
- account

完整 Payroll Engine 僅預留。

<a id="fv-047"></a>
## FV-047｜稅、費用與回饋

來源：S1 第 47 節「Tax / Fee」。  
當期對應：[RC-03](architecture-baseline-v1.0-rc1.md#rc-03)。  
rc1 處置：實際交易 Tax／Fee components 是 CORE；完整 Tax Rule Provider 延後；積分／里程不屬首版。

### 保存的願景正文

交易可有結構化：

- Tax
- Fee
- Interest
- Adjustment

Tax Rule 支援版本化 Provider：

- jurisdiction
- effective date
- version
- source
- override

V1 不把產品變成報稅軟體。

Discount：

直接使用實際支付金額。

Reward / mileage / point system：

V1 不做。

延後收到 Cashback 時，以獨立回饋 / Adjustment Transaction 記錄。

<a id="fv-048"></a>
## FV-048｜搜尋

來源：S1 第 48 節「Search」。  
當期對應：[RC-10](architecture-baseline-v1.0-rc1.md#rc-10)。  
rc1 處置：結構化搜尋與最小 Predicate 是 CORE；FTS／fuzzy／OCR 搜尋與自然語言查詢延後。

### 保存的願景正文

V1：

Advanced Structured Search。

條件可包含：

- Merchant
- Note
- Account
- Category
- Tag
- Currency
- Transaction type
- Status
- Amount
- Date
- Attachment

底層 Search Projection Engine：

- SQLite FTS
- alias
- canonical entity
- ranking
- fuzzy candidates
- OCR text
- incremental index
- rebuild
- version

未來 Natural Language Search：

`Natural Language → Predicate AST`

不另外建查詢系統。

<a id="fv-049"></a>
## FV-049｜分析查詢

來源：S1 第 49 節「Analytics」。  
當期對應：[RC-13](architecture-baseline-v1.0-rc1.md#rc-13)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

完整 Analytics Query Engine。

Dimension / Filter 可組合：

- date
- account
- category
- currency
- merchant
- tag
- transaction type

支援：

- drill-down
- saved query
- custom report
- future dashboard

UI 維持一般 Personal Finance Report。

不是 BI Tool。

<a id="fv-050"></a>
## FV-050｜分析倉儲

來源：S1 第 50 節「Analytics Warehouse」。  
當期對應：[RC-13](architecture-baseline-v1.0-rc1.md#rc-13)。  
rc1 處置：先以少量 Projection + SQLite query／indexes 完成；通用 Warehouse 延後。

### 保存的願景正文

核心 Ledger 不承擔所有重型分析。

建立 Local Analytics Warehouse / Projection。

支援：

- daily balance
- monthly totals
- category aggregation
- net worth
- investment analytics

可重建。

不是 Source of Truth。

<a id="fv-051"></a>
## FV-051｜衍生投影

來源：S1 第 51 節「Projection」。  
當期對應：[RC-13](architecture-baseline-v1.0-rc1.md#rc-13)。  
rc1 處置：版本／rebuild 與必要更新為 CORE；通用增量引擎與一致性平台延後。

### 保存的願景正文

採 Incremental Projection Engine。

支援：

- event-driven update
- checkpoint
- projection version
- dirty-range recalculation
- full rebuild fallback

Consistency Tier：

- Strong
- Near-real-time
- Eventual

UI 能知道 stale / updating 狀態。

<a id="fv-052"></a>
## FV-052｜備份

來源：S1 第 52 節「Backup」。  
當期對應：[RC-14](architecture-baseline-v1.0-rc1.md#rc-14)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

Local-first。

登入為選配。

Cloud Backup 底層：

- versioned
- encrypted
- revisions
- tombstones
- attachments
- sync metadata

使用者只看到：

- 自動備份
- 手動備份
- 最後成功時間
- 歷史版本
- Restore

<a id="fv-053"></a>
## FV-053｜還原

來源：S1 第 53 節「Restore」。  
當期對應：[RC-14](architecture-baseline-v1.0-rc1.md#rc-14)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

Restore 必須可驗證。

支援：

- checksum
- manifest
- schema compatibility
- restore dry-run
- Ledger invariant
- attachment validation
- migration validation
- projection rebuild
- safety backup before restore

失敗時不能傷害目前正式資料。

<a id="fv-054"></a>
## FV-054｜長期標準封存

來源：S1 第 54 節「Canonical Archive」。  
當期對應：[RC-14](architecture-baseline-v1.0-rc1.md#rc-14)。  
rc1 處置：先完成 specification；完整 Canonical Archive exporter／importer 延後。

### 保存的願景正文

三層分離：

`Runtime DB`

≠

`Backup Package`

≠

`Long-term Canonical Archive`

Canonical Archive 採人類可讀 + machine-readable。

可包含：

- manifest.json
- accounts.jsonl
- transactions.jsonl
- ledger_entries.jsonl
- entities
- investments
- metadata
- attachments
- schema
- README
- checksums

<a id="fv-055"></a>
## FV-055｜加密與金鑰

來源：S1 第 55 節「Encryption」。  
當期對應：[RC-14](architecture-baseline-v1.0-rc1.md#rc-14)。  
rc1 處置：可還原的加密備份是 CORE；後續 D-003／2A 已將最小 envelope、密碼＋文字 Recovery Key 與雙路還原驗證提前至首個可用版本，QR／完整 rotation／定期 health check 等進階能力仍延後。下方願景正文原樣保留。

### 保存的願景正文

Canonical Data 與 Encryption Container 解耦。

採 Key Envelope：

Data Encryption Key

可被：

- password-derived key
- Recovery Key

分別包裝。

支援：

- password change
- Recovery Key rotation
- Recovery Health Check
- test unlock

Recovery Key：

文字 + QR Code。

不自動存相簿。

<a id="fv-056"></a>
## FV-056｜安全

來源：S1 第 56 節「Security」。  
當期對應：[RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

支援：

- App PIN
- Biometrics
- automatic lock
- encrypted local DB
- Android Keystore
- future iOS Keychain
- encrypted backup

App logout：

不能刪除 local financial data。

<a id="fv-057"></a>
## FV-057｜資料隱私

來源：S1 第 57 節「Privacy」。  
當期對應：[RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

Privacy Capability Layer 管理：

- Camera
- Files
- Location
- Notifications
- Calendar
- Biometrics
- Cloud OCR

每項 Capability 必須知道：

- uses what data
- leaves device?
- retention
- optional?
- revocable?

<a id="fv-058"></a>
## FV-058｜畫面隱私

來源：S1 第 58 節「Presentation Privacy」。  
當期對應：[RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

全 App 共用：

Privacy Presentation Layer。

涵蓋：

- Home
- Ledger
- Reports
- Search
- Recent Apps preview
- Notifications
- Widget
- Shortcut

支援：

- normal
- hide amounts
- minimal
- background privacy shield

Screen Security 支援分級敏感度。

<a id="fv-059"></a>
## FV-059｜提醒與日曆

來源：S1 第 59 節「Notification / Calendar」。  
當期對應：[RC-17](architecture-baseline-v1.0-rc1.md#rc-17)。  
rc1 處置：rc1 提案：核心簡單提醒；通用 Reminder Engine 與 Google Calendar 延後。

### 保存的願景正文

底層：

Rule-based Reminder Engine。

V1 UI：

簡單 Preset。

可輸出至：

- In-app
- System Notification
- Google Calendar

Google Calendar：

**Controlled bidirectional integration**

ExpenseTracker 為 financial source of truth。

Calendar 外部修改：

只產生差異提示。

不能直接修改 financial rules。

<a id="fv-060"></a>
## FV-060｜匯入匯出

來源：S1 第 60 節「Import / Export」。  
當期對應：[RC-18](architecture-baseline-v1.0-rc1.md#rc-18)。  
rc1 處置：匯入匯出為 CORE；rc1 提案先完成 CSV／JSON，Excel 與外部機構 adapters 延後。

### 保存的願景正文

採 Migration Framework。

External data：

`Adapter → Parser → Staging → Validation → Matching → Confirm → Ledger`

支援：

- CSV
- Excel
- JSON
- future bank statement
- credit-card statement
- broker statement
- other finance apps

匯入必須：

- preview
- mapping
- duplicate detection
- rollback

<a id="fv-061"></a>
## FV-061｜本機資料庫

來源：S1 第 61 節「Local Database」。  
當期對應：[RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

採：

**Drift + SQLite**

分層：

UI  
→ Controller / Notifier  
→ Use Case  
→ Repository Interface  
→ Data Source  
→ Drift  
→ SQLite

Domain 永遠不能直接依賴 Drift model。

<a id="fv-062"></a>
## FV-062｜狀態管理

來源：S1 第 62 節「State Management」。  
當期對應：[RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

採 Riverpod。

原則：

**Thin Riverpod, Thick Domain**

Riverpod 處理：

- UI state
- async state
- dependency injection
- orchestration
- cache invalidation

禁止把 Ledger / Investment / Budget business logic 塞進 Provider。

<a id="fv-063"></a>
## FV-063｜模組化架構

來源：S1 第 63 節「Module Architecture」。  
當期對應：[RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

採 Modular Monolith。

主要 Module：

- Ledger
- Accounts
- Credit Cards
- Budget
- Recurring
- Investment
- Analytics
- Search
- Reconciliation
- Import / Export
- Sync
- Reminder
- Forecast
- Billing
- Lending
- Security

Module 不能直接偷讀另一 Module internal repository / table。

<a id="fv-064"></a>
## FV-064｜跨模組溝通

來源：S1 第 64 節「Cross-module Communication」。  
當期對應：[RC-19](architecture-baseline-v1.0-rc1.md#rc-19)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

同步操作：

**Application API / Facade**

跨模組狀態改變：

**Domain Event**

例如：

- TransactionPosted
- RefundCreated
- StatementClosed
- ReconciliationCompleted
- InvestmentTradeExecuted

重要 Domain Event 持久化。

但不採 Full Event Sourcing。

<a id="fv-065"></a>
## FV-065｜交易邊界

來源：S1 第 65 節「Transaction Boundary」。  
當期對應：[RC-19](architecture-baseline-v1.0-rc1.md#rc-19)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

本機財務變更：

**ACID + Unit of Work**

一個 Financial Use Case：

全部成功或全部 rollback。

外部副作用：

- Calendar
- Cloud
- Provider API

不能加入 Ledger DB Transaction。

採：

Domain Event  
→ Durable Job / Saga

<a id="fv-066"></a>
## FV-066｜Transactional Inbox／Outbox

來源：S1 第 66 節「Inbox / Outbox」。  
當期對應：[RC-19](architecture-baseline-v1.0-rc1.md#rc-19)。  
rc1 處置：只在必要可靠副作用採原子 job／outbox；全面 inbox／outbox framework 延後。

### 保存的願景正文

採 Transactional Inbox + Outbox。

Ledger change + Audit + Outbox：

同一 DB Transaction commit。

Message semantics：

**At-least-once delivery**

Consumer：

**Idempotent**

Business effect：

盡可能 Exactly-once。

<a id="fv-067"></a>
## FV-067｜耐久背景工作

來源：S1 第 67 節「Durable Jobs」。  
當期對應：[RC-19](architecture-baseline-v1.0-rc1.md#rc-19)。  
rc1 處置：Persistent Job Queue、Idempotency、Retry／Backoff 為 CORE；DAG／Saga／通用 checkpoint／DLQ UI 延後。

### 保存的願景正文

統一 Durable Job Engine。

適用：

- Backup
- Restore verification
- Recurring
- Reminder
- Calendar Sync
- Market refresh
- Cleanup
- Health check

支援：

- persistent state
- checkpoint
- idempotency
- retry
- backoff
- dependencies
- priority
- cancellation
- version migration

失敗超過限制：

進 Dead Letter / Recovery Queue。

<a id="fv-068"></a>
## FV-068｜識別碼

來源：S1 第 68 節「Identity」。  
當期對應：[RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

Public / Domain ID：

**UUID v7**

Local SQLite：

可使用 `INTEGER PRIMARY KEY` 做 internal row ID。

規則：

`rowId` 永遠不能離開 Data Layer。

同步、Domain、API、Import：

一律只認 UUID。

<a id="fv-069"></a>
## FV-069｜實體生命週期

來源：S1 第 69 節「Entity Lifecycle」。  
當期對應：[RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

所有可同步核心 Entity 至少具備：

- publicId
- workspaceId
- createdAt
- updatedAt
- deletedAt
- version

必要時：

- archivedAt

只有真正需要歷史有效性的 Domain 才使用：

- validFrom
- validTo

避免全面 temporal 化。

<a id="fv-070"></a>
## FV-070｜工作空間

來源：S1 第 70 節「Workspace」。  
當期對應：[RC-20](architecture-baseline-v1.0-rc1.md#rc-20)。  
rc1 處置：defaultWorkspace 與 workspaceId 是 CORE；多帳本、跨帳本轉移與多人共用延後。

### 保存的願景正文

底層支援 Multi-workspace。

V1 UI：

只有「我的帳本」。

Workspace 可有自己的：

- accounts
- transactions
- budget
- report
- base currency

跨 Workspace Transfer：

使用 linked events。

未來 Membership：

- Owner
- Editor
- Viewer

V1 不開多人 UI。

<a id="fv-071"></a>
## FV-071｜稽核

來源：S1 第 71 節「Audit」。  
當期對應：[RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。  
rc1 處置：核心部分保留；進階子能力依 rc1 分段實作。具體範圍、接入與驗收以連結節點為準。

### 保存的願景正文

重要操作記錄 Audit Principal：

- Human
- Automation
- Importer
- BackgroundJob
- ExternalIntegration
- Migration

包含：

- actorId
- deviceId
- source
- timestamp
- correlationId

<a id="fv-072"></a>
## FV-072｜附件儲存

來源：S1 第 72 節「Attachment Storage」。  
當期對應：[RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。  
rc1 處置：依最新 review 的附件階段化方向保留契約；完整附件儲存隨 Optional 附件功能一起實作。

### 保存的願景正文

採 Content-addressed Storage。

Attachment：

- hash identity
- MIME
- metadata
- thumbnail
- OCR state
- backup state

同一檔案：

只保存一份 blob。

Revision：

只引用 attachment。

不複製檔案。

<a id="fv-073"></a>
## FV-073｜資料保留與清理

來源：S1 第 73 節「Data Lifecycle」。  
當期對應：[RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。  
rc1 處置：必要完整性與基本清理保留；統一 Lifecycle Engine、GC、compaction 延後。

### 保存的願景正文

Storage Lifecycle Engine：

- retention policy
- draft cleanup
- tombstone lifecycle
- diagnostics retention
- projection cleanup
- attachment GC
- revision compaction
- integrity check

正式財務資料優先保留。

<a id="fv-074"></a>
## FV-074｜刪除與永久清除

來源：S1 第 74 節「Delete / Purge」，已補齊全文。  
當期對應：[RC-15](architecture-baseline-v1.0-rc1.md#rc-15)、[RC-25](architecture-baseline-v1.0-rc1.md#rc-25)。  
rc1 處置：一般刪除與風險確認為 CORE；完整 Workspace purge／雲端清除與 Crypto-erasure 流程保留為後續能力，第一階段不展示未完成的永久清除入口。

### 保存的願景正文

一般刪除：

risk-based confirmation。

刪除整個 Workspace：

biometric / PIN

impact preview

backup prompt

cooling-off period

真正 Purge：

official data

revisions

tombstones

projections

search index

unused blobs

cloud copy

encryption key material

最後跑 integrity check。

採 Crypto-erasure，不假裝可以可靠覆寫 flash 實體區塊。

<a id="fv-075"></a>
## FV-075｜多裝置 Sync 與家庭共用願景

來源：S2 第 5、6 節；此 ID 保留原草稿的 review 補錄身份，對應完整 v0.9 Sync 另見 FV-081。  
當期對應：[RC-20](architecture-baseline-v1.0-rc1.md#rc-20)。

長期能力保留 Conflict resolution UI、field merge、multi-device state machine、sync inbox／outbox、server change log、Multi-workspace、Family Sharing、Member、Role、Invitation、Shared permission、Approval flow。Workspace 可擁有自己的帳戶、交易、Budget、Report 與 base currency；跨 workspace transfer 的 linked events 與 Owner／Editor／Viewer 願景亦見 [FV-070](#fv-070)。

本階段只準備 UUID、version、updatedAt、deletedAt、deviceId／actor metadata、provider-neutral Repository／cloud adapter、revision metadata 備份與唯一 defaultWorkspace。Engine、共享權限與 UI 延後，不提前建空表。第一階段產品模式為 Local-first + Cloud Backup；Backup 不是 Sync。

<a id="fv-076"></a>
## FV-076｜Recovery Center 與安全模式

來源：S2 第 12 節。  
當期對應：[RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。

長期保留進階 Recovery Center、逐筆修復 revision chain 與 Advanced Reconciliation Tools。第一階段先完成 Safe Mode：DB／Ledger health check 失敗時停止一般寫入，提供可安全使用的查看、診斷匯出、projection 重建與 backup restore。

延後完整修復中心不等於可以忽略健康檢查或讓損壞繼續擴大。具體受控復原流程與不可讀資料的處理，見 rc1 的細化提案。

<a id="fv-077"></a>
## FV-077｜長期效能目標與品質平台

來源：S2 第 13 節，以及 Q170 完成後的規格整理說明。  
當期對應：[RC-21](architecture-baseline-v1.0-rc1.md#rc-21)、[RC-22](architecture-baseline-v1.0-rc1.md#rc-22)。

保留 10～20 年、100k+ transactions 的產品目標，Ledger property／fuzz tests，以及 cold start、新增交易、單月交易載入、首頁、月報、100k query、backup／restore benchmarks。長期可建立 benchmark history、nightly regression 與更完整效能平台；第一階段不要求每個 PR 跑巨大平台。

完整測試、CI/CD 與 Codex 規範現已補齊，見 FV-095、FV-097、FV-104、FV-105 及 Q039～Q043；效能平台的實作規模仍依最新 review 分期。

<a id="fv-078"></a>
## FV-078｜Core-first, Extension-ready 與最終審查

來源：S2 第 14 節、實際 CORE 清單與 Architecture Review Gate。  
當期對應：[RC-01](architecture-baseline-v1.0-rc1.md#rc-01)、[RC-02](architecture-baseline-v1.0-rc1.md#rc-02)、[RC-06](architecture-baseline-v1.0-rc1.md#rc-06)、[RC-22](architecture-baseline-v1.0-rc1.md#rc-22)。

最新 review 的 CORE 清單為：記帳、Ledger、Account、Category、Merchant、Tag、Transfer、Split、Refund、多幣別、基本 FX、信用卡、基本分期、股票／ETF 投資核心、Budget、Recurring、Search、Reports、Security、Backup／Restore、Import／Export、Design System；加上 Provider interfaces、Module APIs、Capability registry、Migration framework。

OCR、發票、Google Calendar、Bills、Forecast、Goal、Loan、Insurance、Payroll、Shared Expense、Natural Language Search、Multi-device Sync 等保留為後續 Slice／Optional Capability。加入它們的目標是不用重做 Ledger、Account、Money、Time、Workspace、Repository 或 Migration；不是保證所有後續功能零 migration 或零成本。

歷史 Gate：整體方向 GO；直接 Freeze v0.9 NO-GO，理由是 scope 過度前置。rc1 用 CORE／EXTENSION-READY／OPTIONAL 區分範圍，再進最終 Freeze Review。本次文件未代替使用者宣布 Freeze；已核實的 review 決定與整理者細化提案仍須明確分開。來源完整不等於架構已 Freeze。

<a id="fv-079"></a>
## FV-079｜健康檢查與 Recovery

來源：S1 第 75 節「Health / Recovery」。  
當期對應：[RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。

### 保存的願景正文

Fast Health Check：

每次啟動。

Deep Check：

migration 後

restore 後

abnormal shutdown

manual diagnostics

檢查：

Ledger invariant

orphan

attachment

revision chain

projection

sync metadata

正式 Ledger 有問題：

進 Recovery Mode。

Recovery Center：

read-only

emergency backup

diagnostics

projection rebuild

snapshot compare

repair workflow

任何修改正式 Ledger 的 Repair：

需要使用者確認。

<a id="fv-080"></a>
## FV-080｜供應商中立的混合後端

來源：S1 第 76 節「Backend」。  
當期對應：[RC-23](architecture-baseline-v1.0-rc1.md#rc-23)。

### 保存的願景正文

採 Vendor-neutral Hybrid Backend。

V1 可利用例如：

Supabase Auth

Storage

metadata service

但核心只認：

Repository / Service Interface。

Domain 不依賴 Supabase / Firebase SDK。

未來可以換 Backend Adapter。

<a id="fv-081"></a>
## FV-081｜未來同步與衝突

來源：S1 第 77 節「Sync」。  
當期對應：[RC-20](architecture-baseline-v1.0-rc1.md#rc-20)。

### 保存的願景正文

V1：

Cloud Backup。

未來：

Multi-device Sync。

底層採：

Revision + Conflict Detection。

重要資料：

不採 Last Write Wins。

Conflict：

低風險自動 merge。

Financial data：

人工確認。

<a id="fv-082"></a>
## FV-082｜Secrets 分級

來源：S1 第 78 節「Secrets」。  
當期對應：[RC-23](architecture-baseline-v1.0-rc1.md#rc-23)。

### 保存的願景正文

Credential 分級：

User OAuth token
→ platform secure store

Public client identifier
→ app config

Private provider key
→ backend secret store

Server credential
→ server only

支援：

rotation

version

revocation

<a id="fv-083"></a>
## FV-083｜環境與 Runtime Config

來源：S1 第 79 節「Config」。  
當期對應：[RC-23](architecture-baseline-v1.0-rc1.md#rc-23)。

### 保存的願景正文

Build Flavor：

dev

staging

prod

Runtime Config：

只允許非敏感、可安全動態調整內容。

Config 必須：

versioned

signed

fallback defaults

<a id="fv-084"></a>
## FV-084｜Feature Capability

來源：S1 第 80 節「Feature Capability System」。  
當期對應：[RC-01](architecture-baseline-v1.0-rc1.md#rc-01)。

### 保存的願景正文

每個 Capability 可表示：

implemented

verified

enabled

environment

dependency

migration level

experimental

deprecated

這是控制「底層完整，但 UI 不一定顯示」的主要機制。

<a id="fv-085"></a>
## FV-085｜Design System

來源：S1 第 81 節「Design System」。  
當期對應：[RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

### 保存的願景正文

Material 3 作為底層。

上層建立自己的 Design System：

semantic color

typography

spacing

radius

elevation

input

button

sheet

dialog

list

chart

loading

empty

error

V1：

暖色 + 淺背景。

Dark Mode：

架構預留，UI 可晚一點開。

<a id="fv-086"></a>
## FV-086｜無障礙

來源：S1 第 82 節「Accessibility」。  
當期對應：[RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

### 保存的願景正文

高標準：

font scaling

touch target

screen-reader labels

non-color-only states

clear form error

reduced motion

contrast validation

<a id="fv-087"></a>
## FV-087｜國際化與格式

來源：S1 第 83 節「Localization」。  
當期對應：[RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

### 保存的願景正文

V1 UI：

繁體中文。

從第一天就採完整 i18n architecture。

支援：

locale

currency formatting

decimal precision

date/time

timezone

percentage

negative amount formatting

UI format 不影響 Ledger data。

<a id="fv-088"></a>
## FV-088｜表單與互動行為

來源：S1 第 84 節「UI Behavior」。  
當期對應：[RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

### 保存的願景正文

Empty State：

引導使用者下一步。

Form：

完整 Form State Engine。

UX：

即時但不打擾。

儲存後：

回到原來源 Context。

新交易：

預設乾淨表單。

「再記一筆類似交易」安全複製：

沿用：

account

category

merchant

tags

currency

不沿用：

amount

datetime

note

attachment

invoice

external ID

<a id="fv-089"></a>
## FV-089｜交易列表

來源：S1 第 85 節「Transaction List」。  
當期對應：[RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

### 保存的願景正文

按日期分組。

每一天顯示：

Income total

Expense total

Swipe：

只提供低風險操作。

高風險：

進 detail + confirmation。

<a id="fv-090"></a>
## FV-090｜交易詳情

來源：S1 第 86 節「Transaction Detail」。  
當期對應：[RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

### 保存的願景正文

預設顯示簡單資訊。

可以展開：

funding flow

split

fee / tax

FX

refund

reconciliation

Activity Timeline

不在一般 UI 顯示：

raw event ID

raw ledger leg ID

internal revision ID

這些只進 Diagnostics。

<a id="fv-091"></a>
## FV-091｜互動報表

來源：S1 第 87 節「Reports」。  
當期對應：[RC-13](architecture-baseline-v1.0-rc1.md#rc-13)。

### 保存的願景正文

支援互動 Drill-down。

例如：

Category
→ Subcategory
→ Transaction

Trend point
→ Period transactions

但 UI 不做 BI Builder。

<a id="fv-092"></a>
## FV-092｜效能

來源：S1 第 88 節「Performance」。  
當期對應：[RC-21](architecture-baseline-v1.0-rc1.md#rc-21)。

### 保存的願景正文

正式產品目標：

10～20 年資料。

至少支援：

100k+ transactions

大量 legs

revisions

market history

attachment metadata

壓力測試：

使用遠高於正常情境的資料量。

Performance Gate：

PR
→ smoke

main / nightly
→ full benchmark

release
→ full performance gate

監控：

query

memory

jank

background jobs

backup

restore

migration

analytics

<a id="fv-093"></a>
## FV-093｜查詢與索引治理

來源：S1 第 89 節「Query / Index Governance」。  
當期對應：[RC-21](architecture-baseline-v1.0-rc1.md#rc-21)。

### 保存的願景正文

不能遇到慢查詢就亂加 Index。

要有：

query pattern

query-plan benchmark

slow-query log

unused-index check

index-size monitoring

partial index

covering index

FTS governance

migration regression

<a id="fv-094"></a>
## FV-094｜資料遷移

來源：S1 第 90 節「Migration」。  
當期對應：[RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。

### 保存的願景正文

一般：

Transactional Migration。

重大：

Shadow / Copy Migration。

流程：

old DB
→ new schema
→ transform
→ invariant
→ checksum
→ verification
→ atomic switch

舊 DB 在驗證完成前不刪除。

<a id="fv-095"></a>
## FV-095｜測試

來源：S1 第 91 節「Testing」。  
當期對應：[RC-21](architecture-baseline-v1.0-rc1.md#rc-21)。

### 保存的願景正文

核心財務模組採接近 Financial-grade 的測試策略。

包含：

Unit

Widget

Integration

Repository Contract

Migration

Sync conflict

Import rollback

Regression

Property-based

Fuzz

random financial transaction generation

long-run simulation

determinism

disaster recovery

Ledger / Sync / Investment / Reconciliation：

最高強度。

一般 UI：

合理強度，不過度工程化。

<a id="fv-096"></a>
## FV-096｜診斷與錯誤回報

來源：S1 第 92 節「Diagnostics」。  
當期對應：[RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。

### 保存的願景正文

預設：

Local structured diagnostics。

包含：

module

operation

correlation ID

migration

sync

import

backup

slow query

禁止 log：

transaction amount

merchant

account name

raw note

OCR raw text

attachment content

Remote Crash Reporting：

Opt-in。

預設關閉。

<a id="fv-097"></a>
## FV-097｜更新與發版

來源：S1 第 93 節「Update / Release」。  
當期對應：[RC-24](architecture-baseline-v1.0-rc1.md#rc-24)。

### 保存的願景正文

完整 Update Channel：

version

build

channel

commit SHA

artifact checksum

minimum version

migration level

rollback marker

一般 UI 只顯示：

「目前版本」

以及必要時：

「最新版本」。

技術 metadata 放 Diagnostics。

<a id="fv-098"></a>
## FV-098｜平台邊界

來源：S1 第 94 節「Platform」。  
當期對應：[RC-23](architecture-baseline-v1.0-rc1.md#rc-23)。

### 保存的願景正文

V1：

Android first。

但核心不能綁 Android。

平台能力都透過 Interface：

SecureStorage

Biometrics

Calendar

Notifications

Update

Location

未來 iOS 補 Adapter。

<a id="fv-099"></a>
## FV-099｜Shortcut 與 Widget

來源：S1 第 95 節「Shortcut / Widget」。  
當期對應：[RC-25](architecture-baseline-v1.0-rc1.md#rc-25)。

### 保存的願景正文

Android Shortcut：

Add expense

Add income

Scan receipt

Open Inbox

Home Widget：

保持簡單。

遵守 Privacy Presentation Policy。

<a id="fv-100"></a>
## FV-100｜Action Link

來源：S1 第 96 節「Deep Link」。  
當期對應：[RC-25](architecture-baseline-v1.0-rc1.md#rc-25)。

### 保存的願景正文

所有外部入口共用 Action Link System。

支援：

open

review

resolve

confirm flow

Link 不放敏感資料。

任何會修改 Ledger 的 action：

必須進 App、驗證狀態、必要時解鎖並確認。

<a id="fv-101"></a>
## FV-101｜安全 Undo

來源：S1 第 97 節「Undo」。  
當期對應：[RC-25](architecture-baseline-v1.0-rc1.md#rc-25)。

### 保存的願景正文

低風險：

直接 Undo。

正式 Posted Financial Action：

使用 Revision / Reversal。

不提供假性的「歷史消失」。

<a id="fv-102"></a>
## FV-102｜風險分級確認

來源：S1 第 98 節「Risk-based Confirmation」。  
當期對應：[RC-25](architecture-baseline-v1.0-rc1.md#rc-25)。

### 保存的願景正文

Low：

直接執行 + Undo。

Medium：

確認一次。

High：

顯示 impact + 二次確認。

Critical：

PIN / Biometrics。

底層預留 Policy Engine。

<a id="fv-103"></a>
## FV-103｜核心 Source of Truth

來源：S1 第 99 節「核心 Source of Truth」。  
當期對應：[RC-13](architecture-baseline-v1.0-rc1.md#rc-13)。

### 保存的願景正文

必須一直遵守：

Ledger 是財務真相。

以下全部只是 derived data：

balance cache

snapshot

report

analytics

search index

forecast

projection

dashboard

market valuation

Derived Data：

可以刪掉重建。

Ledger：

不能靠 derived data 修回去。

<a id="fv-104"></a>
## FV-104｜Codex 架構契約

來源：S1 第 100 節「Codex Architecture Contract」。  
當期對應：[RC-24](architecture-baseline-v1.0-rc1.md#rc-24)。

### 保存的願景正文

Codex 可以：

Implement

Refactor within approved boundary

Add tests

Optimize

Fix bugs

Build UI against approved capability

Codex 不可以自行：

改 Ledger invariant

改 Domain boundary

改 schema strategy

改 monetary representation

改 sync semantics

改 security model

改 migration policy

讓 UI 直接存取 DB

把 business logic 塞進 Provider

讓外部 SDK 滲入 Domain

讓 hidden feature 以 stub 假裝完成

Architecture Change：

必須先有 ADR。

<a id="fv-105"></a>
## FV-105｜GitHub 開發治理

來源：S1 第 101 節「GitHub / Development Governance」。  
當期對應：[RC-24](architecture-baseline-v1.0-rc1.md#rc-24)。

### 保存的願景正文

全新 Repository。

開發模式：

main
+
feature / slice branches

要求：

PR

Acceptance Criteria

Tests

Architecture Gate

Migration Gate

Static Analysis

Security Check

exact commit SHA

release artifact traceability

禁止：

直接 push main。

Architecture Freeze 後：

Codex 只能依 Spec 開發。

<a id="fv-106"></a>
## FV-106｜實作順序

來源：S1 第 102 節「Implementation Strategy」。  
當期對應：[RC-22](architecture-baseline-v1.0-rc1.md#rc-22)。

### 保存的願景正文

實作不按照「畫面順序」。

而按照 Domain dependency。

概念順序：

Foundation
→ Money / Time / Identity
→ Ledger
→ Account / Category
→ Transaction
→ Projection
→ Search
→ Inbox / Matching
→ Credit Card / FX
→ Budget / Recurring
→ Investment
→ Backup / Migration
→ Sync preparation
→ Analytics
→ UI Surface

UI 可以早期建立 shell 與 Design System。

但：

畫面完成不等於 Domain 完成。

Domain Gate 通過後才能宣稱該 Capability 可用。

<a id="fv-107"></a>
## FV-107｜簡潔 UI 原則

來源：S1 第 103 節「V1 UI Philosophy」。  
當期對應：[RC-01](architecture-baseline-v1.0-rc1.md#rc-01)。

### 保存的願景正文

最重要的一句：

程式可以先寫完整，但 UI 先簡潔。現在不會用到的能力可以不顯示；底層只要被標示為已實作，就必須是正確且經測試的。進階能力未來可以透過 Capability 啟用，適合的資料、模型與平台模組則可按需下載載入。

因此 V2 不追求：

「把所有功能都塞到使用者眼前。」

而追求：

簡單的表面 + 嚴謹的底層。

<a id="fv-108"></a>
## FV-108｜Architecture Freeze Gate

來源：S1 第 104 節「Architecture Freeze 前最後 Gate」。  
當期對應：[RC-22](architecture-baseline-v1.0-rc1.md#rc-22)。

### 保存的願景正文

正式建立新 GitHub repo 並讓 Codex 大規模開發前，需要完成：

Architecture Consistency Review

Domain Boundary Review

Ledger Invariant Review

Data Model Review

Security / Privacy Review

Sync / Backup Review

Capability / Optional Module Review

UI Information Architecture Review

Over-engineering Review

Missing Requirement Review

Review 完成後：

建立：

Architecture Baseline Commit

記錄 exact SHA。

從這個 SHA 開始進入正式 Implementation Slices。

Baseline Statement

ExpenseTracker V2 是一個：

Local-first、Ledger-centric、offline-capable、modular、privacy-first、long-lived personal finance platform。

它可以具有很深的財務與資料能力，但不要求使用者承受相同程度的複雜度。

最終設計原則：

複雜度留在系統裡，簡單留給使用者。

<a id="question-register"></a>
## 原始 170 題決策登錄

**核對結果：170／170，有原題、有使用者答覆、有當期對應；無缺號、無以新增能力充當原題。** 下列定案文字屬 Full Vision；scope 標籤則是最新 review 與 rc1 的實作分期。提問中的其他 A／B／C／D 選項只是背景，不代表全部採用。

各題「定案說明」保留原對話文字與條件；Q148 按下一則編號校正後的結論整理。詳盡提問可展開查看，以免只記住選項字母而遺失所選能力。原文中的實作承諾若已被 review 減重，請以當期範圍連結為準。

- 001～010：[Q001](#q001) · [Q002](#q002) · [Q003](#q003) · [Q004](#q004) · [Q005](#q005) · [Q006](#q006) · [Q007](#q007) · [Q008](#q008) · [Q009](#q009) · [Q010](#q010)
- 011～020：[Q011](#q011) · [Q012](#q012) · [Q013](#q013) · [Q014](#q014) · [Q015](#q015) · [Q016](#q016) · [Q017](#q017) · [Q018](#q018) · [Q019](#q019) · [Q020](#q020)
- 021～030：[Q021](#q021) · [Q022](#q022) · [Q023](#q023) · [Q024](#q024) · [Q025](#q025) · [Q026](#q026) · [Q027](#q027) · [Q028](#q028) · [Q029](#q029) · [Q030](#q030)
- 031～040：[Q031](#q031) · [Q032](#q032) · [Q033](#q033) · [Q034](#q034) · [Q035](#q035) · [Q036](#q036) · [Q037](#q037) · [Q038](#q038) · [Q039](#q039) · [Q040](#q040)
- 041～050：[Q041](#q041) · [Q042](#q042) · [Q043](#q043) · [Q044](#q044) · [Q045](#q045) · [Q046](#q046) · [Q047](#q047) · [Q048](#q048) · [Q049](#q049) · [Q050](#q050)
- 051～060：[Q051](#q051) · [Q052](#q052) · [Q053](#q053) · [Q054](#q054) · [Q055](#q055) · [Q056](#q056) · [Q057](#q057) · [Q058](#q058) · [Q059](#q059) · [Q060](#q060)
- 061～070：[Q061](#q061) · [Q062](#q062) · [Q063](#q063) · [Q064](#q064) · [Q065](#q065) · [Q066](#q066) · [Q067](#q067) · [Q068](#q068) · [Q069](#q069) · [Q070](#q070)
- 071～080：[Q071](#q071) · [Q072](#q072) · [Q073](#q073) · [Q074](#q074) · [Q075](#q075) · [Q076](#q076) · [Q077](#q077) · [Q078](#q078) · [Q079](#q079) · [Q080](#q080)
- 081～090：[Q081](#q081) · [Q082](#q082) · [Q083](#q083) · [Q084](#q084) · [Q085](#q085) · [Q086](#q086) · [Q087](#q087) · [Q088](#q088) · [Q089](#q089) · [Q090](#q090)
- 091～100：[Q091](#q091) · [Q092](#q092) · [Q093](#q093) · [Q094](#q094) · [Q095](#q095) · [Q096](#q096) · [Q097](#q097) · [Q098](#q098) · [Q099](#q099) · [Q100](#q100)
- 101～110：[Q101](#q101) · [Q102](#q102) · [Q103](#q103) · [Q104](#q104) · [Q105](#q105) · [Q106](#q106) · [Q107](#q107) · [Q108](#q108) · [Q109](#q109) · [Q110](#q110)
- 111～120：[Q111](#q111) · [Q112](#q112) · [Q113](#q113) · [Q114](#q114) · [Q115](#q115) · [Q116](#q116) · [Q117](#q117) · [Q118](#q118) · [Q119](#q119) · [Q120](#q120)
- 121～130：[Q121](#q121) · [Q122](#q122) · [Q123](#q123) · [Q124](#q124) · [Q125](#q125) · [Q126](#q126) · [Q127](#q127) · [Q128](#q128) · [Q129](#q129) · [Q130](#q130)
- 131～140：[Q131](#q131) · [Q132](#q132) · [Q133](#q133) · [Q134](#q134) · [Q135](#q135) · [Q136](#q136) · [Q137](#q137) · [Q138](#q138) · [Q139](#q139) · [Q140](#q140)
- 141～150：[Q141](#q141) · [Q142](#q142) · [Q143](#q143) · [Q144](#q144) · [Q145](#q145) · [Q146](#q146) · [Q147](#q147) · [Q148](#q148) · [Q149](#q149) · [Q150](#q150)
- 151～160：[Q151](#q151) · [Q152](#q152) · [Q153](#q153) · [Q154](#q154) · [Q155](#q155) · [Q156](#q156) · [Q157](#q157) · [Q158](#q158) · [Q159](#q159) · [Q160](#q160)
- 161～170：[Q161](#q161) · [Q162](#q162) · [Q163](#q163) · [Q164](#q164) · [Q165](#q165) · [Q166](#q166) · [Q167](#q167) · [Q168](#q168) · [Q169](#q169) · [Q170](#q170)

<a id="q001"></a>
### Q001｜完整個人財務產品定位

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-003](#fv-003)。  
**rc1 契約：** [RC-01](architecture-baseline-v1.0-rc1.md#rc-01)。

好，那就定案：V1 直接做完整個人財務 App，包含投資／股票模組。

但我會要求架構上把「日常帳務」和「投資資產」拆成不同 domain，不要把股票交易硬塞進一般收支 Transaction。這樣未來要加股息、損益、持倉、成本、即時報價時，不會污染核心記帳模型。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q001 原題與選項（來源上下文）</summary>

第一題先定義 新版記帳 App V1 的產品定位，這會直接決定資料模型和架構複雜度：

A｜純記帳核心版：收支、帳戶、分類、轉帳、搜尋、基本報表。預算、定期、匯率、股票之後再加。
B｜完整個人財務版：收支＋帳戶＋分類＋轉帳＋搜尋＋報表＋預算＋定期收支＋多幣別／匯率；股票投資先預留架構，V1 後段或 V1.1 再做。
C｜一次完整做完：B 的全部，再加股票／投資資產、投資績效與資產總覽，V1 就涵蓋所有主要功能。
D｜自訂：你直接告訴我哪些一定要 V1。

我目前比較傾向 B：它已經會是一個完整、真正能長期使用的記帳 App，但不會讓股票資料源與投資模型在一開始就把核心帳務架構搞得太重。這次又是重開 repo，很適合先把「日常財務核心」做好，再把投資做成獨立 domain 接進來。

你先選 A / B / C / D。

</details>

<a id="q002"></a>
### Q002｜Local-first 與雲端備份

**使用者原答：** 先B然後預留C的方向  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-052](#fv-052)、[FV-075](#fv-075)。  
**rc1 契約：** [RC-14](architecture-baseline-v1.0-rc1.md#rc-14)、[RC-20](architecture-baseline-v1.0-rc1.md#rc-20)。

很好，這個方向我也認同。先把決策固定成：

V1：Local-first + 雲端備份／還原
未來：可升級成真正的多裝置同步

因此我們現在就會預留 UUID、createdAt / updatedAt、刪除狀態、資料版本等同步需要的資訊，但 V1 不先背 conflict resolution 與 sync engine 的複雜度。

下一題非常重要，會直接決定整個資料庫核心。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q002 原題與選項（來源上下文）</summary>

接下來第二題，而且這題會直接影響資料庫、備份、登入與未來同步架構：

你希望資料主要放在哪裡？

A｜完全本機

所有記帳資料只存在手機
可手動備份／還原
不需要登入
架構最單純
換手機要自己搬資料

B｜本機優先＋雲端備份

平常完全使用本機 DB
App 不依賴網路也能正常使用
可選擇登入後備份到雲端
換手機可以恢復資料
暫時不做多裝置即時同步

C｜本機優先＋完整多裝置同步

手機本機仍有完整資料
登入後可跨手機／平板同步
離線修改後重新上線自動合併
要處理 conflict、sync state、server schema
架構最完整，但也是最複雜

我的建議是 B。

我們可以從第一天就把資料模型設計成未來能升級到 C，但 V1 不急著做真正的雙向即時同步。對自用記帳 App 來說，離線穩定＋資料不會因換手機消失通常比「兩台裝置同時編輯」更重要。

你選 A / B / C。

</details>

<a id="q003"></a>
### Q003｜高標準 Ledger

**使用者原答：** 可以那就用B然後標準高  
**當期範圍：** CORE。  
**願景主題：** [FV-007](#fv-007)。  
**rc1 契約：** [RC-03](architecture-baseline-v1.0-rc1.md#rc-03)。

那我們就正式定成：

高標準 Ledger 架構
不是完整會計軟體，但底層要做到接近會計系統等級的可靠性。

我會把幾個原則直接列成之後 Codex 不能破壞的 invariant：一筆交易可以有多個資金異動；轉帳不能靠兩筆互不相干的紀錄拼湊；餘額必須能從 ledger 重建；退款、手續費、信用卡、投資現金流都要能追溯；不能直接偷偷改帳戶餘額；所有調整都必須留下明確事件。這樣之後就算報表或 UI 出 bug，底層帳還是能核對回來。

接著下一題會影響非常大：

補充：使用者曾比較 B／C，最後明確採高標準 B；不強制完整正式會計科目體系。資金流一致性與可重建性仍不可放寬。

<details>
<summary>Q003 原題與選項（來源上下文）</summary>

第 3 題｜帳務底層要怎麼設計？

A｜簡單記帳模型

每筆紀錄就是：
收入 / 支出 + 金額 + 帳戶 + 分類

轉帳另外特別處理。

優點是簡單，但之後信用卡、退款、投資、跨帳戶操作容易開始出現例外。

B｜Ledger 帳本模型，我推薦這個

使用者看到的還是很直覺：

早餐 $80
現金 → 餐飲

但資料庫底層是一個「交易事件 + 多個資金異動」。

例如從銀行轉 $5,000 到現金：

純文字
Transaction
├─ 銀行帳戶   -5,000
└─ 現金帳戶   +5,000

信用卡消費：

純文字
Transaction
├─ 餐飲支出   +800
└─ 信用卡負債 +800

之後付款：

純文字
銀行帳戶   -800
信用卡負債 -800

這樣退款、轉帳、信用卡、股票、手續費、多幣別都比較自然。

C｜完整會計雙式簿記

資產、負債、收入、費用、權益全部按照正式會計原則處理，每筆借貸平衡。

架構最嚴謹，但對個人記帳 App 會增加不少不必要的產品複雜度。

我的選擇：B

底層具有接近雙式帳本的可靠性，但介面完全不要讓你看到「借方／貸方」這些會計概念。

這也很適合我們 V1 要直接做信用卡、股票、轉帳、多幣別的方向。

你選 A / B / C。

</details>

<a id="q004"></a>
### Q004｜帳戶類型與擴充

**使用者原答：** 選B留C的可能性  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-010](#fv-010)。  
**rc1 契約：** [RC-05](architecture-baseline-v1.0-rc1.md#rc-05)。

好，這題也定案：

V1 用完整預設帳戶類型，底層預留未來自訂 Account Type。

也就是使用者先不用處理太多自由設定，但資料模型不能把帳戶類型寫死到未來難以擴充。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q004 原題與選項（來源上下文）</summary>

第 4 題｜帳戶類型要做到多完整？

A｜基本帳戶
只有：

現金
銀行
信用卡
投資帳戶

簡單，但未來資產總覽會比較受限。

B｜完整個人資產帳戶，我推薦
包含：

現金
銀行／數位帳戶
信用卡
電子支付／電子錢包
投資帳戶
儲值帳戶
其他資產
其他負債
可設定「是否計入總資產」

例如悠遊卡、LINE Pay 餘額、借給別人的錢、貸款，都可以正確放進去。

C｜完全自訂 Account Type
除了系統預設類型外，使用者可以建立自己的帳戶類型。

自由度最高，但會讓報表、圖示、排序、資產／負債判定和同步規則複雜很多。

我建議 B，而且底層預留擴充能力，但 V1 不開放任意自訂 Account Type。

你選 A / B / C。

</details>

<a id="q005"></a>
### Q005｜雙層分類

**使用者原答：** 雙層分類就好  
**當期範圍：** CORE。  
**願景主題：** [FV-011](#fv-011)。  
**rc1 契約：** [RC-05](architecture-baseline-v1.0-rc1.md#rc-05)。

好，那就定死 雙層分類，不特別為無限層級增加複雜度。

也就是 V1 結構固定：

純文字
大分類
└─ 子分類

例如：

純文字
餐飲
├─ 早餐
├─ 午餐
└─ 飲料

而且我會建議收入、支出分類在產品上分開管理，避免新增交易時混在一起。

下一題會直接影響 Ledger 模型本身。

<details>
<summary>Q005 原題與選項（來源上下文）</summary>

接著第 5 題，我想先定 分類 Category 的結構，因為它會直接影響新增交易、預算、報表與統計。

第 5 題｜分類要做到幾層？

A｜單層分類
例如：

餐飲
交通
娛樂
薪資

最簡單，但報表比較粗。

B｜兩層分類，我比較推薦
例如：

純文字
餐飲
├─ 早餐
├─ 午餐
├─ 晚餐
└─ 飲料

交通
├─ 捷運
├─ 計程車
└─ 加油

預算可以設在：

餐飲整體
或某個子分類

報表也可以：

看大類
再展開看細項

對手機操作還算好控制。

C｜無限層級分類
例如：

純文字
生活
└─ 飲食
   └─ 外食
      └─ 午餐

彈性最高，但 UI、預算繼承、報表 aggregation、拖曳排序都會複雜很多。

我的建議是 B，而且資料結構預留 C。

也就是 V1 UI 最多讓你建立：

純文字
Parent Category
└─ Subcategory

但 DB 不要用「固定 parent/child 兩張表」這種寫死方法，而是設計成將來能擴成 tree。

另外我會建議 收入分類和支出分類分開，不要讓「薪資」跟「餐飲」混在同一個選單。

你選 A / B / C。

</details>

<a id="q006"></a>
### Q006｜拆分類與未來多帳戶付款

**使用者原答：** B，但我想預留多帳戶付款或者是刷退之類的  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-016](#fv-016)。  
**rc1 契約：** [RC-03](architecture-baseline-v1.0-rc1.md#rc-03)。

可以，這個我會視為重要架構約束，而不是「之後再想」。

所以第 6 題正式定成：V1 UI 採 B，但底層 Ledger 要能原生支援多帳戶付款、部分刷退、全額刷退、折抵與其他多腿交易。 也就是現在先不把複雜操作全部露給使用者，但資料模型不能限制死。

例如未來一筆 2,000 元消費，可以表示成：

純文字
信用卡 A     1,200
現金           800

餐飲         1,500
日用品         500

刷退 600 元時，也不會把原交易直接改掉，而是新增一個可追溯到原交易的退款事件。這樣報表、帳戶餘額、歷史紀錄和稽核都不會亂。這點我會列成 Codex 之後不能破壞的 invariant。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q006 原題與選項（來源上下文）</summary>

第 6 題｜一筆交易要不要支援「拆分分類」？

例如你去 Costco 刷卡 2,300 元：

純文字
總金額 2,300

食品      1,500
日用品      500
娛樂        300

A｜不支援拆分

一筆交易只能選一個分類。

優點是操作最簡單，但這種混合消費只能自己拆成三筆交易。

B｜支援拆分交易，我推薦

平常新增交易還是一個分類，只有需要時才按「拆分」。

底層可以表示：

純文字
信用卡      +2,300 負債

食品支出     1,500
日用品支出     500
娛樂支出       300

這會和我們選的高標準 Ledger 架構非常契合，而且之後報表與預算都會更準。

C｜進一步支援複雜拆分

除了分類拆分，還可以同一筆交易：

多帳戶付款
多幣別
部分現金＋部分信用卡
部分退款／折抵

功能最完整，但新增畫面也會複雜不少。

我建議 B，底層 Ledger 本來就能承受更複雜的多腿交易，但 V1 UI 先只開放「一個付款帳戶＋多個分類拆分」。

你選 A / B / C。

</details>

<a id="q007"></a>
### Q007｜信用卡與分期 Domain

**使用者原答：** 可以選C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-017](#fv-017)、[FV-018](#fv-018)。  
**rc1 契約：** [RC-07](architecture-baseline-v1.0-rc1.md#rc-07)。

好，那信用卡就直接採 C：完整信用卡＋分期模型。我會把它當成正式 domain，不會只把信用卡視為「負數帳戶」。

V1 會涵蓋結帳日、繳款截止日、信用額度、本期帳單、未出帳、已繳／未繳，以及單筆分期與帳單分期；資料模型也會預留利息、手續費、剩餘期數與提前清償。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q007 原題與選項（來源上下文）</summary>

接下來第 7 題我想定 信用卡怎麼處理，因為這會直接影響負債、帳單和繳款模型。

A｜把信用卡當一般帳戶
刷卡就是增加信用卡餘額，繳款就是轉帳。最簡單，但沒有帳單週期、結帳日、繳款截止日。

B｜完整信用卡模型，我推薦
每張卡可設定：

結帳日
繳款截止日
信用額度
本期帳單
未出帳金額
已繳／未繳
自動建立繳款提醒或建議交易

底層仍然是 Ledger，只是多一層 CreditCard domain。

C｜完整信用卡＋分期
除了 B，再加：

單筆分期
帳單分期
每期本金／利息
提前清償
分期剩餘期數

我會選 C，因為既然我們這次 V1 就要做完整個人財務 App，分期其實很常見，而且現在不先把資料模型想好，之後補會比較痛。

你選 A / B / C。

</details>

<a id="q008"></a>
### Q008｜完整多幣別 Ledger

**使用者原答：** 選C  
**當期範圍：** CORE。  
**願景主題：** [FV-019](#fv-019)、[FV-020](#fv-020)。  
**rc1 契約：** [RC-04](architecture-baseline-v1.0-rc1.md#rc-04)。

好，那多幣別就正式採 C：完整多幣別 Ledger。

這代表之後像換匯、海外刷卡、美股買賣，都可以用同一套底層模型處理，而且歷史交易永遠保留當下實際匯率與原始幣別，不會因為今天匯率變動就回頭改歷史紀錄。

下一題我想直接定 投資模組的範圍，因為你選的是完整 V1，這塊要先講清楚。

<details>
<summary>Q008 原題與選項（來源上下文）</summary>

接下來第 8 題，我想定 多幣別與匯率，因為這會同時影響帳戶、交易、報表、股票與總資產。

A｜單一基準幣別
所有帳戶與交易都以 TWD 為主，匯率只當查詢工具。

B｜帳戶可有不同幣別，我推薦
例如：

台幣帳戶：TWD
美金帳戶：USD
日圓現金：JPY
美股投資帳戶：USD

每筆交易保留原始幣別與金額；報表再換算成「主要顯示幣別」。

C｜完整多幣別 Ledger
除了 B，再讓單筆交易本身可同時含不同幣別，例如換匯：

純文字
TWD 帳戶   -32,500 TWD
USD 帳戶    +1,000 USD
手續費         100 TWD

而且會保存當下實際成交匯率，不用之後的新匯率回頭改變歷史交易。

我會推薦 C。
因為我們已經確定要做股票、完整資產與高標準 Ledger，多幣別如果只做到 B，之後真正換匯時還是會遇到模型限制。

你選 A / B / C。

</details>

<a id="q009"></a>
### Q009｜投資完整願景與漸進 UI

**使用者原答：** 可以C先做後續需要顯示再接UI  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-022](#fv-022)、[FV-024](#fv-024)、[FV-025](#fv-025)。  
**rc1 契約：** [RC-08](architecture-baseline-v1.0-rc1.md#rc-08)。

可以，這樣最穩。

投資模組我們就採 C 的完整 domain model，但 UI 採漸進式開放：先把資料模型、計算邏輯、公司行動、跨券商持倉、績效算法這些底層能力做好，V1 畫面只先接你真正會用到的功能，後面再逐步顯示，不需要為了加 UI 去改 schema。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q009 原題與選項（來源上下文）</summary>

第 9 題｜投資模組要做到哪一層？

A｜只有持倉追蹤

股票名稱／代號
持有股數
平均成本
現價
未實現損益

比較像資產看板。

B｜完整投資交易，我推薦
除了 A，再支援：

買進
賣出
股息
手續費
稅
現金帳戶連動
已實現／未實現損益
多幣別
歷史交易
成本基礎

C｜完整投資組合系統
除了 B，再加入：

股票分割
合股
配股
現金增資
股利再投資
公司行動 Corporate Actions
多券商
同一股票跨帳戶持有
更完整的績效分析，例如 TWR / XIRR

我會建議 C，但分階段實作。
原因是這些 Corporate Actions 如果資料模型一開始沒預留，之後補進去通常很痛；但 UI 不需要一開始全部做得很重。

你選 A / B / C。

</details>

<a id="q010"></a>
### Q010｜Budget Rule Engine

**使用者原答：** 可以選C但一開始UI可以不那麼複雜  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-027](#fv-027)。  
**rc1 契約：** [RC-09](architecture-baseline-v1.0-rc1.md#rc-09)。

好，預算就定成 C：完整 Budget Rule Engine，UI 先保持簡單。這樣底層能力先做到位，但不會讓 V1 一打開就是一堆進階設定。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q010 原題與選項（來源上下文）</summary>

接下來第 10 題，我想定 預算系統，因為它會和分類、帳戶、定期交易、報表全部連在一起。

第 10 題｜預算要做到哪個層級？

A｜只有每月分類預算
例如：

餐飲 8,000
交通 3,000

最簡單。

B｜彈性預算
除了分類，也可以：

對大分類設預算
對子分類設預算
對特定帳戶設預算
自訂週期：每週／每月／每年
未用完可選擇是否累積到下期

C｜完整預算規則系統，我推薦
除了 B，再加入：

多條件預算，例如「信用卡＋餐飲」
排除特定交易
一次性預算
專案型預算，例如「日本旅遊 50,000」
共用／重疊規則的優先順序
預算警戒線，例如 50% / 80% / 100%

我會建議 C，但 UI 一開始保持簡單。

因為我們前面已經決定底層要高標準，如果 Budget model 一開始只綁 categoryId + month，之後很快會撞牆。

你選 A / B / C。

</details>

<a id="q011"></a>
### Q011｜Recurring／Automation

**使用者原答：** 可以C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-028](#fv-028)。  
**rc1 契約：** [RC-09](architecture-baseline-v1.0-rc1.md#rc-09)。

好，那定期交易也採 C：底層做完整規則引擎，UI 先簡化。

也就是架構上先支援浮動金額、信用卡帳單連動、依前期金額、假日順延／提前、多步驟流程與未來外部事件觸發；但 V1 使用者先只看到最常用的「每週／每月／每年、自動建立或提醒確認」這種介面。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q011 原題與選項（來源上下文）</summary>

接著第 11 題我想定 定期交易 / 自動記帳，因為它會影響排程、通知、交易產生規則與未來同步。

第 11 題｜定期交易要做到哪種程度？

A｜基本定期
例如每月 5 號：

房租 15,000
Netflix 390
薪資 50,000

到期時自動建立交易。

B｜完整 recurring rule，我推薦
除了 A，再支援：

每天／每週／每月／每年
每 N 天／週／月
月底
指定星期
起始日／結束日
固定次數
金額可在建立前修改
自動建立或先提醒確認

C｜完整排程＋條件式
除了 B，再支援：

浮動金額，例如信用卡帳單
根據上一期金額
與預算／帳單連動
因假日提前或延後
多步驟，例如先建立帳單，再於截止日建立付款
未來可能接銀行通知或外部事件觸發

我建議 C 的底層能力，但 V1 UI 先做 B。

也就是一開始使用者看到的是正常的「每月、每週、自動／提醒」設定，但 scheduler / rule model 不要只寫成簡單日期欄位，之後才有辦法支援信用卡帳單和更複雜的自動化。

你選 A / B / C。

</details>

<a id="q012"></a>
### Q012｜分析引擎與一般報表

**使用者原答：** 好C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-049](#fv-049)。  
**rc1 契約：** [RC-13](architecture-baseline-v1.0-rc1.md#rc-13)。

好，那報表就採 C：底層是完整分析引擎，V1 UI 維持一般使用者容易理解的樣子。

這樣首頁與「報表」頁可以先呈現收入／支出、分類占比、現金流、淨資產、預算達成率、年度趨勢等常用資訊，但底層查詢已經能支援帳戶、分類、標籤、商家、幣別、交易類型等組合篩選。之後要加自訂報表或 dashboard，不用重寫資料層。

接下來我想討論一個很容易被低估，但會直接影響日常記帳體驗的部分。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q012 原題與選項（來源上下文）</summary>

接下來第 12 題，我想定 報表與分析系統的層級。這會影響資料 aggregation、cache、查詢效能，還有首頁到底能做到多有用。

第 12 題｜報表要做到哪一層？

A｜基本報表

每月收入／支出
分類占比
帳戶餘額
月份比較

夠用，但比較像一般記帳 App。

B｜完整個人財務分析
除了 A，再有：

淨資產趨勢
現金流
預算執行率
固定支出 vs 浮動支出
商家／分類／帳戶排行
年度趨勢
多幣別換算後分析
投資資產與日常財務分開看

C｜分析引擎
除了 B，再把底層設計成可組合分析，例如：

純文字
時間範圍
+ 帳戶
+ 分類
+ 幣別
+ 商家
+ 標籤
+ 交易類型

之後可以做像：

過去一年
信用卡消費
排除旅遊
只看餐飲
按月份比較

也可以支援：

自訂 dashboard
自訂報表
儲存篩選條件
drill-down 到原始交易
未來新增更多圖表而不用重寫資料層

我推薦 C，但 V1 UI 先做 B 的樣子。

底層先有一致的 analytics/query model，畫面先不要做成像 BI 工具那麼複雜。

你選 A / B / C。

</details>

<a id="q013"></a>
### Q013｜交易資訊與正式 Merchant

**使用者原答：** 先B  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-013](#fv-013)、[FV-012](#fv-012)。  
**rc1 契約：** [RC-03](architecture-baseline-v1.0-rc1.md#rc-03)、[RC-05](architecture-baseline-v1.0-rc1.md#rc-05)、[RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。

好，那交易資訊先採 B，不做自訂欄位系統。商家會做成獨立 entity，這樣未來可以支援常用分類建議、搜尋與分析，而不是只存一段文字。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q013 原題與選項（來源上下文）</summary>

第 13 題｜交易資訊要豐富到什麼程度？

A｜基本交易

金額
日期
帳戶
分類
備註

B｜完整交易資訊
除了 A，再支援：

商家
標籤
照片／收據
地點（可選）
手續費
付款方式資訊
自訂備註
附件

C｜B＋自訂欄位系統
例如使用者可以自行新增：

發票號碼
訂單編號
報帳狀態
同行者
專案
其他自訂欄位

彈性非常高，但 UI 與搜尋／同步／報表都會再複雜不少。

我目前比較推薦 B，然後其中「標籤」可以拿來解決很多 C 才需要的需求。像「日本旅遊」、「公司報帳」、「裝潢」都可以直接用 Tag，不一定需要自訂欄位系統。

另外商家我會建議做成真正的 Merchant entity，而不是純文字，這樣之後可以自動記住：

全聯 → 日用品
中油 → 加油
Netflix → 娛樂

甚至慢慢做出記帳建議。

你選 A / B / C。

</details>

<a id="q014"></a>
### Q014｜強化且保持平面的 Tag

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-011](#fv-011)。  
**rc1 契約：** [RC-05](architecture-baseline-v1.0-rc1.md#rc-05)。

好，Tag 採 B：強化但保持單純。它可以進搜尋、報表、預算與定期交易規則，但不會變成另一套分類系統。

接下來這題很重要，因為我們已經決定 Ledger 要做高標準。

<details>
<summary>Q014 原題與選項（來源上下文）</summary>

接下來第 14 題，我想定 標籤 Tag 的角色，因為它很容易和分類、專案、預算重疊。

第 14 題｜Tag 要做到哪種程度？

A｜單純標籤
例如：

日本旅遊
公司報帳
約會
搬家

一筆交易可有多個 Tag，只用於搜尋與篩選。

B｜強化 Tag，我推薦
除了 A，再支援：

顏色／圖示
多選
報表分析
預算規則可引用 Tag
定期交易可自動帶入 Tag
投資／帳務事件都可使用

但 Tag 不負責層級分類，也不做太複雜的規則。

C｜Tag 變成通用屬性系統
可以有群組、層級、互斥、規則、必填等。

功能很強，但很容易和 Category／Project／Custom Field 混在一起。

我建議 B。
Category 回答「這筆錢是什麼」，Tag 回答「這筆錢屬於什麼情境」。

例如：

純文字
分類：餐飲 > 晚餐
Tag：日本旅遊、朋友聚餐

你選 A / B / C。

</details>

<a id="q015"></a>
### Q015｜Revision 與 soft delete

**使用者原答：** 可以B高標準，但這樣會不會造成資料龐大  
**當期範圍：** CORE。  
**願景主題：** [FV-008](#fv-008)。  
**rc1 契約：** [RC-03](architecture-baseline-v1.0-rc1.md#rc-03)。

不太會。真正容易把資料撐大的不是 revision history，而是照片／收據附件。

假設你一天記 10 筆，一年大約 3,650 筆；就算用 20 年，也才 73,000 筆。每筆再加幾個 ledger legs、revision、tag 關聯，對 SQLite 這種本機資料庫來說都還是很小的量。

我們可以把高標準 B 做得很節制：

一般交易只保留「目前版本 + revision metadata」，revision 只記真正改過的欄位與變更時間，不複製整包附件。
deleted 只留 tombstone 與必要 metadata，不會整筆資料再複製一份。
報表 cache、統計結果這種衍生資料可以重建，不需要永久保存。
收據照片另外管理，這才是主要容量來源；可以做壓縮、縮圖、原圖是否保留、雲端備份等策略。
未來同步需要的 tombstone / revision 也可以做 compact，但不要破壞可追溯性。

實際上，即使累積很多年，純文字＋數字＋關聯資料通常還是在幾十 MB 到低百 MB 等級；反而一張手機照片就可能 2～8 MB。只要收據附件策略做好，資料庫本身完全不是問題。

所以第 15 題我會正式定成：

B 高標準版

一般修改：revision history
一般刪除：soft delete / tombstone
刷退、退款、沖銷、投資取消：正式 reversal / adjustment event
附件不跟 revision 重複儲存
derived data 可重建

這個方向很適合我們未來要預留 C 的多裝置同步。

<details>
<summary>Q015 原題與選項（來源上下文）</summary>

第 15 題｜交易「修改／刪除」後，歷史要怎麼處理？

A｜直接修改資料

例如原本早餐 $80，改成 $100，就直接把資料庫裡的 80 改成 100。

最簡單，但：

不知道以前是多少
很難追查餘額異常
同步時也比較容易衝突

B｜保留 Revision History，我推薦

你在 UI 上一樣只是按「編輯」。

但底層保留：

純文字
原始交易
↓
Revision 1
↓
Revision 2

例如：

純文字
10/1 早餐 $80
→ 改成 $100
→ 分類從早餐改成午餐

系統知道整個修改歷史。

刪除也不是直接消失，而是：

純文字
deletedAt
deletion reason / metadata

一般畫面不顯示，但資料可以稽核、恢復，未來同步也比較安全。

C｜完全 Immutable Event Ledger

任何資料都永遠不能修改。

改 $80 → $100 時，實際上會：

純文字
Reverse 原交易 -80
新增新交易 +100

正式金融系統很常見，非常嚴謹。

但個人記帳 App 會產生很多技術事件，而且編輯、報表、同步邏輯都更重。

我建議：B，但吸收 C 的優點

也就是：

使用者體驗

正常修改、刪除即可。

底層

所有重要變更有 revision / audit trail。

而像：

刷退
退款
信用卡沖銷
股票交易取消
已結帳帳單修正

這些真正有財務意義的動作，則不能偷偷覆寫原紀錄，要建立 reversal / adjustment event。

這樣會比純 B 更可靠，又不像 C 那麼重。

你選 A / B / C；我會比較推薦 B（高標準版）。

</details>

<a id="q016"></a>
### Q016｜OCR 輔助記帳

**使用者原答：** 好選B  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-031](#fv-031)。  
**rc1 契約：** [RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。

好，第 16 題定案：B｜OCR 輔助記帳。

原則也一起固定：OCR 只是「幫你填表單」，不會直接寫進 Ledger。商家、金額、日期、發票／收據號碼等都先辨識，再由你確認後入帳。未來如果要升級成品項辨識、自動拆分分類、重複交易偵測，也不需要重做核心架構。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q016 原題與選項（來源上下文）</summary>

可以。第 16 題我們就定 收據／附件能力：

A｜只做附件保存

拍照或從相簿選圖
可附 PDF／圖片
顯示縮圖
不做 OCR
最穩、最簡單

B｜OCR 輔助記帳，我推薦
除了 A，再支援：

辨識金額
日期
商家名稱
發票／收據號碼
自動帶入新增交易表單
使用者確認後才入帳

重點是「OCR 只幫忙填，不自動決定交易內容」，避免辨識錯誤直接污染帳本。

C｜智慧收據系統
除了 B，再做：

自動辨識品項
嘗試分類品項
一張收據自動拆分分類
推測付款方式
找重複交易
學習商家與分類習慣

功能最強，但辨識品質、模型／API 成本、隱私與離線能力都會變成正式架構議題。

我的建議是 B，底層預留 C。這樣 V1 已經很實用，但不用一開始就把 AI 辨識做成關鍵依賴。

你選 A / B / C。

</details>

<a id="q017"></a>
### Q017｜進階搜尋與自然語言預留

**使用者原答：** 可以B預留C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-048](#fv-048)。  
**rc1 契約：** [RC-10](architecture-baseline-v1.0-rc1.md#rc-10)。

好，第 17 題定案：B｜進階搜尋，預留 C｜自然語言搜尋。

之後如果加「去年用信用卡吃飯超過 1,000 元」這種搜尋，我們會讓它只是把自然語言轉成既有的 structured filters，而不是另外做一套搜尋系統。這樣搜尋、報表、預算規則可以共用同一個條件模型。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q017 原題與選項（來源上下文）</summary>

接著第 17 題，我想定 搜尋與交易查找能力。這會影響索引、資料庫結構和報表共用的查詢層。

A｜基本搜尋

備註
商家
分類
日期
金額

B｜進階搜尋，我推薦
除了 A，再支援：

多條件組合
帳戶
Tag
幣別
收入／支出／轉帳
有無附件
金額區間
已刪除／退款／刷退狀態
儲存常用篩選

C｜搜尋語法／智慧搜尋
例如直接輸入：

去年用信用卡吃飯超過 1000 的紀錄

或：

日本旅遊但不是餐飲

系統解析成條件搜尋。

我建議 B，底層預留 C。
因為我們前面已經有完整 analytics/query engine，其實搜尋最好直接共用同一套條件模型，不要另外再做一套。

你選 A / B / C。

</details>

<a id="q018"></a>
### Q018｜版本化雲端備份與未來同步準備

**使用者原答：** 好C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-052](#fv-052)、[FV-075](#fv-075)。  
**rc1 契約：** [RC-14](architecture-baseline-v1.0-rc1.md#rc-14)、[RC-20](architecture-baseline-v1.0-rc1.md#rc-20)。

好，第 18 題定案：底層採 C，V1 體驗維持 B。

也就是雲端不只是丟一包備份檔，而是從一開始就有版本、加密、完整性檢查、revision、tombstone、附件與 sync metadata 的概念；但你實際看到的介面先保持簡單，只需要「自動備份、歷史版本、最後備份時間、還原」。這會讓未來真正升級多裝置同步時，不需要推翻整套備份架構。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q018 原題與選項（來源上下文）</summary>

接著第 18 題，我覺得該把我們前面選的 Local-first＋雲端備份具體化。

第 18 題｜雲端備份要怎麼設計？

A｜單純整包備份

把本機資料庫＋附件打包
手動備份
手動還原
可以放 Google Drive / 自選位置

最簡單，但每次都是整包。

B｜版本化備份，我推薦
除了 A，再加入：

自動定期備份
保留多個歷史版本
備份前完整性檢查
加密
可選只還原某個備份版本
App 內顯示最後成功備份時間
新手機登入後可選版本還原

仍然不是多裝置同步，但可靠度高很多。

C｜增量雲端資料層
除了 B，再把雲端資料拆成：

transaction revisions
tombstones
attachments
sync metadata

雖然 V1 還不開真正多裝置同步，但其實雲端底層已經接近未來 Sync Engine。

我的建議是 C 的資料格式與架構，V1 使用體驗維持 B。

也就是你看到的只是：

自動備份
最近備份
歷史版本
還原

但底層不要只丟一個 backup.zip 就結束，這樣未來升級多裝置同步會輕鬆非常多。

你選 A / B / C。

</details>

<a id="q019"></a>
### Q019｜登入選配

**使用者原答：** 選B  
**當期範圍：** CORE。  
**願景主題：** [FV-052](#fv-052)、[FV-056](#fv-056)。  
**rc1 契約：** [RC-14](architecture-baseline-v1.0-rc1.md#rc-14)、[RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。

好，第 19 題定案：B｜登入選配。

也就是不登入也能完整使用記帳功能；只有要開啟雲端備份、還原，以及未來同步時才需要身份驗證。登入系統會跟帳本 ownership 解耦，避免日後更換 Google／Apple／Email 登入方式時動到核心財務資料。

<details>
<summary>Q019 原題與選項（來源上下文）</summary>

接著第 19 題，我建議開始定 登入／身份系統，因為我們已經有雲端備份了。

A｜完全不登入

App 本機直接用
備份靠使用者自己選檔案位置
最省事
但之後跨裝置、雲端還原比較麻煩

B｜登入是選配，我推薦

不登入也能完整記帳
想開啟雲端備份時再登入
可支援 Google / Apple / Email 等方式
本機帳本不依賴登入狀態
登出也不會讓本機資料消失

C｜強制登入

第一次開 App 就要有帳號
雲端管理最一致
但對自用記帳 App 來說摩擦比較大，而且違反我們前面 local-first 的精神

我建議 B。而且身份系統和財務資料 ownership 要分開設計，避免未來更換登入方式時影響帳本本身。

你選 A / B / C。

</details>

<a id="q020"></a>
### Q020｜App 安全與本機加密

**使用者原答：** 選B  
**當期範圍：** CORE。  
**願景主題：** [FV-056](#fv-056)。  
**rc1 契約：** [RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。

好，第 20 題定案：B｜App 級安全。

也就是會包含 PIN、生物辨識、自動鎖定、本機 DB 加密、安全金鑰儲存，以及雲端備份獨立加密。正常使用不需要你自己管理 recovery key。

<details>
<summary>Q020 原題與選項（來源上下文）</summary>

接著第 20 題，我想定 安全性與本機加密。這是財務 App 很重要的一層。

A｜基本保護

依賴手機系統鎖
App 本身不另外上鎖
DB 不做額外加密

最簡單，但保護層比較少。

B｜App 級安全，我推薦

可選 PIN
生物辨識解鎖
App 切到背景後可自動鎖定
本機資料庫加密
加密金鑰放在 Android Keystore / iOS Keychain
備份檔另外加密
使用者不需要理解金鑰管理

C｜Zero-knowledge 等級
除了 B，再做：

使用者自己持有加密密鑰／recovery key
雲端服務端理論上無法解密資料
換手機必須處理 key recovery
忘記 recovery key 可能真的無法救回資料

安全性最高，但產品複雜度也高很多。

我建議 B。
如果未來真的要把它做成對外公開、多人使用的正式產品，再評估 C。

你選 A / B / C。

</details>

<a id="q021"></a>
### Q021｜資料匯入／移轉 Framework

**使用者原答：** 可以C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-060](#fv-060)。  
**rc1 契約：** [RC-18](architecture-baseline-v1.0-rc1.md#rc-18)。

好，第 21 題定案：C｜Migration Framework。

這樣未來不管是銀行 CSV、信用卡帳單、券商對帳單，甚至其他記帳 App 的資料，都會先進 staging 區做解析、欄位對應、重複偵測與驗證，確認後才真正寫入 Ledger。這可以大幅降低「一匯入就把正式帳本搞亂」的風險。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q021 原題與選項（來源上下文）</summary>

接下來第 21 題，我想定 資料匯入／匯出。這會影響資料可攜性，也決定我們未來能不能從別的記帳 App 搬資料進來。

A｜基本 CSV

匯出交易 CSV
匯入 CSV
最簡單

B｜完整資料可攜，我推薦

CSV 匯入／匯出
Excel 匯出
JSON 完整備份格式
可匯出指定期間／帳戶／分類
匯入前預覽
欄位 mapping
重複資料偵測
匯入失敗可回滾

C｜Migration Framework
除了 B，再設計成可寫 importer adapter，例如：

Money Manager
CWMoney
AndroMoney
銀行 CSV
券商對帳單
信用卡帳單

不同來源各有自己的 parser，但最後都轉成統一的 staging model，再確認後寫入 Ledger。

我會推薦 C，但 V1 先提供 B 的 UI。

因為「匯入」最怕直接把外部資料硬塞進正式 Ledger；用 staging/import pipeline 會安全很多。

你選 A / B / C。

</details>

<a id="q022"></a>
### Q022｜介於極簡與完整之間的首頁

**使用者原答：** 介於A跟B之間吧，不要太簡潔也不要太多  
**當期範圍：** CORE。  
**願景主題：** [FV-005](#fv-005)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

可以，那我會把第 22 題定成 A/B 混合版首頁。

首頁第一屏只放最有用的幾個東西：本月收支或現金流摘要、淨資產／帳戶總額、精簡的預算進度、信用卡待繳（有需要時才顯示）、最近交易與快速新增。投資摘要、即將到期的定期交易這些可以放在下一段，或有事件時再顯示，不要一開始就把首頁塞滿。整體也會避開你不喜歡的「卡片一張接一張」版型。

<details>
<summary>Q022 原題與選項（來源上下文）</summary>

接著第 22 題，我想定 首頁 Dashboard 的定位。這會影響資訊架構和之後整個 App 的主導航。

A｜極簡首頁
只顯示：

本月收入
本月支出
帳戶總額
快速新增

優點是乾淨。

B｜個人財務總覽，我推薦
除了 A，再有：

本月現金流
預算進度
淨資產
信用卡待繳
即將發生的定期交易
投資總值／損益
常用帳戶
最近交易

但控制資訊密度，不做滿版卡片堆疊。

C｜可自訂 Dashboard
除了 B，再讓使用者：

自己選模組
排序
隱藏
調整尺寸
建立不同 dashboard

自由度最高，但 UI 與狀態管理會複雜很多。

我建議 B，底層預留 C。而且會遵守你之前的偏好：首頁不要變成一堆卡片，而是更像有層次的財務摘要版面。

你選 A / B / C。

</details>

<a id="q023"></a>
### Q023｜五個底部導航位置

**使用者原答：** 選C  
**當期範圍：** CORE。  
**願景主題：** [FV-004](#fv-004)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 23 題定案：C｜底部 5 個位置，中間固定新增。

主導航就是：

首頁
帳本
＋ 新增
報表
資產

設定、備份、安全性、匯入匯出這類低頻功能不占主分頁，放右上角或獨立設定頁。

<details>
<summary>Q023 原題與選項（來源上下文）</summary>

接下來第 23 題，我想定 主導航。這會直接影響之後每個功能頁怎麼分組。

A｜4 個主分頁

首頁
記帳
報表
更多

最簡單，但股票、預算、帳戶都會被塞進「更多」。

B｜5 個主分頁，我比較推薦

首頁
帳本
報表
資產
設定／更多

其中「資產」再放帳戶、信用卡、投資、淨資產等。

C｜5 個主分頁，但把新增放中間

首頁
帳本
＋
報表
資產

設定則放右上角或個人頁。

我目前比較傾向 C，因為記帳 App 的「新增」是最高頻操作，讓它永遠在底部中央會很順手。

你選 A / B / C。

</details>

<a id="q024"></a>
### Q024｜快速輸入與情境式特殊交易

**使用者原答：** B跟C混合吧  
**當期範圍：** CORE。  
**願景主題：** [FV-006](#fv-006)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 24 題定案：B＋C 混合。

一般按中間「＋」時，直接進入快速記帳；只顯示金額、收入／支出、帳戶、分類、日期這些高頻欄位。商家、Tag、附件、拆分、多幣別、手續費等放進進階區。轉帳、投資、換匯、退款／刷退、信用卡繳款這些特殊交易則走獨立入口與專用表單，不硬塞進一般記帳流程。

這樣會兼顧速度和完整性。

<details>
<summary>Q024 原題與選項（來源上下文）</summary>

接著第 24 題，我想定 「新增交易」的主要操作方式，這會直接影響每天使用手感。

A｜單一完整表單
按「＋」後進一個完整頁面，所有欄位都在同一頁：

收入／支出／轉帳
金額
帳戶
分類
商家
Tag
備註
附件等

功能完整，但容易顯得很重。

B｜快速輸入＋進階展開，我推薦
一開始只顯示最常用欄位：

金額
支出／收入／轉帳
帳戶
分類
日期

其他像商家、Tag、附件、拆分、手續費、多幣別放在「更多」。

這樣大部分記帳可以幾秒完成，但複雜交易仍能處理。

C｜情境式新增
按「＋」先出現：

支出
收入
轉帳
投資
信用卡繳款
換匯
退款

選完才進對應表單。

邏輯最清楚，但每次多一步。

我比較推薦 B 為主，吸收 C：一般按「＋」直接快速記帳；長按或旁邊入口再選「轉帳、投資、退款、換匯」等特殊交易。

你選 A / B / C，也可以直接選 B+C 混合。

</details>

<a id="q025"></a>
### Q025｜金額欄內建計算器

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-006](#fv-006)、[FV-009](#fv-009)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)、[RC-04](architecture-baseline-v1.0-rc1.md#rc-04)。

好，第 25 題定案：B｜金額欄直接內建簡單計算器。像 120 + 85 - 20 可以直接算出結果再寫入金額欄，而且這次會把前導零、小數點、連續運算這類輸入規則一開始就寫進測試規範。

<details>
<summary>Q025 原題與選項（來源上下文）</summary>

接著第 25 題，我想定 計算機要不要直接整合進新增交易。你之前舊版就有計算機，而且輸入體驗曾經出過前導零之類的問題，所以新版最好一開始就定義清楚。

A｜不做內建計算機
金額欄只輸入數字。

B｜金額欄內建簡單計算，我推薦
可以直接輸入：

120 + 85 - 20

然後結果自動變成 185

支援：

+ - × ÷
小數
百分比
括號
正確處理前導零與小數點
計算完成後才寫入金額欄

C｜完整財務計算器
除了 B，再加入：

稅率
折扣
小費
匯率換算
分期試算
自訂公式

我會建議 B，匯率、分期這些交給各自的專用流程，不要把新增交易頁的計算器做得太重。

你選 A / B / C。

</details>

<a id="q026"></a>
### Q026｜完整財務時間、簡潔 UI

**使用者原答：** 可以，那就C，UI先B  
**當期範圍：** CORE。  
**願景主題：** [FV-015](#fv-015)。  
**rc1 契約：** [RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。

好，第 26 題定案：資料模型採 C，UI 採 B。

也就是底層完整保存 timestamp＋時區語意，但一般記帳畫面只讓你看到日期和時間；跨國旅遊、投資市場時間、匯入外部資料或未來同步時，才使用完整時區資訊。

<details>
<summary>Q026 原題與選項（來源上下文）</summary>

接下來第 26 題，我想定 交易日期與時間要做到多精細。

A｜只記日期
只存 2026/09/26，不管幾點發生。

B｜日期＋時間，我推薦
每筆交易都有完整 timestamp，但 UI 預設只突出日期；需要時可以改時間。這樣未來排序、匯入銀行資料、同一天多筆交易都比較準確。

C｜日期＋時間＋時區語意
除了 B，再明確處理：

原始交易時區
跨國旅遊
夏令時間
匯入外部資料時保留來源時間
顯示時再依使用者時區轉換

我其實會建議 C 的資料模型，B 的 UI。因為你有多幣別、投資、旅遊情境，時間如果只存本地字串，之後很容易出問題；但一般記帳畫面不需要把時區露給你看。

你選 A / B / C。

</details>

<a id="q027"></a>
### Q027｜規則式商家記憶與智慧預測預留

**使用者原答：** 可以B預留C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-012](#fv-012)。  
**rc1 契約：** [RC-05](architecture-baseline-v1.0-rc1.md#rc-05)。

好，第 27 題定案：B｜規則式商家記憶，底層預留 C｜智慧預測。

系統可以根據歷史交易記住某商家常用的分類、帳戶、Tag 等，下一次只做建議，不會自行入帳；之後如果要加 OCR、時間、地點、金額等上下文預測，也能沿用同一套 suggestion layer。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q027 原題與選項（來源上下文）</summary>

接著第 27 題，我想定 商家 Merchant 是否要做「自動學習」。

A｜只當基本資料

商家名稱
圖示
備註
搜尋使用

B｜規則式記憶，我推薦
系統記住你以前怎麼記：

全聯 → 日用品
中油 → 交通／加油
Netflix → 娛樂
某商家常用某張信用卡

下次輸入同一商家時，自動建議分類、帳戶、Tag，但不直接替你送出。

C｜智慧預測
除了 B，再根據：

時間
地點
金額
過去習慣
OCR 結果

預測整筆交易內容，甚至排序建議。

我建議 B 先做，底層預留 C。這樣實用、可控，也不會一開始就依賴 AI。

你選 A / B / C。

</details>

<a id="q028"></a>
### Q028｜完整 Reconciliation

**使用者原答：** 好，那就C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-034](#fv-034)。  
**rc1 契約：** [RC-12](architecture-baseline-v1.0-rc1.md#rc-12)。

好，第 28 題定案：C｜完整 Reconciliation 對帳機制。

這樣之後銀行帳戶、信用卡都可以有「已清算 / 未清算」、「對帳截止日」、「歷史對帳快照」、「匯入帳單自動 matching」。如果帳不平，也只能透過可追溯的 adjustment 解決，不能直接把 balance 改成看起來正確。這跟我們前面定的高標準 Ledger 很一致。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q028 原題與選項（來源上下文）</summary>

接著第 28 題我想討論一個對高標準 Ledger 很重要的功能：帳戶對帳 / Reconciliation。

A｜不做正式對帳
只顯示 App 算出的帳戶餘額，發現不對就自己新增調整交易。

B｜基本對帳
可以輸入銀行或信用卡目前實際餘額，App 顯示：

帳本餘額
實際餘額
差額

再讓你選擇建立一筆 adjustment。

C｜完整 Reconciliation，我推薦
除了 B，再支援：

指定對帳截止日期
勾選哪些交易已出現在銀行／信用卡帳單
顯示未清算交易
對帳完成後建立 reconciliation snapshot
保留歷次對帳紀錄
銀行 CSV／信用卡帳單匯入時自動嘗試 matching
差額不能偷偷改 balance，只能透過明確 adjustment 解決

例如：

純文字
銀行實際餘額：52,340
Ledger 餘額： 52,140

差額：+200

App 會先幫你找：

是否有漏記交易
是否有重複交易
是否有尚未入帳交易

真的找不到，再建立：

Balance Adjustment +200

而不是直接把帳戶餘額改成 52,340。

我會很推薦 C，因為前面既然已經選了高標準 Ledger，沒有 reconciliation 反而少了一個很重要的自我校驗機制。

你選 A / B / C。

</details>

<a id="q029"></a>
### Q029｜規則提醒與 Google Calendar channel

**使用者原答：** 可以C,B UI另外我想要提醒連動GOOGLE日曆，這樣可能更好  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-059](#fv-059)。  
**rc1 契約：** [RC-17](architecture-baseline-v1.0-rc1.md#rc-17)。

可以，而且我覺得這會比只靠 App notification 更實用。

第 29 題我會調整成：

底層：C｜規則式提醒引擎
V1 UI：B｜簡單的通知設定
再增加第三個概念：Delivery Channel。

同一條提醒規則可以決定要送到哪裡：

純文字
Reminder Rule
├─ App 內提醒
├─ 系統通知
└─ Google Calendar

例如信用卡：

純文字
信用卡繳款截止：10/15

App：
10/12 通知一次
10/14 再提醒

Google Calendar：
10/15 建立「信用卡繳款截止」

但我不建議把「預算使用 80%」這種即時狀態塞進 Google Calendar。比較適合進日曆的是：

信用卡結帳日／繳款日
房租、保費、訂閱等定期付款
定期收入
分期付款
對帳日期
有期限的專案預算
使用者自己指定的重要財務事件

而且每個日曆事件都要保存自己的 externalEventId，這樣你在 App 裡改日期或取消提醒時，能更新原本的 Google Calendar 事件，而不是一直新增重複事件。

另外，ChatGPT 本身也可以連接 Google Calendar；如果你之後希望我直接協助查看或建立你的行事曆事件，可以連接它。不過這跟我們正在設計的 ExpenseTracker 自己整合 Google Calendar 是兩個獨立功能。

接著剛好要決定這個整合最重要的一件事：

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q029 原題與選項（來源上下文）</summary>

接著第 29 題，我想定 通知 / 提醒系統，因為信用卡、預算、定期交易、備份其實都會用到。

A｜只有基本提醒

信用卡繳款
定期交易到期
備份失敗

B｜完整通知中心，我推薦
除了 A，再有：

預算達 50% / 80% / 100%
信用卡即將結帳
信用卡繳款截止
定期交易待確認
投資事件提醒
備份成功 / 失敗
對帳提醒
可個別開關各類通知

C｜規則式通知引擎
除了 B，再支援：

自訂條件
自訂提前幾天
金額門檻
特定帳戶 / 分類 / Tag
未來可接外部事件

例如：

餐飲預算超過 80% 時提醒
信用卡可用額度低於 20% 時提醒
30 天沒對帳時提醒

我會推薦 C 的底層、B 的 UI，跟我們前面的策略一致：能力先有，但不要讓設定頁變得太複雜。

你選 A / B / C。

</details>

<a id="q030"></a>
### Q030｜受控雙向 Google Calendar

**使用者原答：** 選C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-059](#fv-059)。  
**rc1 契約：** [RC-17](architecture-baseline-v1.0-rc1.md#rc-17)。

好，第 30 題定案：C｜受控雙向 Google Calendar 整合。

ExpenseTracker 會是財務規則的 source of truth。App 建立的日曆事件會保留外部事件 ID，之後能正確更新或刪除；如果你直接在 Google Calendar 改日期或刪除事件，App 可以偵測差異，但不會直接改帳務規則，而是讓你確認是否同步。這樣也能避免日曆誤操作影響信用卡繳款、定期付款等重要資料。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q030 原題與選項（來源上下文）</summary>

第 30 題｜Google Calendar 要單向還是雙向？

A｜App → Google Calendar 單向

ExpenseTracker 是唯一資料來源。

你在 App 改繳款日：
→ Google Calendar 跟著更新。

但直接在 Google Calendar 修改事件：
→ 不會回寫 ExpenseTracker。

最安全、最容易避免帳務資料出錯。

B｜完整雙向同步

在 Google Calendar 改日期：
→ ExpenseTracker 的財務提醒也跟著改。

很方便，但會產生很多問題，例如誤刪事件、重複事件、同步衝突。

C｜受控雙向，我推薦

ExpenseTracker 仍是財務規則的 source of truth。

但可以讀取 Google Calendar 狀態，例如：

事件被刪除了
時間被調整
使用者完成／變更事件

App 再詢問：

Google Calendar 的繳款日期已改成 10/16，是否同步修改？

不直接偷偷修改財務規則。

我會選 C。這樣有雙向整合的便利，但 Google Calendar 永遠不能在你不知道的情況下改動帳務邏輯。

你選 A / B / C。

好，Google Calendar 這條整合方向我先納入架構；而且你現在已經把 Google Calendar 連上 ChatGPT 了，之後如果你要我協助檢查實際行事曆流程，也可以直接做。

現在第 30 題還差你的選擇：

A｜單向：ExpenseTracker → Google Calendar；Calendar 的修改不回寫。
B｜完全雙向：Calendar 的修改直接回寫 ExpenseTracker。
C｜受控雙向，我推薦：ExpenseTracker 是財務規則的 source of truth；如果 Calendar 端有改動，App 偵測到後詢問你是否同步，不直接偷偷改財務資料。

我會選 C，安全性和便利性最好平衡。你選 A / B / C。

</details>

<a id="q031"></a>
### Q031｜供應商可替換的混合後端

**使用者原答：** 好那就選D  
**當期範圍：** CORE。  
**願景主題：** [FV-080](#fv-080)。  
**rc1 契約：** [RC-23](architecture-baseline-v1.0-rc1.md#rc-23)。

好，第 31 題定案：D｜混合式、供應商可替換的雲端架構。

下一題我建議直接定 本機資料庫，因為這會是整個 App 最核心的基礎之一。

<details>
<summary>Q031 原題與選項（來源上下文）</summary>

接著第 31 題，我覺得可以開始進入比較核心的技術架構決策了。

第 31 題｜雲端後端要採哪種方向？

A｜Firebase
Authentication、Cloud Storage、Firestore、Functions 等直接用 Google 生態。

優點是成熟、Flutter 支援很好；缺點是資料架構比較容易被 Firebase 綁住，而且未來完整 sync engine 要仔細設計。

B｜Supabase
PostgreSQL + Auth + Storage + Edge Functions。

對我們這種有很多關聯、revision、ledger、sync metadata 的資料模型比較自然，也方便未來做伺服器端查詢。

C｜自有 Backend
例如：

Flutter → REST/API → PostgreSQL → Object Storage

自由度與可控性最高，也最好做完整 sync protocol，但開發與維護成本最高。

D｜混合式，我目前最推薦
V1：

Flutter local DB
↓
Backend abstraction
↓
Supabase / 類似服務負責 Auth、backup metadata、storage

但 Domain、Repository、Sync protocol 完全不直接依賴 Supabase SDK。

未來如果要換成自有 Backend：

SupabaseAdapter → OwnServerAdapter

核心 App 不需要大改。

我會比較推薦 D。因為我們這次已經明確要求架構壽命要長，不適合讓 Firebase/Supabase API 滲透整個程式。

你選 A / B / C / D。

</details>

<a id="q032"></a>
### Q032｜Drift + SQLite

**使用者原答：** 好就選A  
**當期範圍：** CORE。  
**願景主題：** [FV-061](#fv-061)。  
**rc1 契約：** [RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。

好，第 32 題正式定案：A｜Drift + SQLite。本機 DB 會是核心資料來源，但 Drift model 不會直接跑進 Domain / UI，Repository 會把兩邊隔開。

<details>
<summary>Q032 原題與選項（來源上下文）</summary>

第 32 題｜本機資料庫要選哪一類？

A｜Drift + SQLite，我推薦
很適合我們現在這種：

Ledger 多表關聯
多腿交易
revision history
reconciliation
analytics/query engine
複雜 JOIN
transaction
schema migration

Drift 現在本身就是建構在 SQLite 上的型別安全 reactive persistence library，支援 transaction、migration、join、複雜 SQL 與跨平台。
Dart packages
+1

我們甚至可以利用 SQLite 的 FTS、window function 等能力處理搜尋與財務分析，而不用另外維護一套查詢引擎。
Dart packages

B｜ObjectBox / 類似 Object Database

物件操作比較直接、效能也很好，ObjectBox 目前仍有持續更新。
Dart packages
+1

但我們這個 App 已經越來越偏：

高關聯性 + Ledger + audit + reconciliation + analytics

這種資料形態我會更偏向 relational database。

C｜純 SQLite + 自己寫 DAO

自由度最高。

但很多：

type safety
reactive query
migration tooling
boilerplate

都要自己維護，我認為沒有必要。

我的建議：A｜Drift + SQLite

而且我會要求再加幾個標準：

純文字
Domain
   ↓
Repository Interface
   ↓
Local Data Source
   ↓
Drift
   ↓
SQLite

Domain 永遠不能直接碰 Drift model。

這樣未來就算換 DB，也不會污染整個 App。

另外我們前面選了本機資料庫加密，因此實作時不會直接照舊教學套 sqlcipher_flutter_libs；這個 package 在目前版本已經標示為 obsolete，SQLite 3.x 的加密整合方式已經改變，屆時會按照新版 sqlite3/cipher 方案做技術驗證。
Dart packages
+1

所以這題我其實很明確推薦 A。

你選 A / B / C。

</details>

<a id="q033"></a>
### Q033｜Thin Riverpod、Thick Domain

**使用者原答：** 好選A  
**當期範圍：** CORE。  
**願景主題：** [FV-062](#fv-062)。  
**rc1 契約：** [RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。

好，第 33 題定案：A｜Riverpod，但採「薄 Riverpod、厚 Domain」原則。

也就是 Riverpod 主要負責 UI state、async orchestration、dependency injection、cache/invalidation；真正的 Ledger、Budget、Investment、Sync、Reconciliation 規則都放在 Domain / Use Case，不塞進 Provider。

<details>
<summary>Q033 原題與選項（來源上下文）</summary>

接著第 33 題：State Management / Dependency Injection 怎麼做？

目前 Riverpod 3.4.3 在 2026 年 9 月仍持續更新，官方本身定位就是 reactive caching / data binding，也支援 async state、override 與測試；BLoC 9.2.1 也仍是成熟且積極維護的方案。
Dart packages
+2

A｜Riverpod，我推薦

用 Riverpod 處理：

UI state
async loading/error/data
dependency injection
Repository / Use Case 注入
畫面之間需要共享的狀態
cache / invalidation

但要訂一條很重要的規則：

純文字
Widget
   ↓
Controller / Notifier
   ↓
Use Case
   ↓
Repository
   ↓
Data Source

商業邏輯不能全部塞進 Provider。

例如「信用卡分期怎麼算」、「Ledger 是否平衡」、「刷退怎麼建立 reversal」都應該是 Domain 邏輯，而不是寫在 Notifier 裡。

B｜BLoC / Cubit

結構通常更顯式：

純文字
UI
↓ Event
BLoC
↓ State
UI

大型團隊很好管理，而且測試清楚。BLoC 的官方定位也強調 presentation 與 business logic 分離。
Dart packages

但我們這個 App 有大量：

reactive DB query
filter
async service
dependency injection
local-first state

如果每一個畫面都建立 Event / State，程式碼量可能會比較重。

C｜Riverpod + BLoC 混用

例如一般畫面用 Riverpod，複雜流程用 BLoC。

我反而不推薦。不是不能做，而是 Codex 後續很容易開始不知道某個功能到底該用哪一套，久了 architecture consistency 會下降。

我的建議：A｜Riverpod

但採「薄 Riverpod、厚 Domain」原則。

Riverpod 只負責協調狀態與依賴，不成為我們的 business logic layer。這樣即使未來 Riverpod 換掉，Ledger、Budget、Investment、Sync 這些核心都不會跟著重寫。

你選 A / B / C。

</details>

<a id="q034"></a>
### Q034｜Modular Monolith

**後續歸因更正（2026-09-26）**：使用者原答「選C」明確選定題目中的 Modular Monolith；原助手在推薦與後續回覆中提出「不要過度拆 package」，屬於助手實作建議，不能另列為使用者已選定的套件粒度限制。下方歷史文字原樣保留；後續 [D-002](#decision-module-enforcement) 已明確選定按業務拆套件，業務內按需要再拆。

**使用者原答：** 選C  
**當期範圍：** CORE。  
**願景主題：** [FV-063](#fv-063)。  
**rc1 契約：** [RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。

好，第 34 題定案：C｜Modular Monolith。

我會採「模組邊界嚴格，但專案結構不要過度拆 package」的做法。也就是 Ledger、Investment、Budget、Analytics、Sync、Credit Card 等都有自己的 domain boundary，模組彼此不能隨便直接讀對方的資料表或內部 class；需要互動時走明確 interface / application service。這對之後 Codex 很重要，因為可以直接訂規則：禁止為了方便跨模組偷存取 internal implementation。

大概會是這種概念：

純文字
app/
core/

modules/
  ledger/
  accounts/
  credit_cards/
  budgets/
  recurring/
  investments/
  analytics/
  reconciliation/
  import_export/
  sync/
  reminders/

但不是每個 module 都硬拆成獨立 Dart package，避免架構漂亮但開發痛苦。

<details>
<summary>Q034 原題與選項（來源上下文）</summary>

接著第 34 題，我想定 整體專案分層方式。

A｜Feature-first，我推薦
例如：

純文字
features/
  transactions/
  accounts/
  budgets/
  investments/
  reports/
  recurring/
  reconciliation/

每個 feature 裡再有：

presentation
application
domain
data

優點是功能邊界清楚，Codex 也比較不容易把所有東西塞進同一層。

B｜Layer-first
例如：

純文字
presentation/
domain/
data/
application/

所有功能再散落在各層。

理論上很乾淨，但專案大了之後找一個完整功能會跨很多資料夾。

C｜Modular Monolith
在 A 的基礎上更進一步，把核心功能做成相對獨立 module，例如：

純文字
modules/
  ledger/
  investments/
  budgets/
  analytics/
  sync/

每個 module 有自己的 domain boundary，彼此透過明確 interface 溝通。

這是最嚴謹，但規範也最多。

我會推薦 C，但實作風格接近 A：也就是採 modular monolith 的邊界思想，但不要做成過度工程化的 package 地獄。

你選 A / B / C。

</details>

<a id="q035"></a>
### Q035｜Application API 與 Domain Event

**使用者原答：** BC混合  
**當期範圍：** CORE。  
**願景主題：** [FV-064](#fv-064)。  
**rc1 契約：** [RC-19](architecture-baseline-v1.0-rc1.md#rc-19)。

好，第 35 題定案：B＋C 混合。

原則會是：同步查詢與明確操作走 Application API / Facade；跨模組狀態變化則用 Domain Event。 例如 Budget 要查某期間支出，可以呼叫 LedgerQueryService；但當一筆交易完成、信用卡結帳、投資交易成交時，就發布 TransactionPosted、StatementClosed、InvestmentTradeExecuted 這類事件，讓其他模組自己反應。這樣既不會過度 event-driven，也能保持模組邊界乾淨。

<details>
<summary>Q035 原題與選項（來源上下文）</summary>

接著第 35 題，我想定 模組之間的資料共享方式，這會直接決定我們的 modular monolith 到底是不是真的有邊界。

A｜可以直接共用 Repository
例如 Budget module 可以直接呼叫 TransactionRepository，Investment 也可以直接讀 Ledger repository。簡單，但久了模組會互相纏住。

B｜透過 Application API / Facade，我推薦
例如 Budget 不直接碰 Ledger database，而是呼叫：

純文字
LedgerQueryService
BudgetService
PortfolioService

每個 module 對外只暴露少數穩定 API，內部 repository/data source 都不公開。

C｜完整 Event-driven
模組主要透過 domain events 溝通，例如：

純文字
TransactionPosted
RefundCreated
StatementClosed
InvestmentTradeExecuted

其他 module 訂閱事件再更新自己的 projection。

解耦最強，但如果所有事情都 event-driven，V1 會有點過度工程化。

我會建議 B 為主、吸收 C：同步查詢和明確指令走 Facade/Application API；真正跨模組且適合非同步反應的事情才用 domain events。

你選 A / B / C，也可以直接選 B+C 混合。

</details>

<a id="q036"></a>
### Q036｜重要事件持久化、不做 Full Event Sourcing

**使用者原答：** 好B  
**當期範圍：** CORE。  
**願景主題：** [FV-064](#fv-064)。  
**rc1 契約：** [RC-19](architecture-baseline-v1.0-rc1.md#rc-19)。

好，第 36 題定案：B｜重要 Domain Event 持久化，但不做完整 Event Sourcing。

也就是像 TransactionPosted、RefundCreated、StatementClosed、ReconciliationCompleted、InvestmentTradeExecuted 這類真正有財務意義的事件會保留；UI refresh、按鈕點擊這種短暫事件不會進資料庫。

<details>
<summary>Q036 原題與選項（來源上下文）</summary>

接下來第 36 題，我想定 Domain Event 到底要不要持久化。這會影響未來同步、稽核、重建資料的能力。

A｜只在記憶體中傳遞
事件只用來通知其他 module，App 關掉後就不存在。

最簡單，但未來不好追蹤「某件事到底發生過沒有」。

B｜重要事件持久化，我推薦
只有真正有財務意義的事件才存下來，例如：

TransactionPosted
RefundCreated
StatementClosed
ReconciliationCompleted
InvestmentTradeExecuted
CorporateActionApplied

UI 類事件、畫面 refresh 這種則不存。

這會讓 audit、sync、debug 都可靠很多。

C｜完整 Event Sourcing
所有狀態都由事件重建，資料表只是 projection。

最嚴謹，但對這個 App 來說會太重，開發與 migration 成本也會高很多。

我建議 B：保留重要 Domain Events，但不是完整 Event Sourcing。

你選 A / B / C。

</details>

<a id="q037"></a>
### Q037｜Revision 與衝突偵測的同步

**使用者原答：** B  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-081](#fv-081)。  
**rc1 契約：** [RC-20](architecture-baseline-v1.0-rc1.md#rc-20)。

好，第 37 題定案：B｜Revision + Conflict Detection。

同步時不採「最後寫入直接覆蓋」，而是透過 version / updatedAt / deviceId / revision / tombstone 判斷是否衝突。一般可安全合併的資料自動處理；涉及 Ledger、信用卡、投資等重要資料時，只要存在真正衝突，就保留下來等待明確解決，不靜默覆寫。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q037 原題與選項（來源上下文）</summary>

接著第 37 題，我想定 同步架構的核心策略。我們前面已經決定 V1 先做備份，但未來要能升級成多裝置同步，所以現在要決定底層怎麼預留。

第 37 題｜未來 Sync Engine 要採哪種模型？

A｜Last Write Wins
同一筆資料在兩台裝置都修改時，以最後更新時間為準。

簡單，但可能把另一台的重要修改直接蓋掉。

B｜Revision + Conflict Detection，我推薦
每筆可同步資料都有：

id
version
updatedAt
deviceId
revision / tombstone

如果兩台裝置改到同一筆，就標成 conflict，而不是直接覆蓋。

一般情況自動合併；真的衝突時再讓使用者選擇。

C｜CRDT / 完整分散式同步
從資料結構本身設計成多裝置可以同時修改、最後自動 convergence。

技術上最強，但對 Ledger 這種需要強一致性的財務資料來說，複雜度很高，而且不一定適合所有 domain。

我建議 B。

尤其我們的 Ledger、信用卡、投資交易這種資料，寧可明確知道「有衝突」，也不要默默合併錯誤。

你選 A / B / C。

</details>

<a id="q038"></a>
### Q038｜低風險 merge、財務衝突人工確認

**使用者原答：** B  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-081](#fv-081)。  
**rc1 契約：** [RC-20](architecture-baseline-v1.0-rc1.md#rc-20)。

好，第 38 題定案：B｜安全資料自動合併，重要財務資料人工確認。

也就是低風險資料可以依規則合併；但只要牽涉金額、帳戶、交易分類、已結帳信用卡、投資交易、reconciliation 等，就不能靜默決定。系統只在真的有風險時才要求你處理 conflict，避免日常使用一直被同步提示打斷。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q038 原題與選項（來源上下文）</summary>

接著第 38 題，我想定 同步衝突要怎麼解決。

A｜全部讓使用者選
發生衝突就顯示：

保留這台
保留雲端
查看差異

最安全，但可能很煩。

B｜安全資料自動合併，重要財務資料人工確認，我推薦
例如：

Tag 名稱、商家圖示這類低風險資料，可以規則式自動合併
同一筆交易的金額、帳戶、分類被兩台同時修改，就進 conflict
已結帳信用卡、投資交易、reconciliation 資料更嚴格，不自動亂合併

App 只在真的需要你決定時才跳出來。

C｜全自動合併
盡量透過欄位級 merge 解決，只有完全無法判定時才問使用者。

體驗最順，但對財務資料風險比較高。

我建議 B，因為我們前面一直走「高標準但 UI 不過度複雜」的方向，這裡也應該一致。

你選 A / B / C。

</details>

<a id="q039"></a>
### Q039｜核心財務高強度測試

**使用者原答：** C  
**當期範圍：** CORE。  
**願景主題：** [FV-095](#fv-095)。  
**rc1 契約：** [RC-21](architecture-baseline-v1.0-rc1.md#rc-21)。

好，第 39 題定案：C｜核心模組採接近金融系統等級的測試策略。

但會分層，不是所有畫面都用同一強度：Ledger、Sync、Investment、Reconciliation、Import/Restore 這些核心要有 property-based、fuzz、隨機交易生成、long-run simulation、migration matrix、determinism、災難還原測試；一般 UI、設定頁則維持高品質的 unit/widget/integration + 關鍵 golden test 即可。

<details>
<summary>Q039 原題與選項（來源上下文）</summary>

接著第 39 題，我想定 測試策略，這會直接影響之後 Codex 的開發門檻。

A｜一般測試

Unit test
Widget test
Integration test

有基本覆蓋即可。

B｜高標準測試，我推薦
除了 A，再要求：

Domain invariants 必測
Ledger balance / transfer / refund / FX 必測
DB migration test
Repository contract test
Sync conflict test
Import rollback test
Golden/UI test 只放關鍵畫面
每個 bug 修復都要補 regression test

C｜接近金融系統等級
除了 B，再加入：

Property-based testing
Fuzz testing
大量隨機交易生成
Long-run simulation
Determinism test
Cross-version migration matrix
Disaster recovery / restore test

我會建議 C，但分層執行。

不是每個 UI 小功能都搞成金融核心測試，而是：

Ledger / Sync / Investment / Reconciliation：C 等級
一般 UI / 設定頁：B 等級

這樣才能符合我們前面訂的「高標準核心、UI 不過度工程化」。

你選 A / B / C。

</details>

<a id="q040"></a>
### Q040｜嚴格 PR Gate 與架構治理

**使用者原答：** C  
**當期範圍：** CORE。  
**願景主題：** [FV-105](#fv-105)。  
**rc1 契約：** [RC-24](architecture-baseline-v1.0-rc1.md#rc-24)。

好，第 40 題定案：C｜嚴格 PR Gate + Architecture Governance。

之後 Codex 的權限邊界會很清楚：它可以實作、補測試、修 bug，但不能自行改已 freeze 的架構決策。任何 module boundary、資料 schema、同步策略、核心 domain invariant 的變更，都必須先更新 ADR 並重新 review。每個 slice 也要有 acceptance criteria、測試結果與 exact SHA，release artifact 能追溯回 commit。

<details>
<summary>Q040 原題與選項（來源上下文）</summary>

接著第 40 題，我想定 CI/CD 與 GitHub 開發流程，因為之後真的要交給 Codex 開發，這會是品質閘門。

A｜簡單 GitHub Flow

main
feature branch
PR
CI 跑測試

夠用，但規範比較鬆。

B｜嚴格 PR Gate，我推薦
除了 A，再要求：

每個 slice 一個明確 branch
PR 必須綁定 acceptance criteria
lint / test / migration check / architecture check 全過才能 merge
禁止直接 push main
每次 merge 都留下 exact SHA
release 前有完整 regression suite

C｜B + Architecture Governance
除了 B，再加：

ADR 變更必須獨立 review
module boundary 自動檢查
dependency rule 驗證
schema change 必須附 migration plan
performance budget
security/static analysis
release artifact 可追溯到 commit SHA
Codex 不可自行更改已 freeze 的 architecture decision

我會選 C。

因為這次我們花這麼多時間先把架構定完整，就是希望之後 Codex 是「照規格執行」，不是邊寫邊改架構。

你選 A / B / C。

</details>

<a id="q041"></a>
### Q041｜完整 Data Evolution

**使用者原答：** C  
**當期範圍：** CORE。  
**願景主題：** [FV-094](#fv-094)。  
**rc1 契約：** [RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。

好，第 41 題定案：C｜完整 Data Evolution Framework。

這代表我們會把「資料升級」當成正式架構能力，而不只是資料庫 migration。之後會同時管理：

DB schema version
Domain model version
Event version
Backup format version
Import format version
Sync protocol version
Migration dry-run / integrity check
重大 migration 前自動備份
向前／向後相容策略
失敗時 rollback / recovery

也就是未來即使 Ledger、投資公司行動、同步協議或備份格式改版，也不需要冒著破壞多年帳務資料的風險硬升級。

<details>
<summary>Q041 原題與選項（來源上下文）</summary>

接著第 41 題，我想定 版本與 Migration 策略。這對我們這種資料很多、又要求長期使用的 App 很重要。

A｜只做一般 schema migration
每次 DB schema 變更，就寫 migration script 升級。

夠基本，但只處理「欄位怎麼改」，不管 domain 行為變化。

B｜Versioned Migration，我推薦
除了 schema migration，再保留：

DB schema version
app data model version
migration history
upgrade path
migration test
rollback / recovery strategy
backup before risky migration

也就是不是只有 ALTER TABLE，而是整個資料版本有生命週期。

C｜完整 Data Evolution Framework
除了 B，再加入：

domain migration
event/version migration
import format versioning
backup format versioning
sync protocol versioning
backward compatibility window
migration dry-run
migration integrity hash/checksum

這樣未來即使：

Ledger model 升級
投資 corporate action schema 改變
sync protocol 升級
backup format 改版

都能有明確轉換流程。

我會推薦 C。因為這個 App 我們已經不是把它當一次性專案，而是打算長期演進；資料可升級性本身就應該是一個核心 capability。

你選 A / B / C。

</details>

<a id="q042"></a>
### Q042｜本機 Diagnostics 與 Observability 預留

**使用者原答：** 好，照你推薦的  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-096](#fv-096)。  
**rc1 契約：** [RC-15](architecture-baseline-v1.0-rc1.md#rc-15)、[RC-21](architecture-baseline-v1.0-rc1.md#rc-21)。

好，第 42 題定案：C 的 Observability 架構能力，但 V1 預設只開 B 的本機 Diagnostics。

也就是會有 structured logs、migration / sync / import / backup log、slow query 與 performance tracing 能力，但不預設把使用資料或財務資料上傳到遠端。未來如果要加 crash reporting 或 telemetry，必須另外明確 opt-in，而且敏感欄位要先做 redaction / hashing。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q042 原題與選項（來源上下文）</summary>

接著第 42 題，我想定 錯誤處理與 Logging / Diagnostics。這會直接影響未來 Codex debug 和你自己遇到問題時，我們能不能快速定位。

A｜基本 Logging
只記錄：

error
stack trace
crash

最簡單。

B｜結構化 Diagnostics，我推薦
除了 A，再有：

structured logs
module / operation
correlation ID
DB migration log
sync log
import log
backup / restore log
不把敏感財務內容直接寫進 log
App 內可匯出診斷報告

例如：

純文字
module: sync
operation: apply_revision
transactionId: [redacted/hash]
result: conflict_detected

這樣可以 debug，但不會把「你在某間店花多少錢」直接寫進 log。

C｜完整 Observability Framework
除了 B，再加入：

performance tracing
slow query detection
DB health metrics
sync latency
crash correlation
feature-level metrics
optional remote diagnostics / telemetry

功能最完整，但要特別注意隱私與自用 App 是否真的需要遠端 telemetry。

我的建議是 C 的架構能力，但預設只開 B。

也就是本機 diagnostics 做完整；remote telemetry / crash upload 必須明確 opt-in，不預設偷偷上傳財務 App 的使用資料。

你選 A / B / C。

</details>

<a id="q043"></a>
### Q043｜完整 Update Channel、極簡版本顯示

**使用者原答：** 好，但顯示只需要那一版就行  
**當期範圍：** CORE。  
**願景主題：** [FV-097](#fv-097)。  
**rc1 契約：** [RC-24](architecture-baseline-v1.0-rc1.md#rc-24)。

好，第 43 題就這樣定案：底層採 C，但 UI 極簡化。

更新系統內部仍保存完整資訊，例如 version / build / channel / commit SHA / checksum / migration level，用來做驗證與追蹤；但一般使用者畫面只顯示正式版本號，例如：

目前版本：2.3.1
最新版本：2.4.0

甚至沒有更新時只需要：

版本 2.3.1｜已是最新版本

build number、commit SHA、channel 之類都不要塞在正常 UI，需要除錯時才放到「診斷資訊」裡。

<details>
<summary>Q043 原題與選項（來源上下文）</summary>

接著第 43 題，我想定 App 更新 / Release 機制。這一題其實很重要，因為你前一版就遇過「App 顯示已是最新版，但實際版本沒更新」這類問題，所以新版最好從一開始就把版本來源、release metadata、下載與驗證定死。

A｜只靠商店更新

Google Play / App Store
App 內不自己檢查版本

最穩，但如果你主要是自己用、透過 GitHub Release 發 APK，就不夠方便。

B｜App 內更新檢查

App 啟動或手動檢查版本
從 GitHub Release / update manifest 取得最新版本
顯示 release notes
提供下載連結
版本比較有單一標準

比舊版可靠，但還是比較偏「提醒你去更新」。

C｜完整 Update Channel，我推薦
除了 B，再加入：

stable / beta channel
signed update manifest
APK checksum / signature 驗證
minimum supported version
mandatory update / recommended update
rollout metadata
rollback / bad release 標記
release artifact 綁定 commit SHA
更新前檢查 DB migration compatibility
App 內清楚顯示「目前版本 / 最新版本 / channel / build」

例如 manifest 會明確包含：

純文字
version: 2.3.1
build: 20301
channel: stable
minSupportedVersion: 2.1.0
commitSha: abc123...
artifactSha256: ...
migrationLevel: 7

這樣「到底是不是最新版」就不靠模糊邏輯，而是由唯一版本來源判定。

我會選 C。

你要不要也直接選 C？

</details>

<a id="q044"></a>
### Q044｜Android 優先、平台接口預留 iOS

**使用者原答：** B  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-098](#fv-098)。  
**rc1 契約：** [RC-23](architecture-baseline-v1.0-rc1.md#rc-23)。

好，第 44 題定案：B｜Android 優先，架構預留 iOS。

也就是 V1 的實際開發、測試、發佈都先以 Android 為主；但像 Secure Storage、生物辨識、通知、Calendar、Update Service 這些都會透過 interface 隔離，Domain / Repository / UI component 不直接綁 Android。未來要做 iOS 時，補 platform adapter 就好，不需要重寫核心。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q044 原題與選項（來源上下文）</summary>

第 44 題｜第一版要支援哪些平台？

這會影響我們 Flutter 專案一開始要維護哪些 platform-specific integration。

A｜Android only
先把 Android 做到最好，包括生物辨識、Keystore、通知、背景任務、App 更新、Google Calendar 等。

B｜Android 優先，但架構預留 iOS，我推薦
V1 正式開發與測試以 Android 為主；Domain、Database、Repository、UI component 等不寫死 Android。

iOS 特有功能先做 interface，例如：

純文字
SecureStorage
BiometricAuth
CalendarIntegration
NotificationService
UpdateService

Android 先有 implementation，未來要做 iOS 時補 Apple implementation。

C｜Android + iOS 同步開發
每個 Slice 都要求兩邊通過。

品質最完整，但會明顯增加第一版開發量，尤其我們現在是自用 App。

以你目前的情況，我推薦 B：Android 優先、架構預留 iOS。這樣不會為還沒使用的平台拖慢 V1，但也不會把 Android API 寫死進核心。

你選 A / B / C。

</details>

<a id="q045"></a>
### Q045｜Material 3 與自建 Design System

**使用者原答：** 好B  
**當期範圍：** CORE。  
**願景主題：** [FV-085](#fv-085)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 45 題定案：B｜Material 3 為底，自建 Design System。

也就是 Flutter 原生元件只當基礎，不會讓各頁直接各自亂用。會統一管理 color、typography、spacing、radius、button、input、sheet、dialog、list、chart container，以及 loading / empty / error state。這樣 Codex 後面做新頁面時，只能從既有元件和 token 延伸，不會越做越不像同一個 App。

<details>
<summary>Q045 原題與選項（來源上下文）</summary>

接著第 45 題，我想定 Design System / UI 元件策略，這會直接影響之後 Codex 能不能把整個 App 做得一致。

第 45 題｜UI 元件要做到哪種程度？

A｜直接用 Material 3 為主

Flutter 原生元件
少量客製
開發最快
但容易看起來像一般 Flutter App

B｜Material 3 為底，自建 Design System，我推薦
建立自己的：

Color tokens
Typography
Spacing
Radius
Elevation
Icon rules
Button / Input / Sheet / Dialog / List / Chart container
Loading / Empty / Error state

底層仍用 Flutter / Material 3，但 App 不直接到處用原生元件，而是透過自己的元件層。

C｜完全自製 UI framework
幾乎所有元件自己畫、自己管理互動與狀態。

自由度最高，但成本太高，也容易犧牲 accessibility 和平台一致性。

我建議 B。

尤其你之前已經有明確偏好：暖色、淺背景、不喜歡滿畫面卡片堆疊。所以這次應該從第一天就把這些寫進 Design Tokens，而不是做到一半再慢慢統一。

你選 A / B / C。

</details>

<a id="q046"></a>
### Q046｜淺色優先、深色模式預留

**使用者原答：** B  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-085](#fv-085)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 46 題定案：B｜淺色優先，Design System 預留深色模式。

V1 會以暖色、淺背景為主要設計與驗收基準；但所有顏色都走 semantic token，不把實際色碼散落在各頁。未來要補 Dark Mode，只需要新增一套 theme mapping，而不是逐頁重做。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q046 原題與選項（來源上下文）</summary>

接著第 46 題，我想定 Theme 與外觀模式。

A｜只做淺色
先把暖色、淺背景做到最好，不做深色模式。

B｜淺色優先＋預留深色，我推薦
V1 主要設計、驗收都以淺色為準，但 Design Tokens 從一開始就支援 light/dark semantic colors，例如：

surface / surfaceVariant / textPrimary / textSecondary / positive / negative / warning

這樣未來加深色模式時，不需要重畫整個 UI。

C｜淺色＋深色同步完成
V1 就要求兩套完整 theme 都做完、都跑 golden test。

我會推薦 B。先把你真正會用的暖色淺色介面做到成熟，但架構不把顏色值寫死。

你選 A / B / C。

</details>

<a id="q047"></a>
### Q047｜高標準無障礙

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-086](#fv-086)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)、[RC-21](architecture-baseline-v1.0-rc1.md#rc-21)。

好，第 47 題定案：B｜高標準 Accessibility。

會要求系統字體縮放、合理 touch target、顏色不作為唯一訊息來源、screen reader label、表單錯誤文字、reduce motion，以及關鍵畫面的對比與大字模式驗收。這些會直接寫進 Design System 和 UI acceptance criteria，而不是最後才補。

<details>
<summary>Q047 原題與選項（來源上下文）</summary>

接著第 47 題，我想定 無障礙與字體縮放策略。這會影響我們自建 Design System 的品質。

A｜基本支援
跟著系統字體大小即可，不另外做太多。

B｜高標準 Accessibility，我推薦

支援系統字體縮放
重要頁面在大字模式下仍不破版
Touch target 不小於合理尺寸
色彩不能只靠紅綠判斷
Screen reader label
表單錯誤有文字說明
動畫尊重 reduce motion
對比度納入 UI 驗收

C｜完整 Accessibility Compliance
除了 B，再用更嚴格的 WCAG 等級與自動檢查，並對所有頁面做 accessibility audit。

我會推薦 B。對自用 App 已經很扎實，也不會把開發成本拉得太高。

你選 A / B / C。

</details>

<a id="q048"></a>
### Q048｜繁中優先與完整 i18n

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-087](#fv-087)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)、[RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。

好，第 48 題定案：B｜繁中優先，但完整 i18n 架構。

V1 介面先只做繁體中文，但所有文字、日期、數字、幣別格式都走 localization layer；Ledger 內部的金額與幣別資料也不會跟 UI 顯示格式綁死。未來要補英文或其他語系，不需要重構畫面。

<details>
<summary>Q048 原題與選項（來源上下文）</summary>

接著第 48 題，我想定 語系、數字與幣別格式。我們前面已經選完整多幣別，所以這題不能只當翻譯處理。

第 48 題｜國際化要做到哪個程度？

A｜繁體中文 + 台灣格式
V1 只支援：

繁體中文
台灣日期格式
TWD 為預設基準幣別

其他幣別能記帳，但 UI 語言不考慮擴充。

B｜繁中優先，但完整 i18n 架構，我推薦
V1 UI 先只做繁體中文，但所有文字都走 localization resources，不把中文字串直接寫死在 Widget。

同時完整處理：

Locale
日期／時間格式
千分位
小數位
正負金額
各幣別 decimal precision
貨幣符號與 ISO code
百分比
時區顯示

例如：

TWD NT$1,280
JPY ¥1,280
USD $1,280.50

但 Ledger 底層不會因顯示格式而改變原始數值。

C｜V1 就多語系
一開始就做：

繁中
英文
可能再加日文等

架構與 UI 測試量都會增加。

我建議 B：先把繁體中文體驗做好，但從第一行 UI code 就具備完整 localization 能力。

你選 A / B / C。

</details>

<a id="q049"></a>
### Q049｜整數 minor unit 與高精度 Decimal

**使用者原答：** B+C  
**當期範圍：** CORE。  
**願景主題：** [FV-009](#fv-009)。  
**rc1 契約：** [RC-04](architecture-baseline-v1.0-rc1.md#rc-04)。

好，第 49 題定案：B + C 混合。

核心規則會是：Ledger 入帳金額一律用整數 minor unit 儲存；匯率、股價、成本計算使用高精度 Decimal；禁止用 double 做財務核心運算。

這樣像 TWD、JPY 這種 0 位小數貨幣，以及 USD 這種 2 位小數貨幣都能穩定處理；投資與 FX 又保有足夠精度。

<details>
<summary>Q049 原題與選項（來源上下文）</summary>

接著第 49 題，我想定一個很核心的技術細節：金額在資料庫裡要怎麼存。這會直接影響匯率、投資、報表與長期計算精度。

A｜直接用 double
最直覺，但浮點數會有像 0.1 + 0.2 != 0.3 這類精度問題。對財務 App 我不建議。

B｜最小貨幣單位整數，我推薦
例如：

TWD 1280 元 → 1280
USD 12.34 → 1234 cents
JPY 500 → 500

資料庫用整數儲存，搭配該幣別的 scale 解讀。

優點是帳務計算非常穩定。

C｜高精度 Decimal
使用任意精度 decimal 表示金額與匯率。

對投資、匯率、價格計算很有彈性，但資料庫與序列化會比較複雜。

我的建議其實是 B + C 混合：

Ledger 最終入帳金額：整數 minor unit
匯率、股價、成本計算：高精度 Decimal
計算完成後再依幣別 rounding rule 轉成 Ledger 金額
全程禁止用 double 做財務核心運算

例如：

純文字
USD 12.34
→ ledgerAmount = 1234
→ currency = USD
→ scale = 2

但匯率可以是：

純文字
32.487315

不需要硬塞成 cents。

我很推薦這個混合方案。你選 A / B / C / B+C。

</details>

<a id="q050"></a>
### Q050｜按 Domain 定義 rounding

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-009](#fv-009)。  
**rc1 契約：** [RC-04](architecture-baseline-v1.0-rc1.md#rc-04)。

好，第 50 題定案：B｜依 Domain 明確定義 rounding 規則。

也就是核心財務運算不允許隨手 round()。FX、分攤、分期、投資成本、稅與手續費都各自有明確 rounding policy；需要吸收尾差時，像拆分交易或分期，會用可預期且可測試的規則處理。

<details>
<summary>Q050 原題與選項（來源上下文）</summary>

接著第 50 題，我想定 Rounding / 四捨五入規則。這其實很重要，因為匯率、分攤、分期、股票手續費都可能產生無法整除的尾數。

A｜全部統一四捨五入
所有地方都用同一種 rounding mode。簡單，但某些金融情境可能不正確。

B｜依 Domain 明確定義，我推薦
例如：

貨幣入帳：依幣別 precision
FX：保留高精度到最後一步才 round
分攤：最後一筆吸收 rounding remainder
分期：最後一期修正尾差
投資成本：內部保留高精度，實際現金流依交易貨幣 round
稅／手續費：依來源規則

每次 rounding 都要有明確規則，不能讓程式隨便 round()。

C｜全部保存未四捨五入原始值
除了 B，再把每次計算前後值都永久保存。

最完整，但資料量和模型複雜度會增加很多，通常沒必要。

我建議 B。高標準，但不過度保存中間計算垃圾。

你選 A / B / C。

</details>

<a id="q051"></a>
### Q051｜手動、比例與百分比分攤

**使用者原答：** 好B預留C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-016](#fv-016)。  
**rc1 契約：** [RC-03](architecture-baseline-v1.0-rc1.md#rc-03)。

好，第 51 題定案：B｜手動 + 比例 / 百分比分攤，底層預留 C｜分攤模板。

V1 會支援直接輸入金額、平均分、百分比、固定比例，而且最後一筆會依我們剛定的 rounding policy 吸收尾差；未來如果要加入常用分攤模板，不需要改底層資料模型。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q051 原題與選項（來源上下文）</summary>

接著第 51 題，我想定 金額分攤與比例拆分 的標準，這跟你前面選的 split transaction 很有關。

A｜只允許手動輸入每個拆分金額
例如總額 1,000，你自己填 400 / 350 / 250。

B｜手動 + 比例 / 百分比分攤，我推薦
除了直接輸入金額，也可以：

50% / 30% / 20%
平均分
依固定比例
最後一筆自動吸收 rounding remainder

C｜再加入分攤模板
例如常用「房租 70% 生活、30% 工作」、「旅費 4 人均分」之類，可以儲存模板重複使用。

我會推薦 B，底層預留 C。V1 先把拆分計算做準，不急著讓 UI 多一堆模板管理。

你選 A / B / C。

</details>

<a id="q052"></a>
### Q052｜Ledger 唯一真相與可重建投影

**使用者原答：** 好B+C  
**當期範圍：** CORE。  
**願景主題：** [FV-007](#fv-007)、[FV-103](#fv-103)。  
**rc1 契約：** [RC-13](architecture-baseline-v1.0-rc1.md#rc-13)。

好，第 52 題定案：B + C｜Ledger 是唯一真相，搭配可重建的 Balance Snapshot / Projection。

也就是：

Ledger 永遠是 source of truth
current balance、日/月餘額、淨資產走快取或 projection
snapshot 壞掉可以整批丟掉重算
不允許「改 currentBalance 就算完成」
長期報表可以直接吃日/月 snapshot，不必每次掃完整帳本

這樣可靠性和效能都兼顧。

<details>
<summary>Q052 原題與選項（來源上下文）</summary>

接著第 52 題，我想定 帳戶餘額的來源與快取策略。這對高標準 Ledger 很重要。

A｜直接存 currentBalance
每次交易後直接更新帳戶餘額欄位，查詢很快，但如果某次更新漏掉，餘額就可能永久錯掉。

B｜Ledger 是唯一真相，餘額可重建，我推薦
帳戶餘額本質上永遠來自 Ledger；可以另外維護 balance snapshot / cache 加速，但 cache 不是 source of truth。

也就是：

Ledger entries → 重建 balance

如果 cache 壞掉，可以丟掉重算。

C｜完整時間點快照系統
除了 B，再固定建立 daily / monthly balance snapshots，讓長期報表和大量資料查詢更快。

我會推薦 B + C 混合：Ledger 永遠是真相，但允許建立可重建的 snapshots / projections 來加速。

你選 A / B / C / B+C。

</details>

<a id="q053"></a>
### Q053｜Archive、Merge／Replace 與引用保全

**使用者原答：** 好C  
**當期範圍：** CORE。  
**願景主題：** [FV-010](#fv-010)、[FV-011](#fv-011)、[FV-012](#fv-012)。  
**rc1 契約：** [RC-05](architecture-baseline-v1.0-rc1.md#rc-05)。

好，第 53 題定案：C｜Archive + Merge / Replace。

也就是任何已被正式交易引用的帳戶、分類、商家、Tag，都不做破壞性刪除；平常用「封存」隱藏，歷史資料仍完整。管理頁則可以做合併、重新指派、帳戶關閉 successor 等整理功能。這跟我們前面強調的可追溯性很一致。

<details>
<summary>Q053 原題與選項（來源上下文）</summary>

接著第 53 題，我想定 刪除帳戶／分類／商家這類已被交易引用的資料，要怎麼處理。

A｜允許刪除
如果已被交易使用，就把關聯清掉或改成未分類。

簡單，但會破壞歷史資料，我不建議。

B｜Archive / 停用，我推薦
只要曾經被正式交易使用，就不能真正刪除，只能「停用 / 封存」。

例如你不再使用某張信用卡：

玉山信用卡
狀態：已封存

歷史交易仍然完整，但新增交易時不再出現在預設選單。

分類、商家、Tag 也採類似概念。

C｜B + Merge / Replace
除了封存，再支援：

合併重複商家
合併 Tag
分類重新歸併
帳戶關閉並指定 successor
批次重新指派歷史資料

例如：

純文字
7-ELEVEN
7-11
統一超商

可以整理成同一個 Merchant。

我推薦 C，但 UI 可以先把「封存」做清楚，Merge / Replace 放管理頁，不要干擾日常記帳。

你選 A / B / C。

</details>

<a id="q054"></a>
### Q054｜Account Lifecycle 與 Opening Balance

**使用者原答：** 好C  
**當期範圍：** CORE。  
**願景主題：** [FV-010](#fv-010)。  
**rc1 契約：** [RC-05](architecture-baseline-v1.0-rc1.md#rc-05)。

好，第 54 題定案：C｜完整 Account Lifecycle。

帳戶會有開戶日期、Opening Balance event、關閉日期、關閉前餘額檢查、剩餘餘額移轉、關閉後禁止新增一般交易，以及必要時重新啟用。Opening Balance 也會明確排除在一般收入／支出報表之外。

<details>
<summary>Q054 原題與選項（來源上下文）</summary>

接著第 54 題，我想定 帳戶關閉與 Opening Balance / Initial State，這會影響第一次建立帳戶、匯入舊資料和對帳。

A｜帳戶只設初始餘額
建立帳戶時直接填「目前餘額 50,000」，系統記住即可。

B｜建立明確 Opening Balance Event，我推薦
建立帳戶時如果有既有餘額，系統自動建立一筆特殊 Ledger event，例如：

純文字
Opening Balance
銀行帳戶 +50,000

它不是一般收入，所以報表不會把它算成「本月收入」。

C｜完整 Account Lifecycle
除了 B，再支援：

開戶日期
初始餘額事件
關閉日期
關閉前強制餘額檢查
剩餘餘額移轉
關閉原因
關閉後禁止新增一般交易
必要時可重新啟用

我會推薦 C，因為對信用卡、銀行、投資帳戶來說，帳戶生命週期其實很重要。

你選 A / B / C。

</details>

<a id="q055"></a>
### Q055｜信用卡手動／帳單匯入及擷取來源

**使用者原答：** B預留C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-017](#fv-017)、[FV-060](#fv-060)。  
**rc1 契約：** [RC-07](architecture-baseline-v1.0-rc1.md#rc-07)、[RC-18](architecture-baseline-v1.0-rc1.md#rc-18)。

好，第 55 題定案：B｜手動＋帳單匯入，底層預留 C｜自動擷取來源。

V1 先把信用卡 statement import / matching 做可靠，包括 CSV、Excel、PDF 匯入、既有交易比對、重複／漏記偵測、statement 建立與人工確認；未來再接 Email、銀行 API 或通知來源時，只新增新的 ingest adapter，不改信用卡核心模型。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q055 原題與選項（來源上下文）</summary>

接著第 55 題，我想定 信用卡帳單資料的來源與匹配策略。

A｜完全手動
帳單金額、繳款日、交易都自己輸入。

B｜手動＋匯入，我推薦
支援：

信用卡 CSV / Excel / PDF 匯入
對應既有交易
找重複／漏記
建立 statement
使用者確認後入帳

C｜再加自動擷取
未來可以接 Email、銀行 API 或通知內容，自動偵測帳單與消費。

我會建議 B，底層預留 C。先把 statement matching 做紮實，之後才接自動來源。

你選 A / B / C。

</details>

<a id="q056"></a>
### Q056｜多 Provider 行情架構

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-026](#fv-026)。  
**rc1 契約：** [RC-08](architecture-baseline-v1.0-rc1.md#rc-08)。

好，第 56 題定案：C｜多 Provider 聚合市場資料架構。

也就是底層會有統一的 MarketDataProvider 介面，但可以依市場與資料類型使用不同來源，例如台股、美股、匯率、Corporate Actions 分開處理；主要來源失敗時，也可以 fallback 到次要來源。更重要的是，Provider 不直接進入 Investment Domain，避免任何一家 API 變動就牽動核心投資邏輯。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q056 原題與選項（來源上下文）</summary>

接著第 56 題，我想定 股票與市場報價資料來源策略。

A｜單一行情來源
所有股票、ETF、匯率都依賴一個 API。

開發最簡單，但來源掛掉、額度改變或某市場不支援時會很麻煩。

B｜Provider abstraction，我推薦
底層定義統一介面，例如：

純文字
MarketDataProvider
├─ getQuote()
├─ getHistoricalPrices()
├─ searchSymbol()
└─ getCorporateActions()

V1 先接一個主要 provider，但 Domain 不知道實際是哪一家 API。以後可以替換或新增來源。

C｜多 Provider 聚合
除了 B，再同時支援多個行情來源，依市場或資料品質自動 fallback，例如台股用 A、美股用 B、匯率用 C。

功能最完整，但 V1 維護成本比較高。

我建議 B，架構預留 C。

也就是一開始只需要把一個可靠資料源接好，但任何股票、匯率、Corporate Action 邏輯都不能直接綁死那個供應商。

你選 A / B / C。

</details>

<a id="q057"></a>
### Q057｜Market Data Pipeline

**使用者原答：** 好C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-026](#fv-026)。  
**rc1 契約：** [RC-08](architecture-baseline-v1.0-rc1.md#rc-08)。

好，第 57 題定案：C｜完整 Market Data Pipeline，UI 維持簡單。

也就是底層會處理市場交易時段、批次報價、歷史行情快取、provider fallback、rate limit、stale-while-revalidate、失敗退避、資料來源與品質標記；但使用者通常只會看到「目前價格、最後更新時間、重新整理」。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q057 原題與選項（來源上下文）</summary>

接著第 57 題，我想定 行情資料的更新與快取策略。

A｜每次打開就即時抓
資料最新，但耗 API quota、速度慢，也很依賴網路。

B｜智慧快取，我推薦

App 先顯示本機最後行情
背景再更新
不同資料有不同 TTL
手動可強制更新
離線仍能看到上次資料
顯示「最後更新時間」

例如即時報價可能幾分鐘更新一次，但公司基本資料、Corporate Action 不需要這麼頻繁。

C｜完整 Market Data Pipeline
除了 B，再加入：

不同市場交易時段
開盤／收盤更新策略
歷史行情分段快取
provider fallback
rate limit 管理
批次 quote
stale-while-revalidate
失敗退避重試
資料品質／來源標記

我會推薦 C，但 UI 維持 B 的簡單感覺。

你選 A / B / C。

</details>

<a id="q058"></a>
### Q058｜Tax Lot Engine

**使用者原答：** 好C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-023](#fv-023)。  
**rc1 契約：** [RC-08](architecture-baseline-v1.0-rc1.md#rc-08)。

好，第 58 題定案：C｜完整 Tax Lot Engine，UI 先簡化。

底層會保留每一批 lot 的取得日期、成本、數量、費用分攤、FX 成本、部分賣出、跨券商移轉，以及 corporate action 對 lot 的調整。V1 UI 可以先只顯示平均成本與已實現／未實現損益，但資料不能只剩一個平均數。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q058 原題與選項（來源上下文）</summary>

接著第 58 題，我想定 投資成本計算方式。這會影響已實現損益、報表和稅務相關資訊。

A｜只用平均成本
所有買進合併成平均成本。最簡單，但不同市場或未來進階分析彈性較低。

B｜支援多種 Cost Basis，我推薦
底層可支援：

Average Cost
FIFO
LIFO
Specific Lot

每個投資帳戶或商品可以有預設方法。賣出時會留下到底消耗哪些 lots 的紀錄，之後損益可以完整重算。

C｜B + Tax Lot Engine
除了 B，再正式建立 tax lot domain，支援：

lot acquisition date
partial lot disposal
corporate action 對 lot 的調整
fee allocation
FX cost basis
lot transfer between brokers
未來依不同市場／稅制加規則

我建議 C 的底層，但 V1 UI 先簡單。平常你可能只看到「平均成本」，但底層不要把 lot 資訊丟掉，未來才能準確處理跨券商、股票分割、部分賣出等情況。

你選 A / B / C。

</details>

<a id="q059"></a>
### Q059｜Benchmark 與 Attribution 願景

**使用者原答：** 好C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-024](#fv-024)。  
**rc1 契約：** [RC-08](architecture-baseline-v1.0-rc1.md#rc-08)。

好，第 59 題定案：C｜完整 Benchmark / Attribution 能力，UI 先維持 B 的清楚程度。

底層會支援 XIRR、TWR、已實現／未實現損益、股息貢獻、FX 貢獻，以及未來 benchmark、資產配置貢獻、最大回撤、波動度等分析；但 V1 不會一開始就把投資頁做成專業交易終端。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q059 原題與選項（來源上下文）</summary>

接著第 59 題，我想定 投資績效怎麼算。

A｜只顯示損益金額 / 報酬率
例如：

成本 100,000
市值 120,000
報酬 +20%

簡單，但沒有考慮資金進出時間。

B｜完整績效指標，我推薦
支援：

Unrealized P&L
Realized P&L
Total Return
XIRR / Money-weighted return
TWR / Time-weighted return
Dividend contribution
FX contribution

這樣可以分辨「股票真的漲很多」和「只是後來加很多本金」。

C｜B + Benchmark / Attribution
除了 B，再加入：

跟指數 benchmark 比較
資產配置貢獻
股票 / 股息 / FX / 手續費對績效的貢獻
各帳戶、各市場分解
年化波動、最大回撤等風險指標

我會建議 C 的資料與計算能力，UI 先做 B。先把績效算準，之後再決定要不要顯示 benchmark 和風險指標。

你選 A / B / C。

</details>

<a id="q060"></a>
### Q060｜通用投資商品模型

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-025](#fv-025)。  
**rc1 契約：** [RC-08](architecture-baseline-v1.0-rc1.md#rc-08)。

好，第 60 題定案：C｜完整資產模型。

底層會用通用 Instrument / Asset 抽象，讓股票、ETF、基金、債券、現金部位，以及未來可能的 REIT、商品、加密資產、選擇權等都能掛在同一套 Portfolio / Lot / Performance 架構上；但 V1 UI 先把常見資產做好，不會一次把所有進階資產類型都攤在介面上。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q060 原題與選項（來源上下文）</summary>

接著第 60 題，我想定 股票／投資資產種類範圍。

A｜只做股票與 ETF：台股、美股、ETF 為主，最單純。
B｜常見投資資產：股票、ETF、基金、債券、現金部位；資料模型以通用 Instrument 為核心。
C｜完整資產模型，我推薦：除了 B，再預留加密資產、黃金／商品、REIT、選擇權等不同 instrument type；每種資產可以有自己的 metadata、價格來源與交易規則，但共用 Portfolio / Lot / Performance 架構。

我會推薦 C，但 V1 UI 先正式支援股票、ETF、基金、債券與現金部位。其他類型先有 domain extension point，不急著全部做畫面。

你選 A / B / C。

</details>

<a id="q061"></a>
### Q061｜金融機構與自訂帳戶群組

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-010](#fv-010)、[FV-039](#fv-039)。  
**rc1 契約：** [RC-05](architecture-baseline-v1.0-rc1.md#rc-05)、[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 61 題定案：C｜Financial Institution + 自訂帳戶群組。

也就是：

FinancialInstitution 是正式 entity，用來承載銀行／券商／信用卡機構資訊、Logo、匯入規則、未來 API connector 等。
自訂群組只是整理與顯示用途，例如「日常資金」「長期投資」「旅遊資金」，不會改變 Ledger 或資產計算邏輯。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q061 原題與選項（來源上下文）</summary>

接著第 61 題，我想定 帳戶、投資、信用卡是否要支援「群組／機構」層級。這會影響資產頁怎麼整理。

A｜沒有機構層級
每個帳戶就是獨立項目，例如：

台新銀行
國泰信用卡
富邦證券

簡單，但帳戶多之後會散。

B｜支援 Financial Institution，我推薦
建立「金融機構」這一層，例如：

純文字
國泰世華
├─ 台幣活存
├─ 美元帳戶
└─ 信用卡

富邦證券
├─ 台股帳戶
└─ 美股帳戶

同一機構可以共用：

Logo
名稱
聯絡資訊
匯入規則
未來 API / Open Banking connector

C｜B + 自訂帳戶群組
除了金融機構，再讓使用者自行建立群組，例如：

日常資金
長期投資
旅遊
不計入淨資產

這類群組純粹是整理視圖，不改變帳務邏輯。

我會推薦 C：金融機構是正式 entity，自訂群組則只是 presentation / organization layer。這樣既有結構，也保有彈性。

你選 A / B / C。

</details>

<a id="q062"></a>
### Q062｜Canonical Entity、Alias 與 Resolution

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-012](#fv-012)。  
**rc1 契約：** [RC-05](architecture-baseline-v1.0-rc1.md#rc-05)、[RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。

好，第 62 題定案：C｜Canonical Entity + Alias + Entity Resolution Engine。

也就是 Merchant、Financial Institution、Instrument 這類主資料都會有穩定 canonical ID，外部名稱只當 alias / source label。匯入、OCR、銀行明細或市場資料遇到不同名稱時，系統會嘗試做 entity resolution，再由你確認是否合併。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q062 原題與選項（來源上下文）</summary>

接著第 62 題，我想定 「商家 / 金融機構 / 投資標的」這些主資料要不要有全域識別與別名機制。這會影響匯入、OCR、自動 matching 和未來同步。

A｜只用名稱
例如 7-ELEVEN、統一超商、7-11 都當不同文字處理。

簡單，但很容易重複。

B｜Canonical Entity + Alias，我推薦
每個正式 entity 有穩定 ID，再支援多個別名。例如：

純文字
Merchant: 統一超商
aliases:
- 7-ELEVEN
- 7-11
- SEVEN

OCR、CSV 匯入或銀行明細讀到不同名稱時，都可以 match 回同一個 entity。

C｜B + Entity Resolution Engine
除了別名，再根據：

名稱相似度
歷史交易
地址
機構代碼
股票代號 / ISIN
OCR 結果

自動推測是不是同一個 entity，再讓使用者確認。

我會推薦 C 的底層能力，V1 UI 先維持 B。這樣未來匯入很多資料時，不會因為名稱差一點點就產生一堆重複商家或標的。

你選 A / B / C。

</details>

<a id="q063"></a>
### Q063｜統一 Matching Engine

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-033](#fv-033)。  
**rc1 契約：** [RC-11](architecture-baseline-v1.0-rc1.md#rc-11)、[RC-18](architecture-baseline-v1.0-rc1.md#rc-18)。

好，第 63 題定案：C｜完整 Matching Engine。

這套 Matching Engine 會成為共用基礎能力，讓手動記帳、OCR、銀行 CSV、信用卡帳單、券商對帳單、Reconciliation 都走同一套 matching pipeline。它可以處理 exact match、fuzzy match、one-to-many / many-to-one，並保留人工確認紀錄來改善後續匹配，但不會自動刪除或合併正式財務資料。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q063 原題與選項（來源上下文）</summary>

接著第 63 題，我想定 重複交易偵測 Duplicate Detection。這對匯入、OCR、手動記帳一起存在時非常重要。

A｜只用完全相同判斷
日期、金額、帳戶完全一致才提示重複。簡單，但容易漏掉。

B｜規則式相似度，我推薦
綜合判斷：

金額
日期時間距離
帳戶
商家
幣別
外部交易 ID
備註／描述
已有 statement match

然後給出「可能重複」分數，但不自動刪資料。

C｜完整 Matching Engine
除了 B，再讓不同來源都走同一套 matching pipeline，例如：

手動輸入 vs 銀行匯入
OCR 收據 vs 信用卡帳單
銀行 CSV vs 已存在交易
券商對帳單 vs 投資交易

並支援：

exact match
fuzzy match
one-to-many / many-to-one
merge suggestion
人工確認紀錄，讓之後 matching 更準

我推薦 C。因為我們已經有 Import Framework、Reconciliation、OCR、Statement Matching，這幾個其實最好共用同一套 Matching Engine。

你選 A / B / C。

</details>

<a id="q064"></a>
### Q064｜完整交易生命週期

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-014](#fv-014)。  
**rc1 契約：** [RC-03](architecture-baseline-v1.0-rc1.md#rc-03)、[RC-07](architecture-baseline-v1.0-rc1.md#rc-07)。

好，第 64 題定案：C｜完整交易生命週期模型。

底層會把 Authorized / Pending / Posted / Cleared / Reconciled / Voided 等狀態與真正的退款、沖銷事件分開。也就是「狀態改變」和「產生新的財務事件」不是同一件事；一般 UI 則只顯示使用者需要理解的「處理中／已入帳／已對帳」等簡化狀態。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q064 原題與選項（來源上下文）</summary>

接著第 64 題，我想定 交易狀態模型。這會影響信用卡未入帳、銀行 pending、退款處理和 reconciliation。

A｜只有已入帳 / 已刪除
最簡單，但無法很好表示銀行「處理中」或信用卡授權中。

B｜標準交易狀態
例如：

Draft
Pending
Posted
Cleared
Reconciled
Voided

已經能涵蓋大部分情況。

C｜狀態 + 財務生命週期，我推薦
除了 B，再把「狀態」和「事件」分開：

例如刷卡：

Authorized → Pending → Posted → Cleared → Reconciled

退款則不是把原交易改成 refunded，而是：

Original Transaction
↓
Refund / Reversal Event

如果銀行取消 pending transaction，也留下明確狀態轉換，而不是直接消失。

這樣特別適合我們前面選的高標準 Ledger、信用卡 Statement、Reconciliation 和 Audit Trail。

我推薦 C，但一般 UI 不需要把所有狀態名稱都顯示出來；平常只顯示像「處理中」「已入帳」「已對帳」。

你選 A / B / C。

</details>

<a id="q065"></a>
### Q065｜多種金融日期語意

**使用者原答：** 好c  
**當期範圍：** CORE。  
**願景主題：** [FV-015](#fv-015)。  
**rc1 契約：** [RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。

好，第 65 題定案：C｜完整 Financial Date Model，UI 維持簡潔。

底層會區分 occurredAt / authorizedAt / postedAt / settledAt / valueDate / importedAt 等時間語意，但不是每筆都強制有值；一般畫面仍以「實際發生時間」為主，其他日期只在明細、帳單與對帳流程需要時顯示。

<details>
<summary>Q065 原題與選項（來源上下文）</summary>

接著第 65 題剛好要處理一個會跟這套生命週期直接相關的細節：一筆交易到底要存幾種日期？

A｜只有一個交易日期
例如 9/26 刷卡，就只有 2026/09/26。簡單，但銀行／信用卡實際入帳可能是 9/27 或 9/28。

B｜交易日期 + 入帳日期
保存：

transactionDate：你實際消費的日期
postedDate：銀行或信用卡正式入帳的日期

一般記帳已經相當夠用。

C｜完整 Financial Date Model，我推薦
視來源保存不同時間語意：

occurredAt：事件實際發生時間
authorizedAt：刷卡授權時間
postedAt：金融機構正式入帳
settledAt：實際清算完成
valueDate：必要時保留金融機構的 value date
importedAt：我們何時取得這筆資料

不代表每筆交易全部都要有值，而是有資料時能正確保存。

例如：

純文字
9/26 19:32  餐廳刷卡
    ↓ authorized

9/27         信用卡正式入帳
    ↓ posted

10/05        出現在帳單並完成對帳

UI 平常仍然只突出「9/26 消費」，其他日期放詳細資料或對帳流程裡。

我建議 C 的資料模型，UI 維持 B 的簡潔度。尤其我們已經要做信用卡、Statement Import、Reconciliation、投資和未來銀行資料串接，只有一個日期之後很容易不夠用。

你選 A / B / C。

</details>

<a id="q066"></a>
### Q066｜Content-addressed 附件儲存

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-072](#fv-072)。  
**rc1 契約：** [RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。

好，第 66 題定案：C｜Content-addressed Storage。

也就是附件、收據、PDF 不直接綁在交易紀錄裡，而是走獨立 blob storage；檔案用內容 hash / 穩定 identity 管理，可以做去重、完整性驗證、本機與雲端共用同一套識別。這樣同一張收據被重複加入時，不需要真的存兩份；Ledger revision 也只引用同一個附件，不會一直複製檔案。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q066 原題與選項（來源上下文）</summary>

接著第 66 題，我想定 附件與收據檔案的實際儲存策略。前面我們已經確定會支援 OCR、圖片與 PDF，但還沒決定檔案怎麼存。

A｜全部直接存在 App 本機資料夾
最簡單，DB 只存路徑。缺點是備份、搬機、同步都比較麻煩。

B｜本機 Object Store + Metadata，我推薦
附件檔案和 Ledger 分開：

DB 只存 attachment metadata
檔案用穩定 UUID 命名
SHA-256 checksum
MIME type
原始檔名
建立時間
縮圖／預覽版本
是否已備份
OCR 狀態

這樣 Ledger revision 不會重複複製圖片。

C｜Content-addressed Storage
在 B 的基礎上，檔案用內容 hash 當 identity，例如同一張收據被重複加入兩次，只存一份實體檔案。

還可以做：

deduplication
integrity verification
local/cloud 同一套 blob identity
future sync 更乾淨

我會推薦 C，因為我們已經有版本化備份、未來 sync、OCR、附件去重需求。UI 完全不用知道這些複雜度。

你選 A / B / C。

</details>

<a id="q067"></a>
### Q067｜本機 OCR 與主動雲端 fallback

**使用者原答：** B  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-031](#fv-031)。  
**rc1 契約：** [RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。

好，第 67 題定案：B｜本機 OCR 優先，必要時雲端 fallback。

原則會是：

預設先走本機 OCR
本機辨識結果會有 confidence
信心不足時才提示是否改用雲端辨識
雲端只拿該張收據／附件，不會拿整個帳本
使用者不同意時，核心記帳仍能完整運作
OCR 結果一律先進 staging / 表單預填，不直接寫入 Ledger

這樣符合我們前面的 local-first 與隱私方向。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q067 原題與選項（來源上下文）</summary>

接著第 67 題，我想定 OCR 要在本機做，還是走雲端服務。

A｜完全本機 OCR
優點是隱私最好、離線可用；缺點是不同格式收據、表格、發票的辨識能力可能受限。

B｜本機優先＋雲端 fallback，我推薦
流程可以是：

本機 OCR → 信心度判斷 → 必要時才詢問是否用雲端辨識

而且雲端 OCR 不直接拿完整帳本，只處理使用者指定的收據/附件。

C｜完全雲端 OCR
辨識能力通常比較強，也容易升級模型，但會讓核心記帳更依賴網路與第三方服務。

我建議 B。這跟我們整體的 local-first 原則最一致，也能保留未來更強辨識能力。

你選 A / B / C。

</details>

<a id="q068"></a>
### Q068｜結構化地點與智慧地點預留

**使用者原答：** B預留C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-013](#fv-013)、[FV-012](#fv-012)。  
**rc1 契約：** [RC-05](architecture-baseline-v1.0-rc1.md#rc-05)、[RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。

好，第 68 題定案：B｜結構化地點，底層預留 C｜智慧地點功能。

交易可以選擇保存地點名稱、地址、緯經度、城市／國家與來源，但位置永遠不是必填。未來如果加入附近商家建議、地點匹配或 geofence，也會採 opt-in，不會背景持續追蹤。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q068 原題與選項（來源上下文）</summary>

接著第 68 題，我想定 地點資訊 Location 的角色。前面交易資訊有預留地點，但還沒決定做到哪個程度。

A｜只手動填文字
例如：

高雄
東京
某間店

簡單，但搜尋與分析能力有限。

B｜結構化地點，我推薦
可以選擇儲存：

地點名稱
地址
緯經度
城市／國家
來源：手動／OCR／系統定位

但完全選配，不會要求每筆交易取得位置。

這樣未來可以做：

旅遊支出
某城市消費
常去商家
地點搜尋

C｜智慧地點功能
除了 B，再支援：

新增交易時建議附近商家
自動推測消費地點
地點 geofence
到某地時提醒記帳
商家位置匹配

功能更完整，但牽涉定位權限、耗電與隱私。

我建議 B，預留 C。

平常不主動追蹤位置，只有使用者需要時才取用；未來若做附近商家建議，也必須是明確 opt-in。

你選 A / B / C。

</details>

<a id="q069"></a>
### Q069｜Merchant、Branch 與 Place Resolution

**使用者原答：** 好C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-012](#fv-012)。  
**rc1 契約：** [RC-05](architecture-baseline-v1.0-rc1.md#rc-05)、[RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。

好，第 69 題定案：C｜Merchant + Branch + Place Resolution。

也就是商家本體和分店分開建模；交易可以只連 Merchant，也可以精確到 Branch。未來 OCR、GPS、地址、銀行描述都可以一起做分店推測，但只是建議，不會硬改交易內容。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q069 原題與選項（來源上下文）</summary>

接著第 69 題，我想定 商家與地點的關係模型。

A｜一個商家只有一個地點
例如「全聯」就是一個 Merchant + 一個地址。簡單，但連鎖店會很難處理。

B｜Merchant + Branch，我推薦
例如：

純文字
Merchant：全聯
├─ 高雄 A 店
├─ 高雄 B 店
└─ 台北 C 店

交易可以只記 Merchant，也可以進一步連到特定 Branch。這樣報表可以看「全聯總共花多少」，也可以看「哪一家分店」。

C｜B + Place Resolution
除了 B，再讓 OCR、GPS、地址、銀行交易描述共同判斷是哪個 Branch；系統會給建議，但不強制。

我建議 C 的底層能力，V1 UI 先做 B。這樣之後商家辨識會更準，也不會把每個分店當成不同 Merchant。

你選 A / B / C。

</details>

<a id="q070"></a>
### Q070｜Receipt／Invoice 與台灣發票能力

**使用者原答：** 好C不過目前沒API可以抓發票的樣子  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-032](#fv-032)。  
**rc1 契約：** [RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。

對，你的理解可以稍微修正成：

不是完全沒有 API，而是沒有「一般個人 App 可以直接無條件串接、登入後就把所有個人發票抓回來」這麼簡單的公開 API。

財政部目前仍有正式的電子發票 API 規範，而且包含像「載具發票表頭查詢、載具發票明細查詢」等介面；但開發者必須提出申請，經審核後取得 AppID 與 APIKey，並受官方使用規範約束。
法規共用系統
+1

所以我們第 70 題仍然可以選 C，但我會把實作策略改成：

資料模型完整支援台灣電子發票，但 V1 不把官方 API 當成必要依賴。

V1 先做：

手動建立發票
OCR 辨識
發票號碼／日期／商家／金額結構化
QR Code / Barcode 掃描能力預留
發票與 Transaction / Receipt 關聯
重複發票偵測
中獎狀態欄位預留

然後另外定義：

純文字
InvoiceSourceAdapter
├─ Manual
├─ OCR
├─ QR Code
├─ Import
└─ TaiwanEInvoiceApi   ← 未來有條件再接

這樣未來真的取得官方 API 資格，只加一個 adapter 就可以接進現有資料模型，完全不需要重做發票系統。這也符合我們一路上的原則：第三方服務可以換，核心 Domain 不依賴它。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q070 原題與選項（來源上下文）</summary>

接著第 70 題，我想定 發票 / 收據號碼要不要做成正式 entity，因為這會影響 OCR、重複偵測和未來台灣電子發票整合。

A｜只存在交易備註
最簡單，但之後很難查重或做發票管理。

B｜結構化 Receipt / Invoice，我推薦
每張收據或發票可以有：

類型
號碼
開立日期
商家
金額
幣別
附件
OCR 結果
對應交易
是否已驗證

這樣可以做：

發票號碼搜尋
重複收據偵測
一張收據對多筆 split transaction
OCR 後自動帶入

C｜B + 台灣電子發票整合預留
除了 B，再預留：

載具
發票字軌／號碼
隨機碼
QR code payload
中獎狀態
未來財政部電子發票 API / 匯入 adapter

V1 不一定馬上連政府服務，但 schema 一開始就能承接。

我會推薦 C，因為你主要使用情境在台灣，而且一旦之後想加電子發票，若前面只存一段備註，重構會比較麻煩。

你選 A / B / C。

</details>

<a id="q071"></a>
### Q071｜QR 掃描與 Matching

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-032](#fv-032)、[FV-033](#fv-033)。  
**rc1 契約：** [RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。

好，第 71 題定案：C｜QR Code 掃描 + 自動 Matching。

流程會是：

掃描電子發票 QR Code
解析可取得的發票資訊
建立/更新 Receipt / Invoice staging 資料
丟進 Matching Engine
嘗試比對既有交易
高度吻合時提示「是否附加到既有交易」
找不到合適交易時，才建立新的記帳草稿

這樣可以大幅降低「先手動記帳，之後掃發票又多一筆」的重複問題，而且仍然維持 使用者確認後才真正寫入 Ledger。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q071 原題與選項（來源上下文）</summary>

第 71 題｜電子發票要不要支援掃 QR Code？

A｜不做
只靠 OCR／手動輸入。

B｜支援 QR Code，我推薦
掃台灣電子發票 QR Code 後，自動解析能取得的資料，再預填發票／交易內容；解析結果仍需確認才能入帳。

C｜B + 自動 Matching
掃完 QR Code 後，再交給我們前面的 Matching Engine，自動找：

「這是不是昨天已經手動記過的全聯 1,280 元？」

如果高度吻合，就提示你把 Receipt / Invoice 掛到既有交易，而不是再建立一筆重複支出。

我會選 C。因為 Matching Engine 我們反正已經決定要做，QR Code 很適合直接接進去。

你選 A / B / C。

</details>

<a id="q072"></a>
### Q072｜Financial Inbox 與 Staging Workflow

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-030](#fv-030)。  
**rc1 契約：** [RC-11](architecture-baseline-v1.0-rc1.md#rc-11)、[RC-18](architecture-baseline-v1.0-rc1.md#rc-18)。

好，第 72 題定案：C｜完整 Financial Inbox / Staging Workflow。

這會變成我們整個 App 很重要的一層：所有「還不能直接進 Ledger」的資料，先統一進 Inbox，例如 OCR 收據、QR 發票、銀行匯入候選、信用卡未匹配項目、定期交易待確認、重複交易候選，以及手動記到一半的草稿。

核心規則會是：

純文字
External / User Input
        ↓
Financial Inbox
        ↓
Validate / Match / Review
        ↓
Confirm
        ↓
Ledger

在 Inbox 裡的東西不影響餘額、不進報表、不算預算；只有確認後才正式產生 Ledger event。這樣資料安全性會高很多，也能避免 OCR、匯入或自動化誤判直接污染帳本。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q072 原題與選項（來源上下文）</summary>

接著第 72 題，我想定 交易的「草稿 / 暫存」能力。這對 OCR、QR、匯入、複雜拆分交易都會用到。

第 72 題｜Draft 要做到哪一層？

A｜沒有 Draft
進新增頁沒存就直接丟掉。

最簡單，但掃收據、拆分交易做到一半時比較痛苦。

B｜自動保存草稿，我推薦
新增交易過程自動保存本機草稿，例如：

已輸入的金額
帳戶
分類
OCR 結果
附件
拆分內容

App 被關掉後重新開啟，也可以繼續。

但 Draft 不影響 Ledger、不影響餘額、不進正式報表。

C｜完整 Inbox / Staging Workflow
除了 B，再把所有「尚未確認的財務資料」統一放到 Inbox，例如：

OCR 收據
QR 發票
銀行匯入候選
信用卡 statement unmatched items
未確認定期交易
未解決的 duplicate/matching
手動新增到一半的草稿

你可以在一個「待處理」入口把它們逐一確認、合併、忽略或正式入帳。

我會推薦 C。

因為我們現在已經有 OCR、QR、Import、Matching、Recurring、Statement 等很多「資料先進來，但不能立刻成為正式帳務」的來源。與其每個模組各做一個暫存區，不如統一成一個 Financial Inbox / Staging Layer。

你選 A / B / C。

</details>

<a id="q073"></a>
### Q073｜Inbox 批次處理與規則自動化預留

**使用者原答：** B預留c  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-030](#fv-030)。  
**rc1 契約：** [RC-11](architecture-baseline-v1.0-rc1.md#rc-11)。

好，第 73 題定案：B｜批次處理，底層預留 C｜規則式自動處理。

V1 的 Financial Inbox 會支援批次確認、忽略、套分類、套 Tag、指定帳戶，以及接受高信心 matching；但像金額異常、退款、跨帳戶、投資、信用卡特殊交易這類高風險項目仍維持逐筆確認。之後如果要加「Netflix 自動分類到娛樂」這種 rule engine，也能直接接上。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q073 原題與選項（來源上下文）</summary>

接著第 73 題，我想定 Inbox 要不要支援「批次處理」。

A｜逐筆處理
每一筆都打開、確認、儲存。最安全，但如果一次匯入 100 筆銀行交易會很累。

B｜批次選取處理，我推薦
可以一次選很多筆：

批次確認
批次忽略
批次套用分類
批次套用 Tag
批次指定帳戶
批次接受高信心 matching

但涉及金額、跨帳戶、退款、投資等高風險項目仍要求逐筆確認。

C｜規則式自動處理
除了 B，再讓使用者建立規則，例如：

商家 = Netflix
→ 分類 = 娛樂
→ 帳戶 = 國泰信用卡
→ 自動確認

效率最高，但需要很嚴格的 rule safety。

我建議 B，底層預留 C。先把批次處理做好，再逐步加入安全的自動化規則。

你選 A / B / C。

</details>

<a id="q074"></a>
### Q074｜Rule Engine 與完整 Automation 預留

**使用者原答：** 好，B預留C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-029](#fv-029)。  
**rc1 契約：** [RC-10](architecture-baseline-v1.0-rc1.md#rc-10)。

好，第 74 題定案：B｜明確 Rule Engine，底層預留 C｜完整 Automation Engine。

V1 先讓規則負責「預填、建議、批次套用」，不直接繞過使用者確認；但底層條件模型會預留未來做到低風險來源自動入帳的能力。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q074 原題與選項（來源上下文）</summary>

接著第 74 題，我想定 自動分類／規則引擎的正式定位。

A｜只做商家記憶
系統記住過去選擇，提供建議，不建立正式規則。

B｜明確 Rule Engine，我推薦
可以建立像：

商家 = Netflix
→ 分類 = 娛樂
→ Tag = 訂閱

或：

帳戶 = 某信用卡
且金額 < 500
且 Merchant = 7-ELEVEN
→ 建議分類 = 飲食

規則預設只做「預填／建議」，不是直接入帳。

C｜完整 Automation Engine
除了 B，再允許某些低風險來源直接自動確認入帳，例如可信銀行來源 + 高信心 matching + 明確規則。

功能最強，但風險也最高。

我建議 B，底層預留 C。這樣先把規則語言和條件模型做好，但 V1 不讓自動化直接繞過使用者確認。

你選 A / B / C。

</details>

<a id="q075"></a>
### Q075｜Priority 與 Specificity 衝突規則

**使用者原答：** 好B  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-029](#fv-029)。  
**rc1 契約：** [RC-10](architecture-baseline-v1.0-rc1.md#rc-10)。

好，第 75 題定案：B｜明確 Priority + Specificity。

規則會有可理解的優先序；同優先序時，條件越具體者優先。如果還是衝突，就不硬猜，直接進 Inbox 顯示「規則衝突」讓你確認。未來可以用學習模型做建議，但不能黑盒式改正式規則。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q075 原題與選項（來源上下文）</summary>

接著第 75 題，我想定 規則優先順序與衝突怎麼處理。這很重要，因為未來規則多了，一筆交易可能同時命中好幾條。

A｜先建立的規則優先
簡單，但久了很難理解為什麼某條規則生效。

B｜明確 Priority + Specificity，我推薦
每條規則都有 priority；同 priority 時，條件更精確的規則優先。

例如：

Merchant = 7-ELEVEN
→ 餐飲

以及：

Merchant = 7-ELEVEN + Account = 公司信用卡
→ 公司報帳

第二條因為更精確，所以優先。

如果兩條同等級規則仍衝突，就不自動決定，進 Inbox 顯示「規則衝突」。

C｜讓系統自動學習哪條規則比較合理
可以根據過去使用者選擇調整優先順序，但可解釋性較低。

我建議 B，未來可以在建議層吸收 C，但不能讓黑盒模型直接改正式規則優先序。

你選 A / B / C。

</details>

<a id="q076"></a>
### Q076｜共用 Predicate／Expression DSL

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-029](#fv-029)。  
**rc1 契約：** [RC-10](architecture-baseline-v1.0-rc1.md#rc-10)。

好，第 76 題定案：C｜完整 DSL / Expression Engine，UI 先維持 B 的簡單條件組合。

這代表搜尋、報表、預算、Rule Engine、Automation 之後都共用同一套 Predicate / Expression 模型，不會各自長一套條件語言。底層可以支援 AND / OR / NOT / 比較 / 範圍 / 集合包含 等邏輯，但一般 UI 不會一開始就暴露成程式語法。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q076 原題與選項（來源上下文）</summary>

接著第 76 題，我想定 搜尋、報表、預算、Rule Engine 要不要共用同一套 Filter/Predicate DSL。這會影響整個系統的一致性。

A｜各模組自己定條件
開發快，但長期會出現「報表支援某條件、預算卻不支援」這種不一致。

B｜共用統一條件模型，我推薦
例如都共用：

日期區間
帳戶
分類
Tag
商家
幣別
金額區間
交易類型
狀態
附件有無
投資標的等

不同模組只限制自己允許使用哪些條件。

C｜完整 DSL / Expression Engine
例如可以組：

(Merchant = X AND Amount > 500) OR Tag contains "旅遊"

功能最強，但 UI 不一定需要一開始暴露完整布林邏輯。

我建議 C 的底層能力，UI 先維持 B。這樣搜尋、報表、預算、Automation 都可以共用同一套 Predicate AST / evaluator。

你選 A / B / C。

</details>

<a id="q077"></a>
### Q077｜可序列化 AST 與版本化 schema

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-029](#fv-029)。  
**rc1 契約：** [RC-10](architecture-baseline-v1.0-rc1.md#rc-10)。

好，第 77 題定案：C｜可序列化 AST + Versioned Expression Schema。

也就是規則、搜尋條件、預算條件、自動化條件都會以結構化 AST 儲存，並帶明確版本，例如 predicate_v1。未來新增運算子或條件能力時，會走 migration，不讓舊規則失效。這也能直接接到之後的自然語言搜尋：自然語言只是轉成同一套 AST，不另造一條查詢路徑。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q077 原題與選項（來源上下文）</summary>

接著第 77 題，我想定 這套 DSL 要不要可版本化與可序列化。這會影響備份、同步、migration 和未來自然語言搜尋。

A｜只存在記憶體結構
最簡單，但規則格式變更時很難升級。

B｜可序列化 AST，我推薦
每個條件都能存成結構化資料，例如：

純文字
AND
├─ Merchant = Netflix
└─ Amount > 300

可以放進 DB、備份、同步，也能做 migration。

C｜B + Versioned Expression Schema
除了 B，再給 expression schema 明確版本，例如 predicate_v1 / v2，未來語法擴充時可以逐版 migration，不會讓舊規則壞掉。

我建議 C，因為我們前面已經選完整 Data Evolution Framework，這裡最好一致。

你選 A / B / C。

</details>

<a id="q078"></a>
### Q078｜Storage Lifecycle Engine

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-073](#fv-073)。  
**rc1 契約：** [RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。

好，第 78 題定案：C｜完整 Storage Lifecycle Engine，V1 UI 先維持 B 的簡單管理方式。

底層會有 retention policy、storage quota、revision compaction、attachment dedup GC、cache/projection 清理、diagnostics log 保留期限，以及清理前 integrity check。正式財務歷史會優先保留；可重建資料才會積極清理。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q078 原題與選項（來源上下文）</summary>

接著第 78 題，我想定 刪除資料的保留期限 / Garbage Collection。我們前面用了 soft delete、tombstone、revision、content-addressed attachments，如果完全永不清理，長期還是會累積不少無效資料。

A｜永遠不自動清理
所有 tombstone、舊 revision、未引用附件永久保留。最安全，但長期會持續膨脹。

B｜分級清理，我推薦
不同資料有不同 retention policy，例如：

正式財務 revision：長期保留
sync tombstone：確認所有裝置同步後，再保留一段安全期
未使用草稿：例如 30/90 天後可清理
未引用附件：進垃圾桶後延遲刪除
cache / projection：隨時可重建，所以可以自動清
diagnostics log：只保留最近一段時間

而且清理前可以先做 integrity check。

C｜完整 Storage Lifecycle Engine
除了 B，再加入：

storage quota
自動壓縮
archive tier
revision compaction
attachment dedup GC
可預覽「哪些資料會被清理」
備份確認後再執行清理

我會推薦 C 的底層能力，但 V1 UI 先做 B。這樣多年使用後資料仍可控，但不會犧牲財務歷史完整性。

你選 A / B / C。

</details>

<a id="q079"></a>
### Q079｜可驗證 Restore

**使用者原答：** C  
**當期範圍：** CORE。  
**願景主題：** [FV-053](#fv-053)。  
**rc1 契約：** [RC-14](architecture-baseline-v1.0-rc1.md#rc-14)。

好，第 79 題定案：C｜可驗證還原流程。

備份完成不只做 checksum，而是會有隔離式 restore dry-run、migration compatibility、Ledger invariant、附件完整性與 projection 重建驗證；真正還原前也會先替目前資料做 safety backup，還原失敗不能碰壞現有帳本。

<details>
<summary>Q079 原題與選項（來源上下文）</summary>

接著第 79 題，我想定 備份與還原的驗證機制。既然這個 App 會長期存很多重要財務資料，我不希望「有備份檔」就等於「真的能還原」。

A｜基本備份驗證
備份完成後只確認檔案存在、大小正常。

B｜完整 Integrity Verification
備份完成後檢查：

checksum
manifest
DB schema/version
附件引用是否完整
必要檔案是否缺失
加密資料是否可讀

但不真的執行還原。

C｜可驗證還原流程，我推薦
除了 B，再做：

備份後可在隔離環境做 restore dry-run
migration compatibility check
Ledger invariant check
attachment integrity
projection 可重建驗證
還原失敗不碰目前正式資料
還原前自動建立 safety backup
還原完成後再次做完整性檢查

換句話說，不只是：

「我有備份」

而是：

「這份備份已經被證明能還原成一致的帳本。」

我推薦 C，尤其我們前面已經選了完整 Data Evolution Framework 和高標準 Ledger。

你選 A / B / C。

</details>

<a id="q080"></a>
### Q080｜分層 Health Check

**使用者原答：** C  
**當期範圍：** CORE。  
**願景主題：** [FV-079](#fv-079)。  
**rc1 契約：** [RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。

好，第 80 題定案：C｜分層 Health Check。

App 每次啟動只跑輕量 Fast Check；更新、還原、異常關閉或手動診斷時，再跑 Deep Check。若只是 projection / cache 壞掉可以自動重建；如果偵測到正式 Ledger 本身有一致性問題，就進 Recovery Mode，停止新的寫入，不會偷偷「修到看起來正常」。

<details>
<summary>Q080 原題與選項（來源上下文）</summary>

接著第 80 題，我想定 App 啟動時的資料健康檢查要做到哪一層。

A｜只檢查 DB 能不能開
能開就進 App，最簡單。

B｜基本 Health Check
啟動時快速檢查：

DB schema version
migration 狀態
必要 metadata
encryption key
上次關閉是否正常
是否有未完成 restore / import

有異常才進修復流程。

C｜分層 Health Check，我推薦
分成兩種：

Fast Check：每次啟動跑，必須很快
Deep Check：更新後、還原後、異常關機後，或使用者手動執行

Deep Check 可以驗證：

Ledger invariant
orphan records
attachment reference
projection consistency
reconciliation state
revision chain
sync metadata
content hash

如果只是 projection 壞掉，就自動重建；如果是正式 Ledger 有問題，就停止寫入並進 recovery mode，不偷偷修資料。

我建議 C。這樣平常啟動不會變慢，但真的有資料風險時能及早發現。

你選 A / B / C。

</details>

<a id="q081"></a>
### Q081｜Recovery Center

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-079](#fv-079)、[FV-076](#fv-076)。  
**rc1 契約：** [RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。

好，第 81 題定案：C｜完整 Recovery Center。

遇到重大資料異常時，App 會先進唯讀保護狀態，再提供 emergency backup、診斷、projection/index 重建、revision chain 檢查、附件驗證、健康備份比對等修復流程。任何可能改到正式 Ledger 的修復，都必須明確確認，修復後再跑一次 Deep Check 才能恢復正常寫入。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q081 原題與選項（來源上下文）</summary>

接著第 81 題，我想定 Recovery Mode 要做到哪個程度。這會決定真的遇到資料損壞時，我們能不能安全救回來。

A｜只顯示錯誤
偵測到重大問題後停止使用，要求從備份還原。

最安全，但可能其實只是少數資料有問題，也完全進不了 App。

B｜唯讀 Recovery Mode
App 可以開啟，但：

禁止新增／修改／刪除
可以查看現有交易
可以匯出資料
可以跑診斷
可以選擇備份還原
可以嘗試重建 projection

不讓問題繼續擴大。

C｜完整 Recovery Center，我推薦
除了 B，再提供有控制的修復流程：

顯示是哪一類資料異常
建立 emergency backup
隔離損壞資料
重建可重建的 projection / index
檢查 revision chain
驗證 attachment
從最近健康 snapshot / backup 比較
產生 diagnostics package
修復完成後再次跑 Deep Check
任何會改正式 Ledger 的修復都要明確確認

我推薦 C，但 UI 不需要很工程師化；平常根本看不到，只有真的出問題才進 Recovery Center。

你選 A / B / C。

</details>

<a id="q082"></a>
### Q082｜Durable Job Engine

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-067](#fv-067)。  
**rc1 契約：** [RC-19](architecture-baseline-v1.0-rc1.md#rc-19)。

好，第 82 題定案：C｜完整 Durable Job Engine。

會有持久化 job state、dependency/workflow、checkpoint、idempotency、retry/backoff、priority、cancellation 與 job version migration。像備份、Calendar sync、市場資料更新、清理、健康檢查這些可靠性要求高的工作會走這套；一般 UI refresh 不會濫用 durable job。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q082 原題與選項（來源上下文）</summary>

接著第 82 題，我想定 背景工作 / Scheduler 架構。我們現在已經有備份、定期交易、信用卡提醒、Google Calendar、市場資料更新等很多背景任務，這一層不能各模組自己亂排。

第 82 題｜背景任務怎麼設計？

A｜各功能自己排程
例如備份自己設 timer、股票自己更新、提醒自己排通知。

開發快，但長期容易重複執行、互相搶資源。

B｜統一 Background Job Manager，我推薦
所有背景工作都註冊到同一套 scheduler：

純文字
BackupJob
RecurringTransactionJob
ReminderJob
CalendarSyncJob
MarketDataRefreshJob
CleanupJob
HealthCheckJob

統一管理：

失敗重試
backoff
網路需求
充電條件
job 去重
執行紀錄
Android 背景限制

C｜完整 Durable Job Engine
除了 B，再加入：

job 狀態持久化
dependency / workflow
checkpoint
idempotency key
crash 後續跑
exactly-once effect 的防重機制
priority
cancellation
job version migration

例如：

純文字
Cloud Backup
  ↓
Upload blobs
  ↓
Upload metadata
  ↓
Verify backup
  ↓
Mark snapshot healthy

App 中途被 Android 殺掉，下次也能從安全 checkpoint 繼續，而不是整套重來或重複上傳。

我推薦 C，但只讓真正需要可靠執行的任務使用 durable workflow；一般簡單 UI refresh 不要丟進去。

你選 A / B / C。

</details>

<a id="q083"></a>
### Q083｜Dead Letter／Recovery Queue

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-067](#fv-067)。  
**rc1 契約：** [RC-19](architecture-baseline-v1.0-rc1.md#rc-19)。

好，第 83 題定案：C｜完整 Dead Letter / Recovery Queue。

也就是 Durable Job 超過重試上限後，不會無限重跑，而是進 DLQ；可以保留失敗原因、依賴 chain、checkpoint、診斷資訊，必要時人工重新執行。這對備份、Calendar sync、行情更新這類背景流程會很重要。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q083 原題與選項（來源上下文）</summary>

接著第 83 題，我想定 背景任務失敗時要不要做統一錯誤佇列。

A｜各模組自己處理失敗
例如 BackupJob 失敗就自己重試，CalendarSyncJob 也自己管。

B｜統一 Failure Queue，我推薦
所有 durable job 失敗都會留下：

job type
failure reason
retry count
last attempted time
是否可自動重試
是否需要使用者介入

App 可以有一個很簡單的「待處理問題」入口。

C｜完整 Dead Letter / Recovery Queue
除了 B，再加入：

超過重試上限後進 Dead Letter Queue
可人工重新執行
可查看依賴 chain
可輸出 diagnostics
某些 job 可從 checkpoint 繼續
避免同一失敗任務無限重跑

我會推薦 C，因為既然我們已經選 Durable Job Engine，沒有 DLQ 會少一塊很重要的可靠性機制。

你選 A / B / C。

</details>

<a id="q084"></a>
### Q084｜分級 Secrets

**使用者原答：** C  
**當期範圍：** CORE。  
**願景主題：** [FV-082](#fv-082)。  
**rc1 契約：** [RC-23](architecture-baseline-v1.0-rc1.md#rc-23)。

好，第 84 題定案：C｜分級 Secrets 架構。

也就是使用者 OAuth token 放平台安全儲存，第三方 private API key 放 Backend secret store，server-to-server credential 不進 App；所有外部服務透過 CredentialProvider + ServiceAdapter 取用憑證，Domain / UI 不直接碰 secrets。這樣之後做 key rotation、換 Provider、撤銷憑證都比較安全。

<details>
<summary>Q084 原題與選項（來源上下文）</summary>

接著第 84 題，我想定 第三方 API 金鑰與 Secrets 怎麼管理。我們現在已經有行情 Provider、雲端 OCR fallback、Google Calendar、未來電子發票等整合，這一題不能隨便處理。

第 84 題｜Secrets / API Key 策略

A｜直接放 App 內
例如把行情 API key 編進 Flutter App。

最簡單，但 APK 被反編譯後通常就能找到 key，我不推薦。

B｜敏感 Secrets 全放 Backend
App 只呼叫我們自己的 Backend Adapter：

純文字
App
 ↓
Backend
 ↓
Market Data / OCR / Other APIs

第三方 API key 永遠不進 App。

安全性高，但所有第三方服務都要經過 backend。

C｜分級 Secrets 架構，我推薦
依 credential 類型分開處理：

使用者自己的 OAuth token
→ Android Keystore / iOS Keychain
可公開的 client identifier
→ App config
第三方 private API key
→ Backend secret store
Server-to-server credential
→ 只存在 server
可輪替的 provider credential
→ 支援 key rotation / versioning

而且每個外部 Provider 都透過：

純文字
CredentialProvider
ServiceAdapter

取得 credential，不讓 Domain 或 UI 直接讀 secret。

這樣未來換行情 Provider、撤銷某個 API key、甚至改成自有 Backend，都不需要改核心 App。

我建議 C。

你選 A / B / C。

</details>

<a id="q085"></a>
### Q085｜Build Flavor 與 Runtime Config

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-083](#fv-083)。  
**rc1 契約：** [RC-23](architecture-baseline-v1.0-rc1.md#rc-23)。

好，第 85 題定案：C｜Build Flavor + Runtime Config 混合。

也就是 dev / staging / prod 由 build flavor 決定安全邊界；runtime config 只控制可以安全動態調整的非敏感設定，而且會有 schema version、簽章驗證與 fallback default。這樣更新 API endpoint、功能開關或 rollout 設定時，不一定每次都要重新打包 App。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q085 原題與選項（來源上下文）</summary>

接著第 85 題，我想定 設定檔與環境切換，因為我們之後一定會有 dev / staging / production、不同 API endpoint、不同更新 channel。

A｜用 build flavor
例如：

dev
staging
prod

每個 flavor 有自己的 endpoint、app name、icon、logging 設定。

B｜Runtime config
App 啟動時讀一份簽署設定，部分非敏感參數可以不重新編譯就調整。

C｜A + B 混合，我推薦

Build flavor 決定安全邊界與主要環境
Runtime config 只控制可安全動態調整的項目
敏感 key 不放 runtime config
config 有 schema version / signature / fallback defaults

這樣既安全又有彈性。

我推薦 C。你選 A / B / C。

</details>

<a id="q086"></a>
### Q086｜Feature Capability System

**使用者原答：** C  
**當期範圍：** CORE。  
**願景主題：** [FV-084](#fv-084)、[FV-001](#fv-001)。  
**rc1 契約：** [RC-01](architecture-baseline-v1.0-rc1.md#rc-01)。

好，第 86 題定案：C｜完整 Feature Capability System。

之後「程式已經有能力」和「正式開放給使用者」會是兩件事。像多裝置同步、自然語言搜尋、Dark Mode、進階投資 UI，都可以先完成底層與測試，再透過 capability 狀態逐步開放；也能限制只在 dev/staging 出現，避免 Codex 不小心把半成品功能直接放進正式版。

<details>
<summary>Q086 原題與選項（來源上下文）</summary>

接著第 86 題，我想定 Feature Flag / 漸進式功能開放。這對我們現在「底層先做完整、UI 後續逐步接上」的策略特別重要。

A｜不做 Feature Flag
功能寫完就直接出現在 UI。最單純，但遇到尚未成熟的投資、同步、進階預算功能時比較難控制。

B｜基本 Feature Flag
例如：

純文字
investmentAdvancedUi = false
naturalLanguageSearch = false
multiDeviceSync = false
darkMode = false

底層能力可以存在，但 UI 先不開放。等測試完成再打開。

C｜完整 Feature Capability System，我推薦
除了 B，再把功能區分成：

implemented：程式已有能力
enabled：目前版本允許使用
availableForEnvironment：只在 dev/staging 開
requiresDependency：例如必須登入或連接 Calendar
requiresMigrationLevel
experimental
deprecated

例如：

純文字
Capability: multi_device_sync

implemented = true
enabled = false
requiresAuth = true
requiresMigrationLevel = 12

這樣我們可以先把完整架構和 domain 寫好，但正式 UI 不會因為「程式碼已存在」就突然露出半成品。

我建議 C。這跟你前面多次選擇的「底層完整、UI 先簡單」非常吻合。

你選 A / B / C。

</details>

<a id="q087"></a>
### Q087｜Privacy Capability Layer

**使用者原答：** C  
**當期範圍：** CORE。  
**願景主題：** [FV-057](#fv-057)。  
**rc1 契約：** [RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。

好，第 87 題定案：C｜Privacy Capability Layer。

也就是相機、檔案、位置、通知、Google Calendar、生物辨識等權限都統一管理，而且每個功能都要明確知道「用了哪些資料、資料會不會離開裝置、是否為選配、能否撤銷」。設定裡也會有獨立的「隱私與權限」中心，不讓權限邏輯散在各模組。

<details>
<summary>Q087 原題與選項（來源上下文）</summary>

接著第 87 題，我想定 隱私與系統權限架構。我們現在會碰到相機、照片、位置、通知、Calendar、生物辨識等權限，最好不要各 feature 自己亂請。

第 87 題｜Permission / Privacy 怎麼設計？

A｜用到再直接向系統要求權限

例如掃發票時直接跳相機權限、地點功能直接跳定位權限。

最簡單，但使用者很容易不知道「為什麼突然要這個權限」。

B｜統一 Permission Manager

所有權限走同一層：

純文字
Camera
Photos / Files
Location
Notifications
Calendar
Biometrics

只有真的使用功能時才要求，而且先由 App 解釋用途，再跳系統權限。

C｜Privacy Capability Layer，我推薦

在 B 上再進一步，把：

純文字
功能需要什麼資料
↓
需要什麼權限
↓
資料會不會離開裝置
↓
保存多久
↓
能否撤銷

全部結構化。

例如「雲端 OCR」會明確知道：

純文字
Input: 指定收據圖片
Leaves device: Yes
Requires explicit action: Yes
Retention: provider policy / app policy
Core accounting dependency: No

而「商家附近建議」：

純文字
Location permission: Optional
Background location: No
Core app dependency: No

這樣之後設定頁也可以有一個很清楚的「隱私與權限」中心，而不是把權限資訊散落各處。

我建議 C，尤其財務 App 很值得把這層做清楚。

你選 A / B / C。

</details>

<a id="q088"></a>
### Q088｜Graceful Degradation 與 Circuit Breaker

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-080](#fv-080)、[FV-026](#fv-026)。  
**rc1 契約：** [RC-23](architecture-baseline-v1.0-rc1.md#rc-23)。

好，第 88 題定案：C｜Graceful Degradation + Circuit Breaker / Service Health。

也就是任何第三方服務掛掉，都不能拖垮核心記帳。行情失敗就用最後快取、本機 OCR 照常、Calendar 壞掉仍保留 App 內提醒、雲端備份失敗也不能影響本機 Ledger；系統另外會有 provider health、circuit breaker、退避重試與自動 fallback。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q088 原題與選項（來源上下文）</summary>

接著第 88 題，我想定 外部服務失效時的降級策略。因為我們現在有行情 Provider、OCR fallback、Calendar、雲端備份等不少外部依賴。

A｜服務失效就顯示錯誤
最簡單，但使用體驗容易被第三方拖垮。

B｜Graceful Degradation，我推薦
每個外部服務都要有明確 fallback：

行情抓不到 → 顯示最後快取價格＋最後更新時間
雲端 OCR 不可用 → 回到本機 OCR／手動輸入
Calendar 失效 → App 內提醒照常運作
雲端備份失敗 → 本機帳本完全不受影響
某個行情 Provider 掛掉 → 切換備援 Provider

核心記帳永遠不依賴外部服務才能工作。

C｜B + Circuit Breaker / Service Health
除了 B，再加入：

provider health state
circuit breaker
exponential backoff
failure threshold
自動 fallback
恢復探測
診斷頁顯示服務健康狀態

我會推薦 C。這跟我們前面的多 Provider、Durable Job、DLQ 很一致。

你選 A / B / C。

</details>

<a id="q089"></a>
### Q089｜長期資料量目標與壓力測試

**使用者原答：** B+C  
**當期範圍：** CORE。  
**願景主題：** [FV-092](#fv-092)。  
**rc1 契約：** [RC-21](architecture-baseline-v1.0-rc1.md#rc-21)。

好，第 89 題定案：B 作為正式效能目標 + C 作為壓力測試基準。

也就是實際產品會以 10～20 年、10 萬級以上交易、大量 Ledger legs / revisions、行情歷史、附件 metadata 為正常長期使用情境；測試時則會刻意灌到更誇張的資料量，驗證查詢、migration、backup、restore、analytics、matching 不會突然失控。

<details>
<summary>Q089 原題與選項（來源上下文）</summary>

接著第 89 題，我想定 效能策略與資料量目標。這會影響 DB index、projection、查詢設計和 Codex 的效能驗收。

第 89 題｜我們要用什麼等級當效能目標？

A｜一般個人使用量
假設：

幾萬筆交易
幾千張附件
少量投資資料

只要操作順即可。

B｜長期高使用量，我推薦
設計時直接假設：

10～20 年資料
10 萬以上交易
大量 Ledger legs / revisions
多帳戶、多幣別
大量行情歷史資料
數千到數萬附件 metadata

要求常用畫面不能因資料量增加明顯變慢。

C｜壓力級資料量
直接用非常誇張的測試量，例如：

100 萬筆交易
大量 revisions
數十萬市場價格點
大量 matching/import data

並把它正式列入 performance benchmark。

我建議 B 為正式產品目標，但測試採部分 C 的壓力量。

也就是實際設計不是為百萬筆資料過度工程化，但 CI / benchmark 會故意灌入超過正常使用量的資料，確保查詢、migration、backup、restore 不會突然崩掉。

你選 A / B / C，或 B + C 壓測。

</details>

<a id="q090"></a>
### Q090｜Performance Regression System

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-092](#fv-092)、[FV-077](#fv-077)。  
**rc1 契約：** [RC-21](architecture-baseline-v1.0-rc1.md#rc-21)。

好，第 90 題定案：C｜完整 Performance Regression System。

我們會把效能當正式 gate：PR 跑快速 smoke benchmark；main / nightly 跑完整 benchmark 和大型資料壓測；release 前再跑全套 performance gate。除了查詢時間，還會看 memory、frame/jank、background job duration、backup/restore throughput、migration、analytics 等，並保存 baseline，避免某次改版功能沒壞但效能悄悄退化。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q090 原題與選項（來源上下文）</summary>

接著第 90 題，我想定 效能預算 Performance Budget。這會讓 Codex 後面不是只看「功能有沒有跑」，而是有明確性能門檻。

第 90 題｜效能驗收怎麼做？

A｜只看體感
功能順就算過，不設定硬指標。

B｜核心流程有明確目標，我推薦
例如針對測試裝置與固定資料集定義：

App cold start
首頁首屏
開啟交易列表
搜尋結果
新增交易提交
月報查詢
projection rebuild
大量匯入
備份／還原

每個流程都有 performance baseline，CI 定期比較，超過容忍範圍就警告或 fail。

C｜完整 Performance Regression System
除了 B，再加入：

DB query benchmark
memory usage
jank / frame time
background job duration
backup throughput
migration benchmark
analytics benchmark
benchmark history
regression threshold
自動產出效能報告

我建議 C，但不是所有 PR 都跑最重的百萬筆壓測。可以分成：

PR → 快速效能 smoke test

main / nightly → 完整 benchmark + 大型資料壓測

release → 全套 performance gate

這樣不會把每次 Codex 開發都拖得太重。

你選 A / B / C。

</details>

<a id="q091"></a>
### Q091｜Opt-in Crash Reporting

**使用者原答：** B  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-096](#fv-096)。  
**rc1 契約：** [RC-15](architecture-baseline-v1.0-rc1.md#rc-15)、[RC-21](architecture-baseline-v1.0-rc1.md#rc-21)。

好，第 91 題定案：B｜Opt-in Crash Reporting。

原則會是：

預設關閉
使用者主動開啟才上傳
只收 crash stack、App 版本、OS / 裝置資訊、模組與必要技術上下文
任何資料先經過 privacy scrubber
不上傳交易金額、商家、帳戶名稱、備註、OCR 原文、附件等財務敏感內容
本機 diagnostics 永遠保留，不依賴遠端 crash service

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q091 原題與選項（來源上下文）</summary>

接著第 91 題，我想定 Crash / 錯誤回報是否要接第三方服務。前面我們已經決定預設只做本機 diagnostics，所以這題主要是在決定 release 後要不要有遠端 crash visibility。

A｜完全本機
所有 crash / diagnostics 只存在裝置，不傳出去。

隱私最好，但如果 App crash 到打不開，要取得資訊比較麻煩。

B｜Opt-in Crash Reporting，我推薦
預設關閉。使用者可以在「隱私與權限」裡開啟：

crash stack
app version
device / OS 基本資訊
module / operation
performance failure context

但不能上傳：

交易金額
商家名稱
備註
帳戶名稱
OCR 原始內容
附件
其他財務敏感資料

C｜完整 Telemetry
除了 crash，再收 performance、feature usage、操作路徑等。

對自用財務 App 我覺得沒必要一開始做到這麼多。

我建議 B：遠端 crash reporting 可以有，但預設關閉、明確 opt-in，而且先經過 privacy scrubber。

你選 A / B / C。

</details>

<a id="q092"></a>
### Q092｜Local Analytics Warehouse 與分析匯出

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-050](#fv-050)。  
**rc1 契約：** [RC-13](architecture-baseline-v1.0-rc1.md#rc-13)、[RC-18](architecture-baseline-v1.0-rc1.md#rc-18)。

好，第 92 題定案：C｜完整 Local Analytics Warehouse，V1 UI 先做 B 的分析匯出能力。

也就是核心 Ledger 繼續維持交易真相來源，分析層則建立可重建的 projection / warehouse，專門服務報表、長時間區間查詢、趨勢分析與外部匯出。這樣未來就算資料量變大、報表變複雜，也不會讓主 Ledger 被大量 aggregation 查詢拖慢。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q092 原題與選項（來源上下文）</summary>

接著第 92 題，我想定 資料匯出給自己分析時，要不要支援「唯讀資料倉儲 / Analytics Export」。我們已經有很完整的 analytics engine，這會決定你未來要不要能在 Excel、Python、Power BI 之類工具裡自己玩資料。

A｜只有一般匯出
CSV / Excel / JSON，手動選範圍匯出即可。

B｜分析專用匯出，我推薦
除了 A，再提供一套穩定、版本化的分析 schema，例如：

transactions
ledger legs
accounts
categories
tags
merchants
investments
daily balances

而且是唯讀 export，不影響正式 Ledger。

C｜完整 Local Analytics Warehouse
除了 B，再建立獨立的 analytics projection / warehouse，專門提供大範圍分析、報表和外部匯出；核心 Ledger 不直接承擔所有分析查詢壓力。

我會推薦 C 的底層能力，V1 UI 先做 B。這樣之後就算報表越來越複雜，分析層也不會直接把主帳本查詢壓垮。

你選 A / B / C。

</details>

<a id="q093"></a>
### Q093｜Incremental Projection Engine

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-051](#fv-051)。  
**rc1 契約：** [RC-13](architecture-baseline-v1.0-rc1.md#rc-13)。

好，第 93 題定案：C｜完整 Incremental Projection Engine。

也就是分析層不是每次全量重算，而是支援 event-driven incremental update、checkpoint、projection version、dirty-range recalculation，以及必要時的 full rebuild fallback。

例如你改了兩年前的一筆交易：

只重算受影響的日期區間與相關 projection
不會把整個 10～20 年帳本全部重算一次

這樣也很符合我們前面定的 Analytics Warehouse、Domain Event 與效能目標。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q093 原題與選項（來源上下文）</summary>

接著第 93 題，我想定 報表計算要即時計算，還是預先聚合。

A｜全部即時計算
每次打開報表都從原始資料重新查。

最單純，但長期資料量大時效能不穩。

B｜常用報表預先聚合，我推薦
例如每天或交易變更後更新：

daily spending
monthly category totals
account balances
budget usage
net worth snapshots

一般報表讀 projection，點進細節才 drill-down 到 Ledger。

C｜完整增量 Projection Engine
除了 B，再讓 projection 支援：

incremental update
event-driven rebuild
checkpoint
version
dirty-range recalculation
full rebuild fallback

例如你修改 2024 年 3 月的一筆交易，不需要把 10 年報表全部重算，只重算受影響的日期範圍。

我推薦 C。這跟我們前面的 persisted domain events、analytics warehouse、performance budget 都很一致。

你選 A / B / C。

</details>

<a id="q094"></a>
### Q094｜Search Projection Engine

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-048](#fv-048)。  
**rc1 契約：** [RC-10](architecture-baseline-v1.0-rc1.md#rc-10)。

好，第 94 題定案：C｜完整 Search Projection Engine。

搜尋會有獨立、可重建的 projection / FTS index，支援全文搜尋、結構化篩選、alias/canonical entity、OCR 文字、ranking、增量索引與版本 migration。未來自然語言搜尋只負責轉成 Predicate AST，再跟既有搜尋層組合，不另外繞一條資料路徑。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q094 原題與選項（來源上下文）</summary>

接著第 94 題，我想定 全文搜尋與索引策略。因為 Merchant、備註、Tag、OCR、發票、匯入描述之後資料會很多。

第 94 題｜搜尋 Index 怎麼做？

A｜直接 SQL LIKE 查詢

例如：

純文字
WHERE note LIKE '%全聯%'

實作簡單，但資料量大之後效能和中文搜尋能力都有限。

B｜SQLite FTS 搜尋索引

建立獨立全文搜尋 index，涵蓋例如：

商家
備註
Tag
分類
發票號碼
外部交易描述
OCR 可搜尋文字

搜尋 index 是 projection，可以隨時重建。

C｜完整 Search Projection Engine，我推薦

在 B 上再進一步：

純文字
Ledger / Entities
      ↓
Search Projection
      ↓
FTS Index

支援：

全文搜尋
structured filter
ranking
alias / canonical entity
typo / fuzzy candidate
OCR text indexing
incremental indexing
index version migration
corruption 時完整 rebuild

而我們前面決定的自然語言搜尋，未來會是：

純文字
自然語言
   ↓
Predicate AST
   ↓
Structured Filter
   +
Search Projection

不需要再建立另一套搜尋資料庫。

我推薦 C。UI 一樣保持簡單，就是一個搜尋框＋篩選器，底層才做完整。

你選 A / B / C。

</details>

<a id="q095"></a>
### Q095｜Privacy Presentation Layer

**使用者原答：** C  
**當期範圍：** CORE。  
**願景主題：** [FV-058](#fv-058)。  
**rc1 契約：** [RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。

好，第 95 題定案：C｜完整 Privacy Presentation Layer。

也就是隱私顯示會成為全 App 共用能力，不會讓首頁、搜尋、通知、最近 App 預覽各自做一套。可以統一控制金額遮罩、帳戶餘額、附件縮圖、背景畫面、通知內容，以及未來 Widget / Shortcut 的敏感資訊顯示。

<details>
<summary>Q095 原題與選項（來源上下文）</summary>

接著第 95 題，我想定 搜尋結果的隱私與敏感資訊顯示。因為這是財務 App，搜尋頁其實很容易一眼暴露很多內容。

A｜全部直接顯示
搜尋結果直接列出金額、商家、帳戶、備註、附件縮圖。

最方便，但旁人看到螢幕時比較敏感。

B｜基本隱私模式
可以在設定開啟「隱私顯示」，例如：

隱藏金額
模糊帳戶餘額
附件縮圖預設不顯示
App 切到背景時隱藏最近畫面

C｜完整 Privacy Presentation Layer，我推薦
除了 B，再讓敏感資訊顯示策略統一套用到：

首頁
搜尋
帳本
報表
最近 App 預覽
通知內容
Widget / Shortcut
截圖或投影情境

例如可以有：

正常模式
隱私模式
背景遮罩
通知只顯示「有一筆待處理交易」，不顯示金額

我會推薦 C。這樣隱私規則不是各畫面自己實作，而是整個 presentation layer 共用。

你選 A / B / C。

</details>

<a id="q096"></a>
### Q096｜分級 Screen Security

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-058](#fv-058)。  
**rc1 契約：** [RC-15](architecture-baseline-v1.0-rc1.md#rc-15)。

好，第 96 題定案：C｜分級 Screen Security。

也就是不同頁面有不同敏感等級，使用者可選保護強度；App 進背景時一律套 privacy shield，但平常不會強制到讓你連報表截圖都不能用。這會和前面的 Privacy Presentation Layer 共用同一套策略，不另外散落實作。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q096 原題與選項（來源上下文）</summary>

接著第 96 題，我想定 截圖 / 螢幕錄影保護策略。這跟剛剛的 Privacy Presentation Layer 很相關。

A｜不限制截圖
完全交給使用者自己決定。

最自由，但敏感財務頁面可能被其他 App、最近任務預覽或錄影捕捉。

B｜可選擇防截圖
設定裡可以開啟：

敏感頁面禁止截圖／錄影
App 進背景時遮罩
最近任務預覽隱藏內容

一般頁面仍可正常截圖。

C｜分級 Screen Security，我推薦
不同畫面有不同敏感等級，例如：

純文字
Public-ish
- 設定
- 幫助

Sensitive
- 首頁
- 帳本
- 報表

Highly Sensitive
- 帳戶明細
- 備份恢復
- 安全設定

使用者可以選：

完全允許
只保護高度敏感頁
所有財務頁都保護

而 App 進背景時一律套 privacy shield。

我會推薦 C，但預設不要太激進，避免你想截一張報表圖時完全不能截。

你選 A / B / C。

</details>

<a id="q097"></a>
### Q097｜通知敏感等級

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-058](#fv-058)、[FV-059](#fv-059)。  
**rc1 契約：** [RC-15](architecture-baseline-v1.0-rc1.md#rc-15)、[RC-17](architecture-baseline-v1.0-rc1.md#rc-17)。

好，第 97 題定案：C｜每種通知可自訂敏感等級。

V1 UI 先提供三個簡單預設就好：完整顯示 / 隱藏金額 / 最小資訊。底層則讓不同通知類型各自有 privacy classification，像備份失敗、預算提醒、信用卡繳款、投資損益可以套不同顯示規則。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q097 原題與選項（來源上下文）</summary>

接著第 97 題，我想定 通知內容的敏感程度。

A｜完整顯示
例如：

國泰信用卡 10/15 應繳 NT$18,520

最方便，但鎖定畫面會暴露財務資訊。

B｜依隱私模式調整，我推薦
正常模式可以顯示金額；隱私模式則變成：

國泰信用卡即將到期

或：

有一筆財務提醒待處理

通知點開、App 解鎖後才顯示完整內容。

C｜每種通知可自訂敏感等級
例如：

備份失敗 → 可完整顯示
預算 80% → 隱藏金額
信用卡繳款 → 只顯示名稱與日期
投資損益 → 完全不在鎖定畫面顯示
使用者可個別設定

我會推薦 C，但 V1 UI 可以先提供幾個簡單預設：

完整
隱藏金額
最小資訊

你選 A / B / C。

</details>

<a id="q098"></a>
### Q098｜Android Shortcut 與 Home Widget

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-099](#fv-099)。  
**rc1 契約：** [RC-25](architecture-baseline-v1.0-rc1.md#rc-25)。

好，第 98 題定案：C｜Android Shortcut + Home Screen Widget。

V1 會有快速新增支出、收入、掃描收據、開啟 Financial Inbox 等 Shortcut；Widget 則先保持輕量，例如本月支出、預算狀態、信用卡待繳、快速新增。所有 Widget 都必須遵守前面定的 Privacy Presentation Layer，鎖定或隱私模式下不能直接暴露敏感財務資訊。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q098 原題與選項（來源上下文）</summary>

接著第 98 題，我想定 App Shortcut / Home Screen Widget。這會影響每天記帳的速度。

A｜不做 Widget / Shortcut
只從 App 內操作，最單純。

B｜快捷新增，我推薦
支援 Android shortcut，例如：

新增支出
新增收入
掃描收據
開啟 Financial Inbox

點了直接進對應流程。

C｜B + Home Screen Widget
除了快捷功能，再提供桌面 Widget，例如：

本月支出
預算剩餘
信用卡待繳
快速新增按鈕

但 Widget 必須遵守我們前面的 Privacy Presentation Layer，可以隱藏金額或完全不顯示敏感內容。

我推薦 C，但第一版 Widget 保持非常簡單，不要做成縮小版 Dashboard。

你選 A / B / C。

</details>

<a id="q099"></a>
### Q099｜Action Link System

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-100](#fv-100)。  
**rc1 契約：** [RC-25](architecture-baseline-v1.0-rc1.md#rc-25)。

好，第 99 題定案：C｜完整 Action Link System。

Google Calendar、通知、Widget、Shortcut、未來外部連結都共用同一套 deep link / action link 架構；連結只帶穩定 ID 與安全 intent，不直接暴露金額、帳戶等敏感資料。任何會改帳的 action 都必須先進 App、完成必要解鎖與狀態驗證，再由使用者確認，不允許「點一下連結就直接改 Ledger」。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q099 原題與選項（來源上下文）</summary>

接著第 99 題，我想定 Deep Link / 外部入口架構。未來 Google Calendar、通知、Widget、Shortcut 都會需要直接打開 App 裡的特定內容。

A｜只有基本開 App
外部入口只負責打開首頁，再由使用者自己找。

B｜結構化 Deep Link，我推薦
例如可以直接進：

某筆交易
某張信用卡帳單
某個預算
Financial Inbox 某個待處理項目
某個投資標的
新增支出流程

而且 deep link 只使用穩定 ID，不把敏感資料直接塞在 URL 裡。

C｜完整 Action Link System
除了 B，再支援帶「意圖」的安全連結，例如：

open transaction
review reminder
confirm recurring item
resolve conflict

但所有會改資料的 action 都不能因為點連結就直接執行，必須進 App 後驗證狀態、解鎖，再讓使用者確認。

我建議 C。這樣 Google Calendar 點回 App、通知 action、Widget、Shortcut 都可以共用同一套入口，不會各做一套 routing。

你選 A / B / C。

</details>

<a id="q100"></a>
### Q100｜安全 Undo 與財務 Revision／Reversal

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-101](#fv-101)。  
**rc1 契約：** [RC-03](architecture-baseline-v1.0-rc1.md#rc-03)、[RC-25](architecture-baseline-v1.0-rc1.md#rc-25)。

好，第 100 題定案：B｜安全 Undo。

低風險操作可以直接復原；但正式財務交易一旦 Posted，Undo 不能把歷史直接抹掉，而是依情境走 revision 或 reversal。這樣使用體驗保有方便性，又不破壞 Ledger 的可追溯性。

<details>
<summary>Q100 原題與選項（來源上下文）</summary>

接著第 100 題，我想定 Undo / 操作撤銷機制。我們已有 revision、reversal、audit trail，所以這題最好現在一起定清楚。

A｜只有 UI 短暫 Undo
例如刪除交易後底部跳出「復原」5 秒，過了就只能重新建立。

B｜安全 Undo，我推薦
一般低風險操作可以直接 Undo，例如：

封存分類
改 Tag
改商家
草稿刪除
Inbox 忽略

但正式財務交易如果已經 Posted，Undo 不等於把歷史抹掉，而是依情境產生 revision 或 reversal。

C｜完整 Command History
所有可變更操作都建成 command：

execute
validate
undo
redo

理論上最漂亮，但對金融交易很容易讓使用者誤以為任何事情都能無痕回復，也會增加不少架構負擔。

我建議 B。也就是 UX 上有好用的 Undo，但底層遵守財務語意：能直接復原的才復原；已產生正式財務效果的，就走 revision / reversal，不假裝它從沒發生過。

你選 A / B / C。

</details>

<a id="q101"></a>
### Q101｜風險分級確認與 Policy 預留

**使用者原答：** 好B預留C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-102](#fv-102)。  
**rc1 契約：** [RC-25](architecture-baseline-v1.0-rc1.md#rc-25)。

好，第 101 題定案：B｜風險分級確認，底層預留 C｜Policy Engine。

也就是低風險操作直接做並可 Undo；中風險簡單確認；高風險顯示影響範圍並二次確認；極高風險像整份還原、清除所有本機資料，則再要求 PIN / 生物辨識。之後如果確認規則越來越多，再把它們收斂成統一 Policy Engine。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q101 原題與選項（來源上下文）</summary>

接著第 101 題，我想定 使用者操作確認的層級。這會影響刪除、還原、批次處理、帳戶關閉等高風險動作。

A｜所有重要操作都跳確認
最安全，但容易變得很煩。

B｜風險分級確認，我推薦
依操作風險決定：

低風險：直接做，可 Undo
中風險：簡短確認
高風險：二次確認，顯示影響範圍
極高風險：要求再次驗證 PIN / 生物辨識

例如：

改 Tag：直接做
封存分類：確認一次
還原整份備份：二次確認
刪除所有本機資料：再次驗證身份

C｜完整 Policy Engine
除了 B，再把所有高風險行為都由統一 policy engine 判斷，依資料類型、操作來源、是否同步、是否有備份等決定確認方式。

我會推薦 B，底層預留 C。V1 不需要把確認邏輯做得太抽象，但要先把風險分級規則建立好。

你選 A / B / C。

</details>

<a id="q102"></a>
### Q102｜帳本設定與裝置設定分離

**使用者原答：** B預留C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-070](#fv-070)。  
**rc1 契約：** [RC-06](architecture-baseline-v1.0-rc1.md#rc-06)、[RC-20](architecture-baseline-v1.0-rc1.md#rc-20)。

好，第 102 題定案：B｜Account Settings / Device Settings 分離，底層預留 C｜多 Profile / Workspace。

也就是像基準幣別、預算規則、報表偏好這類屬於「帳號 / 帳本」的設定，未來可以同步；PIN、生物辨識、Widget、Screen Security、通知權限、Calendar 連線狀態這類則屬於「裝置設定」，不會被另一台裝置覆蓋。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q102 原題與選項（來源上下文）</summary>

接著第 102 題，我想定 設定同步 / 裝置專屬設定。未來如果真的做到多裝置，哪些設定要跟著帳號走，哪些只能留在這台手機，現在最好先分清楚。

A｜所有設定都只存本機
簡單，但換手機要全部重設。

B｜分成 Account Settings / Device Settings，我推薦
例如：

Account-level：

基準幣別
Category / Tag 顯示偏好
預算規則
通知規則
報表偏好
自訂帳戶群組

Device-level：

生物辨識
PIN
Screen Security
Widget 設定
本機通知權限
Calendar 連線狀態
快取策略

這樣未來同步不會把另一台手機的裝置安全設定一起蓋掉。

C｜B + Profile / Workspace
除了 B，再支援多個財務 Profile，例如「個人」「家庭」「公司」，每個 Profile 有自己的帳本與設定。

我會推薦 B，底層預留 C。先把 settings scope 分乾淨，未來要多 Profile 才有空間。

你選 A / B / C。

</details>

<a id="q103"></a>
### Q103｜多 Workspace 地基、單帳本 UI

**使用者原答：** B  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-070](#fv-070)。  
**rc1 契約：** [RC-20](architecture-baseline-v1.0-rc1.md#rc-20)。

好，第 103 題定案：B｜底層支援多 Ledger / Workspace，V1 UI 先維持單一帳本。

也就是核心 schema 會有 workspaceId / ledgerId，讓帳戶、交易、預算、報表、設定都能彼此隔離；但 V1 先只顯示「我的帳本」，不讓介面因為多 Profile 變複雜。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q103 原題與選項（來源上下文）</summary>

接著第 103 題，我想定 多 Profile / Workspace 未來要預留到什麼程度。雖然 V1 不一定要開，但資料模型現在要不要支援多本帳很重要。

A｜永遠單一帳本
整個 App 就一個個人財務空間，最簡單。

B｜底層支援多 Ledger / Workspace，我推薦
V1 UI 只顯示一個「我的帳本」，但核心資料都帶 workspaceId / ledgerId，未來可以新增：

個人
家庭
副業
公司報帳
旅遊專案

不同 workspace 的帳戶、交易、預算、報表彼此隔離。

C｜V1 就開放多 Profile
一開始就讓使用者切換多個帳本，甚至不同備份與權限。

我建議 B。先把 isolation 做進核心 schema，但 V1 UI 不增加切換複雜度。

你選 A / B / C。

</details>

<a id="q104"></a>
### Q104｜受控跨 Workspace Transfer

**使用者原答：** B  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-070](#fv-070)。  
**rc1 契約：** [RC-20](architecture-baseline-v1.0-rc1.md#rc-20)。

好，第 104 題定案：B｜受控跨 Workspace Transfer。

不同 Workspace 仍然彼此隔離，但可以透過明確的跨 Workspace 轉帳事件連結，例如「個人 → 家庭」或「個人 → 副業」。兩邊會各自產生對應紀錄，並用同一個 transferLinkId 關聯，確保資金流能追蹤、對帳，也不會把兩個帳本混成一個。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q104 原題與選項（來源上下文）</summary>

接著第 104 題，我想定 Workspace 之間要不要允許資金移轉。這會影響多帳本未來的邊界。

A｜完全隔離
不同 Workspace 彼此不能直接轉帳；需要時各自手動記錄。

B｜受控跨 Workspace Transfer，我推薦
例如未來有：

個人
家庭
副業

可以建立一個跨 Workspace transfer，系統在兩邊各產生對應事件，並用同一個 transferLinkId 關聯。

這樣兩邊帳本仍獨立，但資金移動可追蹤。

C｜共用帳戶 / 共用資產
同一個帳戶可以被多個 Workspace 共用。

彈性最高，但 ownership、同步、權限、報表歸屬會複雜很多，我不建議一開始走這條。

我推薦 B：Workspace 彼此隔離，但允許明確、可追蹤的跨 Workspace transfer。

你選 A / B / C。

</details>

<a id="q105"></a>
### Q105｜Membership 與家庭權限擴展

**使用者原答：** B預留C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-070](#fv-070)。  
**rc1 契約：** [RC-20](architecture-baseline-v1.0-rc1.md#rc-20)。

好，第 105 題定案：B｜預留基本 Membership，底層保留往 C 擴充。

也就是核心會先有 Workspace / Member / Role 概念，至少能承接 Owner / Editor / Viewer；但 V1 不做多人邀請、權限細分或 shared budget UI。未來如果真的要做家庭共用帳本，再擴充 approval、細粒度權限與 member audit，而不是重做 ownership 模型。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q105 原題與選項（來源上下文）</summary>

接著第 105 題，我想定 未來家庭／多人共用 Workspace 的權限模型。V1 雖然不開多人，但既然已經預留 Workspace，最好先決定底層要不要能承接。

A｜不預留多人
每個 Workspace 永遠只屬於一個使用者。

B｜預留基本 Membership，我推薦
資料模型先有：

Workspace
Member
Role

未來可支援例如：

Owner
Editor
Viewer

但 V1 完全不顯示多人 UI，也不做邀請流程。

C｜完整多人財務協作模型
除了 B，再從現在就設計：

權限細分
誰可以看哪些帳戶
誰可以修改交易
approval flow
shared budget
audit by user
invitation / revoke access

完整度最高，但會把 V1 架構再推向協作型財務系統。

我建議 B，底層預留 C 的擴充點。先把 ownership 與 membership 邊界設計正確，但不要現在就背多人協作的複雜度。

你選 A / B / C。

</details>

<a id="q106"></a>
### Q106｜Audit Principal

**使用者原答：** C  
**當期範圍：** CORE。  
**願景主題：** [FV-071](#fv-071)。  
**rc1 契約：** [RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。

好，第 106 題定案：C｜完整 Audit Principal。

之後重要變更不只記「哪台裝置」，還會記錄執行來源，例如 Human / Automation / Importer / BackgroundJob / ExternalIntegration / Migration，並附上 actorId / deviceId / source / timestamp / correlationId。這樣未來不論是手動修改、OCR 匯入、自動化、同步或 migration，都能追查「這個變更到底是誰、透過什麼機制產生的」。

<details>
<summary>Q106 原題與選項（來源上下文）</summary>

接著第 106 題，我想定 多人／多裝置情境下的 Audit Identity。即使 V1 只有你一個人，這也會影響 revision 與 sync metadata。

A｜只記裝置
每次修改只記 deviceId。

B｜Actor + Device，我推薦
每個重要變更都能記：

actorId：誰做的
deviceId：哪台裝置
source：manual / import / automation / sync / API
timestamp
correlationId

例如未來可以知道：

這筆交易是「使用者 A」在「手機 B」透過「CSV import」建立的。

C｜完整 Audit Principal
除了 B，再區分：

Human user
Automation
Importer
Background job
External integration
System migration

每種 principal 都有自己的 identity 與 permission context。

我會推薦 C。因為我們現在已經有 OCR、import、automation、background jobs、Calendar、未來 sync，單純記「誰按的」其實不夠。

你選 A / B / C。

</details>

<a id="q107"></a>
### Q107｜本機 ACID 與外部副作用

**使用者原答：** B+c  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-065](#fv-065)。  
**rc1 契約：** [RC-19](architecture-baseline-v1.0-rc1.md#rc-19)。

好，第 107 題定案：B + C 混合｜本機 ACID Unit of Work + 外部副作用用 Saga / Durable Job。

也就是本機 Ledger 相關變更必須原子化：全部成功或全部失敗；但 Google Calendar、雲端備份、行情 API 這些外部系統，不會綁進同一個 DB transaction。先確保本機帳務正確提交，再由 Domain Event 觸發 Durable Job 去完成外部同步；外部失敗就重試或進 DLQ，不回滾已經正確成立的帳務。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q107 原題與選項（來源上下文）</summary>

接著第 107 題，我想定 資料庫交易 Transaction Boundary。這對我們高標準 Ledger 很關鍵。

A｜Repository 各自處理 transaction
每個 Repository 自己決定何時 commit。簡單，但跨模組操作容易發生一半成功、一半失敗。

B｜Use Case 級 Unit of Work，我推薦
一個完整財務動作是一個 atomic operation。例如「信用卡退款」可能同時需要：

建立 reversal event
更新 ledger legs
建立 audit record
發布 domain event
標記 projection dirty

這些必須：

全部成功，或全部失敗。

Application / Use Case 決定 transaction boundary，Repository 本身不擅自 commit。

C｜完整 Distributed Transaction / Saga
如果操作同時涉及本機 DB、雲端、Google Calendar、第三方 API，就做 Saga / compensating transaction。

能力最完整，但把所有事情都做成 distributed transaction 會太重。

我的建議是 B 為核心 + 選擇性使用 C：

本機正式帳務：

嚴格 ACID / Unit of Work

外部服務：

不跟 Ledger transaction 綁死，而是先成功提交本機帳務，再透過 Durable Job / Saga 做 Calendar、Cloud、外部 API 等副作用。

例如：

純文字
信用卡繳款
   ↓
Local Ledger commit ✅
   ↓
Domain Event
   ↓
Calendar sync job
   ↓
Google Calendar

如果 Calendar 掛掉，帳務不能 rollback；Calendar job 之後重試即可。

我會推薦 B + C 混合。你選 A / B / C / B+C。

</details>

<a id="q108"></a>
### Q108｜Transactional Inbox／Outbox Framework

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-066](#fv-066)。  
**rc1 契約：** [RC-19](architecture-baseline-v1.0-rc1.md#rc-19)。

好，第 108 題定案：C｜完整 Inbox + Outbox Exactly-once Framework。

也就是正式 Ledger 變更、Audit 與 Outbox event 會在同一個 DB transaction 內一起 commit；外部或跨模組事件進來時則先進 Inbox 做 idempotency / duplicate check。這樣即使 App 在 commit 後立刻 crash、背景 job 重跑、Calendar callback 重送，也不會造成同一筆財務動作被重複執行。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q108 原題與選項（來源上下文）</summary>

接著第 108 題，我想定 Domain Event 與 DB commit 的一致性怎麼保證。這是剛剛 B+C 架構下一個很關鍵的細節。

A｜Commit 後直接 publish event
DB 成功後程式直接發 event。簡單，但如果 App 剛 commit 完就 crash，event 可能永遠沒送出去。

B｜Transactional Outbox，我推薦
在同一個 DB transaction 裡，同時寫入：

Ledger 變更
Audit
Outbox event

commit 成功後，背景 worker 再從 Outbox 發送事件。

所以即使 App 在 commit 後立刻被 Android 殺掉，下次啟動還是能看到未處理 event，繼續送。

C｜完整 Inbox + Outbox Exactly-once Framework
除了 B，再讓外部進來的 event 也有 Inbox 去重與 idempotency，避免 sync、background job、第三方 callback 重複執行。

我會推薦 C，因為我們前面已經有 Sync、Durable Job、Calendar、Backup、Automation；Inbox/Outbox 會讓整個跨模組與外部整合可靠很多。

你選 A / B / C。

</details>

<a id="q109"></a>
### Q109｜At-least-once 與冪等 consumer

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-066](#fv-066)。  
**rc1 契約：** [RC-19](architecture-baseline-v1.0-rc1.md#rc-19)。

好，第 109 題定案：B｜At-least-once delivery + Idempotent Consumer。

也就是事件可以安全重送，但每個 consumer 都必須用 eventId / idempotencyKey 保證「同一事件不管送幾次，真正的財務效果只發生一次」。這比硬追求整條鏈路 exactly-once 更實際，也更適合我們有本機 DB、雲端、Calendar、背景任務等混合環境。

<details>
<summary>Q109 原題與選項（來源上下文）</summary>

接著第 109 題，我想定 Domain Event 的 delivery semantics。雖然我們會盡量做到 effect exactly-once，但底層訊息傳遞實際上還是要接受「可能重送」這件事。

A｜假設只會送一次
最簡單，但一遇 crash/retry 很容易出問題。

B｜At-least-once + Idempotent Consumer，我推薦
事件允許重送，但每個 consumer 都必須用 eventId / idempotencyKey 保證：

同一事件即使收到 2 次、5 次，最終財務效果都只發生一次。

例如 TransactionPosted 被重送兩次：

Budget projection 不會加兩次
Calendar 不會建立兩個事件
Analytics 不會重複計算

C｜全面 Exactly-once Messaging
要求底層 transport 本身保證 exactly-once。

理論上漂亮，但跨本機 DB、HTTP、Google Calendar、雲端服務時成本很高，而且通常仍要 idempotency。

我建議 B：transport 採 at-least-once，business effect 做 exactly-once。這通常比宣稱「整條鏈路 exactly-once」更實際、更可靠。

你選 A / B / C。

</details>

<a id="q110"></a>
### Q110｜UUID v7

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-068](#fv-068)。  
**rc1 契約：** [RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。

好，第 110 題定案：B｜UUID v7。

所有核心 entity、event、revision、Inbox/Outbox record 都由本機直接產生 UUID v7，不依賴 server 發號。這很適合我們的 local-first、多裝置同步與離線建立資料，也能保留較好的時間排序與索引特性。

<details>
<summary>Q110 原題與選項（來源上下文）</summary>

接著第 110 題，我想定 ID 生成策略。這會影響離線建立資料、未來多裝置同步、排序與資料庫索引。

A｜UUID v4
完全隨機、簡單成熟。缺點是索引局部性較差，也沒有時間排序特性。

B｜UUID v7，我推薦
仍然是全域唯一 ID，但帶有時間排序特性，很適合：

Local-first
多裝置離線建立資料
Sync
Event / Revision
Ledger transaction
Outbox / Inbox

而且不用依賴中央伺服器產 ID。

C｜自訂 Snowflake / Server ID
ID 更緊湊、可排序，但通常需要 node/device identity 或中央協調，對 offline-first App 反而多一層複雜度。

我建議 B｜UUID v7。

另外會規定：所有核心 entity ID 都由 App 本地直接產生，不等 server 回傳 ID。這樣離線記帳、匯入、OCR、投資交易都能立刻成立。

你選 A / B / C。

</details>

<a id="q111"></a>
### Q111｜Internal Integer ID 與 Public UUID

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-068](#fv-068)。  
**rc1 契約：** [RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。

好，第 111 題定案：B｜Internal Integer ID + Public UUID v7。

也就是 SQLite 內部表可以用 INTEGER PRIMARY KEY 做 join / index 最佳化；但 Domain、Sync、API、Import、Event、Revision 一律只認 UUID v7。rowId 嚴禁離開 data layer，避免未來同步或資料搬遷被本機流水號綁死。

<details>
<summary>Q111 原題與選項（來源上下文）</summary>

接著第 111 題，我想定 資料庫主鍵與外部識別要不要分離。這會影響 SQLite 效能、sync、import 與 domain model。

A｜所有表直接用 UUID v7 當 Primary Key
最單純，但 SQLite 對整數主鍵通常更有效率。

B｜Internal Integer ID + Public UUID，我推薦
例如：

純文字
transactions
- rowId: INTEGER PRIMARY KEY   ← DB 內部使用
- id: UUIDv7                  ← Domain / Sync / API 使用

好處是：

SQLite join / index 更有效率
Domain 永遠使用穩定 UUID
DB 內部實作可以獨立優化
Import / Sync 不會依賴本機 rowId
未來資料搬遷比較安全

但規則要很嚴格：rowId 絕不能跑出 data layer。

C｜依資料類型混用
核心 entity 用 UUID，projection/cache 用 integer。

彈性最高，但規則容易變複雜。

我建議 B：資料庫內部用 integer surrogate key 提升效率，對外／Domain 一律 UUID v7。

你選 A / B / C。

</details>

<a id="q112"></a>
### Q112｜核心 lifecycle 與按需有效期間

**使用者原答：** B+c  
**當期範圍：** CORE。  
**願景主題：** [FV-069](#fv-069)。  
**rc1 契約：** [RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。

好，第 112 題定案：B + C 混合。

也就是所有核心、可同步 Entity 都統一具備基本生命週期欄位，例如 createdAt / updatedAt / deletedAt / version / workspaceId / publicId，需要封存的再加 archivedAt。至於 validFrom / validTo 這種 Temporal Model，只用在真的需要「某時間點當時是什麼狀態」的 Domain，例如信用卡條款、規則版本、匯率、Corporate Action 等，不全面濫用。

<details>
<summary>Q112 原題與選項（來源上下文）</summary>

接著第 112 題，我想定 資料表是否要全面做「邏輯刪除 + 有效期間」。這會影響歷史查詢與未來同步。

A｜只有部分表做 soft delete
例如 Transaction、Account 做，其他像 Merchant、Tag 直接刪。

簡單，但一致性較差。

B｜核心可同步 Entity 全部統一生命週期欄位，我推薦
例如都至少有：

createdAt
updatedAt
deletedAt
version
workspaceId
publicId

必要時再加 archivedAt。

這樣 sync / audit / migration 比較一致。

C｜完整 Temporal Data Model
除了 B，再支援有效期間，例如：

validFrom
validTo

可以回答「2027 年 1 月時，這個分類/帳戶設定當時是什麼狀態」。

能力很強，但對大部分 master data 會增加不少複雜度。

我建議 B 為預設，只有真的需要歷史語意的 Domain 才做 C。例如信用卡條款、匯率、投資 corporate action、某些規則版本可以有 temporal model，但 Merchant 名稱這類不需要全面 temporal 化。

你選 A / B / C / B+C 混合。

</details>

<a id="q113"></a>
### Q113｜Query／Index Governance

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-093](#fv-093)。  
**rc1 契約：** [RC-21](architecture-baseline-v1.0-rc1.md#rc-21)。

好，第 113 題定案：C｜完整 Query / Index Governance。

之後索引不是「慢了再補」，而是跟查詢模式、效能基準一起治理。會納入 slow query、query plan、unused index、index size、partial / covering index、FTS 分離管理，以及 migration 前後的 query plan regression。這樣可以避免 Codex 為了解一個慢查詢就一直疊 index，最後反而讓寫入、migration 和資料庫體積變差。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q113 原題與選項（來源上下文）</summary>

接著第 113 題，我想定 資料庫索引策略。因為我們前面已經把資料量與效能標準拉高，索引如果讓 Codex 自己隨便加，很容易後面越來越肥。

A｜需要時再加 Index
遇到慢查詢才補。開發簡單，但容易變成事後救火。

B｜預先定義核心 Index Policy，我推薦
從 query pattern 出發，針對常用條件設計 composite index，例如：

workspaceId + occurredAt
accountId + occurredAt
merchantId + occurredAt
categoryId + occurredAt
status + postedAt
publicId
sync 的 updatedAt + version

同時要求 migration 時檢查索引影響。

C｜完整 Query/Index Governance
除了 B，再加入：

slow query log
query plan benchmark
unused index detection
index size monitoring
partial index
covering index
FTS index 與一般 index 分離管理
migration 前後 query plan regression
壓測資料集驗證

我建議 C。因為我們已經有 Performance Regression System、Search Projection、Analytics Warehouse，這裡如果只做到 B，會少掉後續治理能力。

你選 A / B / C。

</details>

<a id="q114"></a>
### Q114｜Transactional 與重大 Shadow Migration

**使用者原答：** C  
**當期範圍：** CORE。  
**願景主題：** [FV-094](#fv-094)。  
**rc1 契約：** [RC-06](architecture-baseline-v1.0-rc1.md#rc-06)。

好，第 114 題定案：C｜一般 migration 走 Transaction，重大 migration 走 Shadow / Copy Migration。

也就是小型 schema 調整採交易式 migration，失敗就 rollback；如果是 Ledger、Sync、Investment 這種重大資料結構改版，就建立 shadow DB / 新 schema，完整搬移與驗證後再 atomic switch。舊 DB 會保留到確認新資料健康，避免 migration 中途 crash 把正式帳本卡在半完成狀態。

<details>
<summary>Q114 原題與選項（來源上下文）</summary>

接著第 114 題，我想定 資料庫 Migration 的執行方式。我們前面已經選完整 Data Evolution Framework，現在要決定升級時怎麼實際跑。

第 114 題｜Migration 要採哪種策略？

A｜直接原地升級

例如：

Schema v12 → ALTER TABLE → v13

最快，但如果 migration 中途失敗，恢復比較麻煩。

B｜交易式 Migration，我推薦

能放在 SQLite transaction 裡的 migration，全部原子化：

全部成功 → commit
任一步失敗 → rollback

同時 migration 前先做：

schema check
available storage check
safety backup
compatibility check

大部分一般 schema change 都走這個方式。

C｜B + Shadow / Copy Migration

對重大改版，例如 Ledger schema 重整，不直接改正式 DB，而是：

純文字
現有 DB
   ↓
建立新 schema / shadow DB
   ↓
搬移＋轉換資料
   ↓
跑 invariants / checksum
   ↓
驗證成功
   ↓
Atomic switch

原 DB 暫時保留，確認新 DB 健康後才清除。

這樣 migration 就算做到 70% crash，也不會把正式帳本留在半殘狀態。

我建議 C，但只在重大 migration 使用；一般小型 migration 仍走 B，不需要每次更新都複製整個資料庫。

你選 A / B / C。

</details>

<a id="q115"></a>
### Q115｜Backup Package 與 Canonical Export

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-054](#fv-054)。  
**rc1 契約：** [RC-14](architecture-baseline-v1.0-rc1.md#rc-14)。

好，第 115 題定案：C｜版本化 Backup Package + 長期 Canonical Export Format。

也就是會明確拆成三層：

Runtime DB：Drift + SQLite，追求效能
Backup Package：追求快速、可靠還原
Canonical Archive：追求長期可攜與技術獨立

這樣未來就算資料庫、Flutter、Backend 甚至整個 App 技術棧換掉，理論上仍能從 canonical format 重建完整財務資料，而不是被某個 SQLite schema 綁死。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q115 原題與選項（來源上下文）</summary>

接著第 115 題，我想定 備份檔本身的格式與可攜性。我們前面已經把備份可靠性做到很高，但還沒決定「備份是不是只能由這個 App 自己讀」。

第 115 題｜Backup Format 怎麼設計？

A｜直接備份加密 SQLite DB

優點是簡單、還原快。

缺點是：

與當時 DB schema 綁得很緊
長期跨版本相容比較麻煩
附件與 metadata 還要另外處理

B｜自訂版本化 Backup Package

例如：

純文字
backup.etbackup
├─ manifest.json
├─ ledger.data
├─ entities.data
├─ events.data
├─ attachments/
└─ checksums/

整包加密，manifest 記錄：

backup format version
app/data version
schema version
建立時間
workspace
checksum
加密資訊

還原時由 migration framework 轉成目前版本。

C｜B + Canonical Export Format，我推薦

除了真正用於快速還原的 backup package，再維持一套穩定、平台無關的 canonical archive format。

也就是即使未來：

Flutter 換掉
Drift 換掉
SQLite 換掉
Backend 換掉

我們仍然有一套能描述完整財務資料的長期格式。

概念上：

Runtime DB ≠ Backup Format ≠ Long-term Canonical Format

這樣 10 年後不會因為某個技術棧不存在，就讀不回自己的帳。

我推薦 C。

你選 A / B / C。

</details>

<a id="q116"></a>
### Q116｜人類可讀與機器可讀 Canonical Archive

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-054](#fv-054)。  
**rc1 契約：** [RC-14](architecture-baseline-v1.0-rc1.md#rc-14)。

好，第 116 題定案：C｜雙格式 Canonical Archive。

正式 Backup Package 可以採更高效的機器格式，但長期封存版本會保留人類可讀的 JSON / JSONL、schema definition、checksums、format version、欄位說明與原始附件。這樣即使很多年後技術棧改掉，資料仍然有機會被一般工具理解與重建。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q116 原題與選項（來源上下文）</summary>

接著第 116 題，我想定 Canonical Archive 要不要以「人類可讀」為目標。

A｜純機器格式
例如 protobuf / binary package。

體積小、速度快，但沒有 App 或解析器時幾乎看不懂。

B｜人類可讀格式
例如以 versioned JSON / JSONL 為主：

accounts
transactions
ledger entries
categories
investments
events
metadata

附件另外存原始檔。

即使很多年後沒有這個 App，用一般工具仍有機會讀出資料。

C｜雙格式，我推薦
Canonical Archive 同時包含：

純文字
canonical/
├─ manifest.json
├─ accounts.jsonl
├─ transactions.jsonl
├─ ledger_entries.jsonl
├─ investments.jsonl
├─ metadata/
└─ attachments/

同時可以另外附：

schema definition
checksums
format version
README / field description

正式 Backup Package 可以使用更高效的機器格式，但「長期封存格式」維持公開、可讀、可驗證。

我會選 C。

這樣即使 15 年後 ExpenseTracker 已經不存在，你至少還能理解「這些資料到底是什麼」，而不只是留下一包沒人知道怎麼解的 binary。

你選 A / B / C。

</details>

<a id="q117"></a>
### Q117｜Canonical Data 與加密容器解耦

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-055](#fv-055)。  
**rc1 契約：** [RC-14](architecture-baseline-v1.0-rc1.md#rc-14)。

好，第 117 題定案：C｜Canonical Data 與 Encryption Container 完全解耦。

也就是 canonical archive 本身維持穩定、可讀、可版本化；真正匯出時，再由外層加密容器保護。未來即使更換加密演算法，也不需要改財務資料格式本身。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q117 原題與選項（來源上下文）</summary>

接著第 117 題，我想定 Canonical Archive 的加密策略。因為「長期可讀」和「財務隱私」其實有一點衝突。

A｜Canonical Archive 預設不加密

優點是最容易長期保存與讀取；缺點是只要檔案被拿到，完整財務資料就直接曝光。

B｜Canonical Archive 預設加密，我推薦

匯出時預設建立加密封裝，但使用者可以選擇額外輸出一份未加密版本。

例如：

純文字
expense-archive.enc

解開後才是：

純文字
manifest.json
transactions.jsonl
ledger_entries.jsonl
attachments/
...

密碼／key 不寫進 archive 本身。

C｜雙層封裝

同一套 canonical data 先產生標準 archive，再由外層 encryption container 保護：

純文字
Canonical Data
    ↓
Versioned Archive
    ↓
Encryption Container

這樣「資料格式」和「加密方式」完全解耦。未來即使更換 encryption algorithm，不需要改 canonical schema。

我會推薦 C。

因為我們前面一直強調長期資料可攜性，Canonical Format 不應該跟某一種加密技術綁死；但實際匯出的檔案又應該預設受到保護。

你選 A / B / C。

</details>

<a id="q118"></a>
### Q118｜Key Envelope

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-055](#fv-055)。  
**rc1 契約：** [RC-14](architecture-baseline-v1.0-rc1.md#rc-14)。

好，第 118 題定案：C｜完整 Key Envelope 架構。

底層會用隨機 Data Encryption Key 加密 archive，再用「使用者密碼」與「Recovery Key」分別包裝這把 key。這樣未來換密碼時，不需要重新加密整包資料；UI 仍保持簡單，只讓你看到「設定密碼＋保存 Recovery Key」。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q118 原題與選項（來源上下文）</summary>

接著第 118 題，我想定 長期封存檔的解密方式。這會影響「安全」和「十幾年後還打得開」之間的平衡。

A｜只用使用者密碼
匯出時設定密碼，透過 KDF 衍生加密金鑰。

優點是最好理解；缺點是密碼忘記就無法恢復。

B｜密碼 + Recovery Key，我推薦
建立 archive 時可以產生一組 recovery key。

平常用密碼解鎖；忘記密碼時，可以用 recovery key 解密。

Recovery key 只交給使用者保管，不跟 archive 放在一起。

C｜完整 Key Envelope 架構
資料本身用隨機 Data Encryption Key 加密，再讓不同方式包住這把 key：

純文字
Archive data
   ↓
Data Encryption Key
   ├─ 使用者密碼包裝
   ├─ Recovery Key 包裝
   └─ 未來可選其他 key provider

這樣未來可以換密碼、不必重新加密整個巨大 archive；也可以新增新的解鎖方式。

我推薦 C，但 UI 仍只讓你感覺是「設定密碼＋保存 Recovery Key」，不要讓使用者看到一堆密碼學術語。

你選 A / B / C。

</details>

<a id="q119"></a>
### Q119｜Recovery Key 輪替與 Health Check

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-055](#fv-055)。  
**rc1 契約：** [RC-14](architecture-baseline-v1.0-rc1.md#rc-14)。

好，第 119 題定案：C｜Recovery Key 可輪替 + Health Check。

也就是 Recovery Key 不是「產生一次就不管」。它會支援重新產生、撤銷舊 key、測試解鎖與定期健康檢查；但前提是你當下仍有合法方式解鎖資料。這樣可以確保備援解密路徑真的可用，而不是多年後才發現 Recovery Key 根本失效。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q119 原題與選項（來源上下文）</summary>

接著第 119 題，我想定 Recovery Key 的管理方式。

A｜只顯示一次，由使用者自行保存
安全，但如果當下沒存好，以後就真的找不到。

B｜可重新產生新的 Recovery Key
舊 key 可撤銷，新 key 重新包裝 Data Encryption Key；前提是使用者當下仍能正常解鎖 archive。

C｜B + Recovery Key Health Check，我推薦
除了可以輪替 Recovery Key，再提供：

建立後要求確認有保存
定期提醒檢查 Recovery Key 是否仍可用
可做「測試解鎖」但不真正還原資料
更換 Recovery Key 時保留 audit metadata
舊 key 撤銷後不能再解鎖新版本 archive

我推薦 C。這樣不只是「有一組 Recovery Key」，而是真的能確認這條救援路徑長期有效。

你選 A / B / C。

</details>

<a id="q120"></a>
### Q120｜Recovery Key 文字與 QR

**使用者原答：** B  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-055](#fv-055)。  
**rc1 契約：** [RC-14](architecture-baseline-v1.0-rc1.md#rc-14)。

好，第 120 題定案：B｜Recovery Key 文字 + QR Code。

Recovery Key 可以同時以文字與 QR Code 呈現，方便你做紙本或離線備份；但 App 不會自動把 QR Code 存進相簿，也不會把它跟 archive 放在一起，避免同一處外洩。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q120 原題與選項（來源上下文）</summary>

接著第 120 題，我想定 Recovery Key 要不要支援離線紙本 / QR 備份。

A｜只顯示文字
例如一串 recovery code，由你複製保存。

B｜文字 + QR Code
除了文字，也能顯示 QR Code，方便：

印出紙本保存
存到離線裝置
換手機時掃描

但 QR Code 本身就是完整敏感資訊，所以不能自動存進相簿。

C｜B + 分段 Recovery，我推薦
除了完整 Recovery Key，再支援分段備份，例如把 recovery material 分成多份：

家裡保存一份
另一個安全位置保存一份
必須取得足夠份數才能恢復

這類設計可以降低「單一紙本遺失或被看到」的風險。

不過對目前這個自用 App，我覺得 B 比較合理；C 已經接近高階金鑰管理，會明顯增加使用負擔。

你選 A / B / C。

</details>

<a id="q121"></a>
### Q121｜刪除保護與冷卻期

**使用者原答：** B+c  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-074](#fv-074)。  
**rc1 契約：** [RC-15](architecture-baseline-v1.0-rc1.md#rc-15)、[RC-25](architecture-baseline-v1.0-rc1.md#rc-25)。

好，第 121 題定案：B + C 混合｜一般高風險刪除走安全確認，Workspace / 全部資料刪除再加冷卻期。

也就是一般大量刪除會要求顯示影響範圍、二次確認、PIN / 生物辨識，並提示先備份；如果是「刪除整個 Workspace / 清空全部資料」這種極高風險操作，會先進待刪除狀態，例如保留 7 天可撤銷，再進真正 purge。這樣不會讓每個小操作都很麻煩，但最危險的操作有足夠保護。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q121 原題與選項（來源上下文）</summary>

接著第 121 題，我想定 使用者刪除／清除資料時的保護策略。

A｜確認後直接刪
簡單，但風險太高。

B｜安全刪除流程，我推薦
如果是大量或全部資料刪除：

顯示影響範圍
要求二次確認
要求 PIN / 生物辨識
提醒是否先做 backup
執行後進 tombstone / deletion workflow
不允許 UI 直接繞過 Ledger / workspace lifecycle

C｜B + 冷卻期 / 延遲刪除
例如「刪除整個 Workspace」先進 7 天待刪除狀態，期間可取消；時間到才真正執行 purge。

我會推薦 C 用在整個 Workspace / 全部資料刪除，B 用在一般大量刪除。也就是分級處理，不讓每個刪除都拖 7 天。

你選 A / B / C / B+C 混合。

</details>

<a id="q122"></a>
### Q122｜完整 Purge 與 Crypto-erasure

**使用者原答：** B  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-074](#fv-074)。  
**rc1 契約：** [RC-15](architecture-baseline-v1.0-rc1.md#rc-15)、[RC-25](architecture-baseline-v1.0-rc1.md#rc-25)。

好，第 122 題定案：B｜邏輯完整 Purge + Crypto-erasure。

也就是 purge 時會清掉正式資料、revision/tombstone、projection/search index、無引用附件 blob、雲端對應資料與相關 key material；最後再跑 integrity check。對現代行動裝置來說，這比嘗試保證物理覆寫 flash 更實際。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q122 原題與選項（來源上下文）</summary>

接著第 122 題，我想定 Purge 真的執行後，要不要做到不可恢復層級。

A｜一般刪除即可
從 DB 和附件索引移除，但不特別處理儲存媒體殘留。

B｜邏輯上完整 Purge，我推薦

清除 Ledger / entity / revision / tombstone
清除相關 projection / search index
清除未再被引用的附件 blob
清除相關 encryption key material
雲端備份與同步資料標記刪除
purge 完成後跑 integrity check

對現代行動裝置來說，這通常已經是合理的安全邊界。

C｜追求 Secure Erase
試圖覆寫實體儲存區塊。

聽起來最安全，但在現代 Android / flash storage / wear leveling / encrypted filesystem 上其實很難保證真正物理覆寫成功，反而容易製造「以為一定刪乾淨」的錯覺。

我建議 B，而且會搭配「刪除 encryption key」這件事。對加密資料而言，crypto-erasure 往往比嘗試手動覆寫 flash 更實際。

你選 A / B / C。

</details>

<a id="q123"></a>
### Q123｜匯出敏感度分級

**使用者原答：** B預留C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-060](#fv-060)、[FV-057](#fv-057)。  
**rc1 契約：** [RC-18](architecture-baseline-v1.0-rc1.md#rc-18)、[RC-25](architecture-baseline-v1.0-rc1.md#rc-25)。

好，第 123 題定案：B｜匯出依敏感度分級，底層預留 C｜Export Policy Engine。

V1 先把報表圖片、部分 CSV、完整交易匯出、Canonical Archive / 全量備份分成不同風險等級；高風險匯出需要額外確認，極高風險還要 PIN / 生物辨識並提醒加密狀態。之後如果要依匯出範圍、附件、投資資料或分享目的地動態判斷，再往完整 Policy Engine 擴充。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q123 原題與選項（來源上下文）</summary>

接著第 123 題，我想定 帳本資料的「匯出分享」要不要做風險分級。

A｜所有匯出一視同仁
CSV、Excel、Canonical Archive 都是一般檔案分享。

B｜依資料敏感度分級，我推薦
例如：

報表圖片：低風險
指定期間 CSV：中風險
完整交易匯出：高風險
Canonical Archive / 全量備份：極高風險

高風險匯出需要額外確認，極高風險則要求 PIN / 生物辨識，並提醒檔案是否加密。

C｜完整 Export Policy Engine
除了 B，再依：

匯出範圍
是否含附件
是否含帳戶識別
是否含投資資料
是否加密
分享目的地

動態決定保護措施。

我建議 B，底層預留 C。V1 先做清楚的風險分級，不要讓匯出流程變得太複雜。

你選 A / B / C。

</details>

<a id="q124"></a>
### Q124｜Consistency Tier

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-051](#fv-051)。  
**rc1 契約：** [RC-13](architecture-baseline-v1.0-rc1.md#rc-13)。

好，第 124 題定案：C｜完整 Consistency Tier。

之後每種 projection 都會明確標註一致性等級：

Strong：像帳戶餘額、關鍵 Ledger summary，交易 commit 後必須立即一致。
Near-real-time：像搜尋索引、常用報表，幾秒內更新即可。
Eventual：像重型 analytics、歷史趨勢、大型 projection，可以背景完成。

UI 也會知道目前資料是不是 stale；如果報表還在重算，就顯示「更新中」，而不是假裝資料已經是最新。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q124 原題與選項（來源上下文）</summary>

接著第 124 題，我想定 App 內搜尋與報表的資料新鮮度策略。我們有 Incremental Projection Engine、Analytics Warehouse 和 Search Projection，這三個如果更新不同步，使用者可能剛新增一筆交易，報表卻晚一拍。

A｜全部同步更新
每次交易完成後，所有 projection、搜尋索引、報表聚合都在同一個 foreground flow 更新完才算完成。資料最即時，但新增交易可能變慢。

B｜核心同步、次要非同步，我推薦
交易 commit 後：

帳戶餘額、關鍵 summary：立即更新
Search index：很快非同步
Analytics projection：背景增量更新
重型報表：必要時讀舊 projection，顯示「更新中」

C｜完整 Consistency Tier
每種 projection 定義一致性等級：

Strong: 必須跟 Ledger 同步
Near-real-time: 幾秒內
Eventual: 背景完成即可

而且 UI 知道目前資料是不是 stale。

我建議 C。這樣我們可以精準控制「哪裡一定要即時、哪裡可以延後」，不需要所有東西都一起拖慢交易提交。

你選 A / B / C。

</details>

<a id="q125"></a>
### Q125｜FX Rate Engine

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-020](#fv-020)。  
**rc1 契約：** [RC-04](architecture-baseline-v1.0-rc1.md#rc-04)。

好，第 125 題定案：C｜完整 FX Rate Engine。

這代表匯率會是獨立 capability，而不是單純「查一下今天匯率」。底層會支援多 Provider、bid/ask/mid、官方/市場/手動匯率、來源品質、fallback、歷史補值、缺值策略與手動 override；但每筆 Ledger 交易仍保留自己當下實際成交匯率，不會被日後行情覆蓋。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q125 原題與選項（來源上下文）</summary>

接著第 125 題，我想定 匯率資料的來源與歷史保存策略。我們前面已經選完整多幣別 Ledger，但還沒定匯率本身怎麼管理。

A｜只用目前匯率
需要換算時直接抓現在匯率，不保存歷史。簡單，但歷史淨資產與績效會失真。

B｜保存每日歷史匯率，我推薦

每日 base/quote FX rate
provider
timestamp
rate type
可重建某天的跨幣別淨資產
Ledger 交易仍保留自己的實際成交匯率

C｜完整 FX Rate Engine
除了 B，再支援：

多 Provider
bid / ask / mid
official / market / user-entered rate
rate confidence / source quality
fallback
歷史補值
缺值 interpolation policy
使用者手動 override
報表可指定換算方法

我會推薦 C。

因為我們已經有投資、FX contribution、多幣別淨資產與多 Provider market data，匯率最好成為獨立的正式 capability，而不是附屬工具。

你選 A / B / C。

</details>

<a id="q126"></a>
### Q126｜Workspace Base Currency 與 Display Currency

**使用者原答：** C  
**當期範圍：** CORE。  
**願景主題：** [FV-020](#fv-020)。  
**rc1 契約：** [RC-04](architecture-baseline-v1.0-rc1.md#rc-04)。

好，第 126 題定案：C｜每個 Workspace 有正式 Base Currency，但報表與資產頁可臨時切換 Display Currency。

這樣原始 Ledger 永遠保留原幣，Workspace 會有一個正式基準幣別做彙總與長期統計；但 UI 可以暫時用 USD、JPY 等查看，不會改動任何帳務資料。

<details>
<summary>Q126 原題與選項（來源上下文）</summary>

接著第 126 題，我想定 基準幣別 Base Currency 的規則。這會影響報表、淨資產、投資績效與多 Workspace。

A｜整個 App 只有一個 Base Currency
例如全部固定 TWD。最簡單，但未來多 Workspace 不夠彈性。

B｜每個 Workspace 一個 Base Currency，我推薦
例如：

個人帳本：TWD
美國投資 Workspace：USD
其他帳本：JPY

所有原始交易仍保留自己的幣別；Base Currency 只用於彙總與顯示。

C｜B + 報表可臨時切換 Display Currency
Workspace 有正式 Base Currency，但使用者在報表或資產頁可以暫時切換顯示成 USD、JPY 等。

例如帳本基準是 TWD，但投資頁可以暫時看：

總資產：USD 42,350

這不會改變 Ledger，也不會改 Workspace 設定。

我建議 C：Workspace 有唯一正式 Base Currency，但 presentation 可以自由切換 Display Currency。

你選 A / B / C。

</details>

<a id="q127"></a>
### Q127｜FX Revaluation

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-021](#fv-021)。  
**rc1 契約：** [RC-04](architecture-baseline-v1.0-rc1.md#rc-04)。

好，第 127 題定案：C｜完整 FX Revaluation Engine。

底層會區分 realized / unrealized FX，支援 period-end revaluation、多次換匯成本基礎、費用分攤，以及投資績效裡把市場報酬和匯率影響拆開。UI 一開始只需要用一般人看得懂的方式顯示「匯率影響」，不會塞滿會計術語。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q127 原題與選項（來源上下文）</summary>

接著第 127 題，我想定 匯率重估與未實現匯兌損益。因為你有多幣別帳戶、投資與淨資產，如果今天 USD/TWD 變動，資產總值會跟著變，但那不代表真的產生一筆收入。

A｜只換算顯示，不計匯兌損益
最簡單。報表只把外幣資產用當日匯率換成 Base Currency。

B｜區分 Realized / Unrealized FX，我推薦
例如你持有 USD 1,000：

成交當下匯率 31
現在匯率 33

資產換算增加 NT$2,000，但這先算 未實現 FX gain。

真正把 USD 換回 TWD 時，才形成 已實現 FX gain/loss。

C｜完整 FX Revaluation Engine
除了 B，再支援：

帳戶／投資部位的 period-end revaluation
realized / unrealized FX attribution
多次換匯的 cost basis
fee allocation
投資績效裡拆出 market return vs FX return
報表可選是否包含未實現匯兌

我建議 C，但 UI 一開始只需清楚顯示「匯率影響」即可，不必把會計術語塞滿畫面。

你選 A / B / C。

</details>

<a id="q128"></a>
### Q128｜Card FX Settlement Model

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-017](#fv-017)、[FV-019](#fv-019)。  
**rc1 契約：** [RC-07](architecture-baseline-v1.0-rc1.md#rc-07)。

好，第 128 題定案：C｜完整 Card FX Settlement Model，UI 先顯示重點。

底層會保留授權時的原幣金額、正式入帳金額、卡組織／發卡行換匯資訊、海外手續費、settlement date，以及 pending → posted 期間可能發生的金額變化。一般 UI 先只顯示「原幣金額 / 實際入帳 / 手續費」，細節放交易明細裡。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q128 原題與選項（來源上下文）</summary>

接著第 128 題，我想定 信用卡外幣消費的匯率與手續費怎麼處理。這會直接影響你之後海外刷卡、對帳與報表準確度。

A｜只記最後入帳 TWD 金額
最簡單，但會失去原幣、實際換匯與手續費資訊。

B｜保留原幣 + 最終入帳金額，我推薦
例如：

原始消費：USD 100
銀行入帳：TWD 3,280
海外手續費：TWD 49

三者都分開保存，報表可以看原幣消費，也可以看實際台幣成本。

C｜完整 Card FX Settlement Model
除了 B，再保存：

authorization currency / amount
posted currency / amount
card network FX
issuer FX
overseas fee
settlement date
匯率差異
pending → posted 的金額變動

我會推薦 C，但 UI 先只顯示「原幣 / 實際入帳 / 手續費」三個重點。

你選 A / B / C。

</details>

<a id="q129"></a>
### Q129｜Credit Limit Engine

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-017](#fv-017)。  
**rc1 契約：** [RC-07](architecture-baseline-v1.0-rc1.md#rc-07)。

好，第 129 題定案：C｜完整 Credit Limit Engine。

底層會支援主卡／附卡共用額度、臨時調額、分期占用額度、pending hold、溢繳款、額度釋放時間差，以及不同發卡行規則；但 UI 先只顯示「信用額度 / 已使用 / 待入帳 / 可用額度」。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q129 原題與選項（來源上下文）</summary>

接著第 129 題，我想定 信用卡額度怎麼算。這會影響待入帳、分期、退款與可用額度。

A｜只看已入帳餘額
可用額度 = 信用額度 − 已入帳欠款。簡單，但 pending 授權會讓顯示和銀行 App 差很多。

B｜已入帳 + Pending Hold，我推薦
會分開記：

已入帳餘額
尚未入帳授權
可用額度
已退款但尚未回補的金額

C｜完整 Credit Limit Engine
除了 B，再支援：

主卡 / 附卡共用額度
臨時調額
分期占用額度規則
海外 pending hold
溢繳款
credit balance
額度釋放時間差
issuer-specific rule adapter

我建議 C，但 UI 一開始只顯示「信用額度 / 已使用 / 待入帳 / 可用額度」。

你選 A / B / C。

</details>

<a id="q130"></a>
### Q130｜Financing Engine

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-018](#fv-018)。  
**rc1 契約：** [RC-07](architecture-baseline-v1.0-rc1.md#rc-07)。

好，第 130 題定案：C｜完整 Financing Engine。

會支援單筆分期、帳單分期、0 利率、固定手續費、APR、每期不同費用、循環利息資料模型預留、提前清償、部分提前還款，以及本金／利息拆分；不同發卡行特殊規則則透過 adapter 隔離。UI 先維持「期數、每期金額、剩餘期數、總費用」這種容易理解的呈現。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q130 原題與選項（來源上下文）</summary>

接著第 130 題，我想定 信用卡帳單與分期的利息／費用模型。

A｜只記固定手續費
每筆分期直接記一個手續費金額，簡單但不夠完整。

B｜分期計畫模型
每個 installment plan 可以保存：

本金
期數
每期金額
手續費
利率
起訖日期
已繳／未繳期數

已經能處理大部分情況。

C｜完整 Financing Engine，我推薦
除了 B，再支援：

0 利率分期
固定手續費
APR / 年利率
每期不同費用
帳單分期
單筆消費分期
revolving / 循環利息資料模型預留
提前清償
部分提前還款
利息與本金拆分
不同 issuer calculation rule adapter

UI 一開始仍可很簡單，只讓你看到：

12 期
每期 NT$2,540
剩餘 8 期
總費用 NT$480

我建議 C，因為前面既然信用卡已經做到完整 domain，利息與分期最好不要再用幾個欄位硬塞。

你選 A / B / C。

</details>

<a id="q131"></a>
### Q131｜Liability／Loan Engine

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-040](#fv-040)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 131 題定案：C｜完整 Liability / Loan Engine，UI 先從基本貸款開始。

底層會支援固定／浮動利率、利率調整歷史、寬限期、提前還款、額外還本金、手續費、repayment schedule，以及實際付款與預計付款差異。這樣房貸、車貸、信貸都能被正確算進淨資產與現金流，而不是只當成一個「負數帳戶」。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q131 原題與選項（來源上下文）</summary>

接著第 131 題，我想定 貸款／負債模組。我們現在已經有 Other Liability，但還沒決定房貸、車貸、信貸這類要不要成為正式 Domain。

A｜只當一般負債帳戶
自己記本金餘額與付款，簡單，但無法正確拆本金／利息。

B｜基本 Loan Model
支援：

原始本金
利率
期數
每月付款
本金／利息拆分
剩餘本金
還款紀錄

已經能涵蓋一般信貸、車貸。

C｜完整 Liability / Loan Engine，我推薦
除了 B，再支援：

固定／浮動利率
利率調整歷史
寬限期
提前還款
額外還本金
手續費
房貸／信貸／車貸等類型
repayment schedule
實際付款與預計付款差異
未來可加入 amortization 試算

這樣淨資產就能真正把長期負債一起算進去，而不是只有信用卡。

我建議 C，但 UI 一樣先從基本貸款開始。

你選 A / B / C。

</details>

<a id="q132"></a>
### Q132｜淨資產限金融資產與金融負債

**使用者原答：** A  
**當期範圍：** CORE。  
**願景主題：** [FV-040](#fv-040)。  
**rc1 契約：** [RC-13](architecture-baseline-v1.0-rc1.md#rc-13)、[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 132 題定案：A｜淨資產只納入金融資產與金融負債。

也就是 V1 不做房產、車輛、收藏品這類非金融資產估值；淨資產主要來自現金、銀行、電子錢包、投資、其他金融資產，以及信用卡、貸款等負債。這樣可以保持資料可信，不把大量主觀估值混進財務總覽。

<details>
<summary>Q132 原題與選項（來源上下文）</summary>

接著第 132 題，我想定 資產負債表與淨資產裡，要不要納入「非金融資產」，例如房子、車子、收藏品。

A｜只算金融資產
只包含：

現金
銀行
投資
信用卡／貸款負債

最乾淨，也最像財務帳本。

B｜支援手動非金融資產，我推薦
可以新增：

房產
車輛
黃金／收藏品
其他資產

每個資產有：

名稱
取得成本
目前估值
幣別
是否計入淨資產

估值先手動更新。

C｜完整 Asset Valuation Engine
除了 B，再支援：

歷史估值
折舊
市場估值來源
手動 override
定期重新估價
與貸款關聯，例如房產 ↔ 房貸
淨值（asset value − linked liability）

我會推薦 C 的底層能力，但 V1 UI 先做 B。這樣房子、車子這些可以先簡單記，之後再加估值與折舊，不用重做資料模型。

你選 A / B / C。

</details>

<a id="q133"></a>
### Q133｜財務目標與 Goal Planning 預留

**使用者原答：** B預留c  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-041](#fv-041)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 133 題定案：B｜基本財務目標，底層預留 C｜完整 Goal Planning Engine。

V1 先支援目標金額、期限、關聯帳戶、目前進度與每月建議存款；未來再擴充自動撥款、Goal 優先級、達成日期預測與現金流連動。Goal 本身先是規劃層，不直接偷偷移動 Ledger 裡的資金。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q133 原題與選項（來源上下文）</summary>

接著第 133 題，我想定 儲蓄目標 / 財務目標 Goals。

A｜不做 Goals
只靠預算和帳戶管理，不另外做「存到多少錢」的功能。

B｜基本財務目標，我推薦
例如：

緊急預備金 150,000
日本旅遊 80,000
買電腦 60,000

可以設定：

目標金額
期限
關聯帳戶
目前進度
每月建議存多少

但它只是規劃工具，不會自己移動資金。

C｜完整 Goal Planning Engine
除了 B，再支援：

多帳戶共同計入目標
多個 Goal 共享資金時避免重複計算
自動撥款計畫
recurring transfer
Goal 優先級
預測達成日期
根據現金流動態調整建議

我會建議 B，底層預留 C。Goals 很實用，但我不想讓它一開始變成另一套複雜的理財規劃系統。

你選 A / B / C。

</details>

<a id="q134"></a>
### Q134｜Cash-flow Forecast Engine

**使用者原答：** 好C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-042](#fv-042)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 134 題定案：C｜完整 Cash-flow Forecast Engine，V1 UI 先維持 B 的簡單預測。

底層會能整合定期收支、信用卡待繳、貸款、分期、已知未來交易，再逐步加入歷史平均、預算趨勢、Goal 計畫與 scenario。重要的是每個預測都要可解釋來源，不能只丟一個黑盒數字。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q134 原題與選項（來源上下文）</summary>

接著第 134 題，我想定 現金流預測 Forecast。

A｜不做預測
只看已發生的收支。

B｜基本預測，我推薦
根據：

定期收入／支出
信用卡待繳
貸款還款
分期
已知未來交易

預估未來 30 / 60 / 90 天現金流與帳戶餘額。

C｜完整 Cash-flow Forecast Engine
除了 B，再加入：

浮動金額區間
歷史平均
預算趨勢
Goal 計畫
不同情境 scenario
最低安全餘額警示
可解釋每一筆預測來源

我會推薦 C 的底層能力，但 V1 UI 先做 B。這樣首頁未來可以很實用地告訴你：

未來 30 天預計支出 NT$32,500
其中信用卡待繳 NT$18,200

而不是做成複雜財務模型。

你選 A / B / C。

</details>

<a id="q135"></a>
### Q135｜Scenario Engine

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-042](#fv-042)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 135 題定案：C｜完整 Scenario Engine，UI 先維持少量、好懂的情境編輯。

也就是底層可以模擬支出變化、提前還款、投資增加、匯率假設、大額支出延後等情境，並比較現金流、淨資產、負債與 Goal 達成時間；但 V1 不會把畫面做成複雜財務建模工具。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q135 原題與選項（來源上下文）</summary>

接著第 135 題，我想定 Forecast 的情境模擬要做到什麼程度。

A｜只有單一路徑預測
只顯示目前條件下的未來餘額。

B｜基本 Scenario
可以切換：

保守
基準
樂觀

主要調整浮動支出、收入或預計投資。

C｜完整 Scenario Engine，我推薦
可以建立自訂情境，例如：

下個月少 20% 娛樂支出
提前還貸款 50,000
增加每月投資 10,000
匯率假設 USD/TWD = 34
某筆大額支出延後一個月

系統比較不同情境下的現金流、資產、負債與 Goal 達成時間。

我建議 C 的底層能力，UI 先提供少量好懂的 scenario 編輯。

你選 A / B / C。

</details>

<a id="q136"></a>
### Q136｜Scenario 轉計畫與 Plan Execution 預留

**使用者原答：** B預留C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-042](#fv-042)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 136 題定案：B｜Scenario 可轉成正式計畫，底層預留 C｜Plan Execution Engine。

也就是情境試算確認後，可以把內容轉成 Goal、Budget 調整、Recurring Transfer、Reminder 或 Planned Transaction，但一定是逐項確認後才生效，不會一鍵把模擬內容直接寫進正式 Ledger。之後若要做到持續追蹤計畫偏差、動態更新預測，再往完整 Plan Execution Engine 擴充。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q136 原題與選項（來源上下文）</summary>

接著第 136 題，我想定 Scenario 是否允許「直接套用成正式計畫」。

A｜只能模擬
Scenario 永遠只是試算，不會影響正式帳本或提醒。

B｜可轉成計畫，我推薦
Scenario 確認後，可以把部分內容轉成：

Goal
Budget adjustment
Recurring transfer
Reminder
Planned transaction

但仍需逐項確認，不會一鍵直接改正式 Ledger。

C｜完整 Plan Execution Engine
除了 B，再允許一個 scenario 變成可持續執行的 financial plan，系統自動追蹤偏差、更新預測、提醒調整。

我會建議 B，底層預留 C。這樣 Scenario 不只是看完就算了，但也不會一開始就變成高度自動化的理財系統。

你選 A / B / C。

</details>

<a id="q137"></a>
### Q137｜Commitment Model

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-043](#fv-043)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 137 題定案：C｜完整 Commitment Model，UI 先維持 B 的簡單 Planned Transaction 體驗。

底層會區分：

Planned：只是預計會發生
Scheduled：已排定日期
Committed：已形成較明確義務
PendingExternalConfirmation：外部已發生，但還沒正式入帳

這些都可以進 Forecast，但在正式 Posted 前不影響 Ledger 餘額。這樣也能把「未來規劃」「定期交易」「信用卡 pending」「已承諾支出」清楚分開。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q137 原題與選項（來源上下文）</summary>

接著第 137 題，我想定 Planned Transaction / 未來交易 的正式模型。

A｜只靠 Reminder / Recurring
未來預計支出都用提醒或定期交易表示。

B｜正式 Planned Transaction，我推薦
可以建立「已知未來會發生、但尚未正式入帳」的交易，例如：

下週要付保費 12,000
下個月要買機票 25,000
預計轉帳 10,000 到投資帳戶

它會參與 Forecast，但不影響目前 Ledger 餘額。

C｜完整 Commitment Model
除了 B，再區分：

Planned
Scheduled
Committed
Pending external confirmation

例如已經下單但尚未扣款，跟單純「打算要買」是不同強度的未來義務。

我會推薦 C 的底層能力，UI 先做 B。這樣之後現金流預測會更準，也能和定期交易、信用卡 pending、Scenario 區分清楚。

你選 A / B / C。

</details>

<a id="q138"></a>
### Q138｜Subscription Management

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-044](#fv-044)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 138 題定案：C｜完整 Subscription Management Engine，V1 UI 先維持 B 的簡潔度。

底層會支援試用期、續訂、價格異動、多幣別、年費換算、使用狀態、信用卡帳單中的 recurring pattern 偵測，以及後續的訂閱分析；但正式帳務仍然透過既有 Ledger / Recurring / Merchant 架構，不另外創造一套重複的交易模型。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q138 原題與選項（來源上下文）</summary>

接著第 138 題，我想定 訂閱 / Subscription 要不要做成獨立能力。雖然我們已經有 Recurring Engine，但 Netflix、Spotify、雲端服務這種訂閱其實有一些專屬需求。

A｜完全當一般定期交易

只設定每月固定扣款即可，最簡單。

B｜Subscription Profile，我推薦

在 Recurring Rule 上加一層訂閱資訊：

商家／服務名稱
方案名稱
月繳／年繳
下次扣款
自動續訂
試用截止日
付款帳戶
最近實際扣款
價格異動紀錄
是否仍在使用

Ledger 還是正常交易，不另外造帳務系統。

C｜完整 Subscription Management Engine

除了 B，再加入：

免費試用提醒
續訂前提醒
價格上漲偵測
年費換算月均成本
同類訂閱分析
長期未使用提醒
多幣別訂閱
匯入信用卡帳單後自動辨識 recurring pattern
未來甚至可接取消訂閱入口

我比較推薦 C 的底層與分析能力，但 V1 UI 先做 B。因為我們本來就有 Merchant、Matching、Recurring、Reminder、Analytics，訂閱偵測其實可以很好地利用既有架構，不必另造一大套系統。

你選 A / B / C。

</details>

<a id="q139"></a>
### Q139｜Billing／Payable Engine

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-035](#fv-035)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 139 題定案：C｜完整 Billing / Payable Engine。

也就是水電、電信、保險、管理費、信用卡帳單等「已產生但尚未付款」的義務會有正式模型。Bill 本身不影響 Ledger，真正付款時才建立正式交易；同時可以進 Forecast、提醒與 Google Calendar。未來也能支援部分付款、滯納金、自動扣款、帳單更正、OCR / Email / Import 擷取。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q139 原題與選項（來源上下文）</summary>

接著第 139 題，我想把「訂閱」以外的 帳單 Bill / 應付款也定清楚。像水電費、電信費、保險費這類通常金額會變動，不太適合只當固定 recurring transaction。

A｜全部當 Recurring Transaction
到期時建立交易，金額再手動改。最簡單，但無法很好表示「帳單已收到，但還沒付款」。

B｜獨立 Bill Model，我推薦
可以有：

發帳日
到期日
應繳金額
商家／機構
關聯帳戶
已收到／待確認／已繳
帳單附件
實際付款交易

例如：

純文字
台電帳單
應繳：NT$1,842
到期：10/18
狀態：待繳
      ↓
付款後
      ↓
關聯正式 Ledger Transaction

Bill 本身不直接影響帳戶餘額，付款交易才影響。

C｜完整 Billing / Payable Engine
除了 B，再加入：

浮動帳單預估
部分付款
多次付款
逾期
滯納金
自動扣款
帳單更正
OCR / Email / Import 擷取
與 Google Calendar / Reminder 連動
Forecast 納入未來應付款
信用卡帳單也可沿用部分共通能力

我會推薦 C。UI 一開始仍然可以很簡單，只顯示：

本月待繳 3 筆
共 NT$8,420

你選 A / B / C。

</details>

<a id="q140"></a>
### Q140｜Receivable／Personal Lending

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-036](#fv-036)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 140 題定案：C｜完整 Receivable / Personal Lending Engine，UI 先維持簡單。

底層會支援借出、待收、部分還款、分期、利息、延期、呆帳／沖銷、Reminder / Calendar、Forecast、還款 matching，以及和 Person entity 的關聯。這樣「借出去的錢」會正確視為應收資產，不會被誤算成一般支出。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q140 原題與選項（來源上下文）</summary>

接著第 140 題，我想定 應收款 / 借出去的錢，因為這跟 Bill 剛好是另一面。

第 140 題｜Receivable / 借款給別人要做到哪種程度？

A｜只當一般支出／收入

例如借朋友 3,000 元就記成支出，朋友還錢再記收入。

最簡單，但報表會誤以為真的「花掉」和「賺到」。

B｜正式 Receivable Model，我推薦

例如：

借給朋友 NT$3,000
狀態：待收

這筆錢會從現金帳戶流出，但同時形成一筆「應收資產」，所以淨資產不會直接少 3,000。

可以記：

對象
金額
日期
到期日
已收／未收
部分還款
備註

C｜完整 Receivable / Personal Lending Engine

除了 B，再支援：

多次部分還款
利息
分期還款
延期
呆帳／沖銷
Reminder / Calendar
與 Contact / Person entity 關聯
Forecast 納入預計收款
一人多筆借款
還款 matching

我會推薦 C，但 UI 先做得像很簡單的「借出 / 待收 / 已收」即可。

你選 A / B / C。

</details>

<a id="q141"></a>
### Q141｜Person／Counterparty 與 Contact Resolution

**使用者原答：** 好c  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-039](#fv-039)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 141 題定案：C｜Person / Counterparty Entity + Contact Resolution，V1 UI 先維持 B 的簡潔度。

底層會把「人／交易對象」做成正式 entity，可保存名稱、別名、備註、選填聯絡方式，並和 Receivable、分帳、報帳、Workspace Member 等關聯；之後可以接手機通訊錄做辨識與合併，但 V1 不會把通訊錄整包匯進來。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q141 原題與選項（來源上下文）</summary>

接著第 141 題，我想定 Person / Counterparty 是否要做成正式 entity。因為應收款、分帳、報帳、轉帳對象之後都可能用到。

A｜只存文字姓名
最簡單，例如「小明」。

B｜正式 Person / Counterparty Entity，我推薦
可以保存：

顯示名稱
別名
備註
聯絡方式（選填）
關聯 Merchant / Account / Receivable
Tag
是否封存

C｜B + Contact Resolution
除了 B，再支援從通訊錄選人、別名合併、同名辨識、未來共用 Workspace member 對應。

我建議 C 的底層能力，V1 UI 先做 B。這樣現在不會太複雜，但未來分帳、借款、家庭共享都能直接用同一套 entity。

你選 A / B / C。

</details>

<a id="q142"></a>
### Q142｜Shared Expense Engine

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-037](#fv-037)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 142 題定案：C｜完整 Shared Expense Engine，UI 先維持簡單。

底層會支援多人共同付款、多人分攤、部分還款、跨幣別旅遊分帳、匯差／手續費分攤，以及最後的 net settlement；但 V1 日常操作先只露出「平均分、自訂金額、誰先付款、誰已還款」這些常用功能。正式帳務仍會正確拆成自己的支出、應收／應付與實際資金流，不會只做表面上的分帳數字。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q142 原題與選項（來源上下文）</summary>

接著第 142 題，我想定 多人分帳 / Split Expense。既然已經有 Person entity，這一塊現在很適合一起定。

A｜不做多人分帳
例如朋友聚餐你先付 2,000，就自己另外建立應收款。

B｜基本 Split Expense
一筆消費可以指定：

總額 2,000
你負擔 800
A 欠你 600
B 欠你 600

Ledger 會同時正確產生自己的支出與 Receivable，不需要你手動拆成好幾筆。

支援：

平均分
固定金額
百分比
部分由自己負擔

C｜完整 Shared Expense Engine，我推薦
除了 B，再支援：

一筆帳多人共同付款
A 先付一部分、你再付一部分
多筆消費互相抵銷
Person 間 net settlement
部分還款
多幣別旅遊分帳
手續費／匯差分攤
最後結算「誰該付誰多少」
未來可跟 Shared Workspace 結合

例如旅行結束不用逐筆還：

A 欠你 1,200
你欠 B 500
系統可算出淨結算關係。

我會推薦 C，但 V1 UI 先只露出「平均分 / 自訂金額 / 已收款」等常用功能，不做得像專業分帳 App 那麼複雜。

你選 A / B / C。

</details>

<a id="q143"></a>
### Q143｜Expense Claim Engine

**使用者原答：** 好c  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-038](#fv-038)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 143 題定案：C｜完整 Expense Claim Engine，V1 UI 先做 B 的簡潔報帳流程。

底層會支援多筆交易組成一張 Claim、提交／審核／退回／核准／付款狀態、部分核准、多幣別與匯差、附件完整性，以及和 Person / Organization 的關聯；但 V1 先讓你可以很直覺地做「這筆是代墊 → 已提交 → 已核銷／待收款」。自己的真正支出與代墊部分會分開計算，不污染個人消費報表。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q143 原題與選項（來源上下文）</summary>

接著第 143 題，我想定 報帳 / Reimbursement。這跟分帳很像，但語意其實不同，例如你先墊公司費用，之後公司再還你。

A｜當一般應收款處理
先記支出，再建 Receivable。能用，但報表比較難區分「自己的消費」和「代墊」。

B｜正式 Reimbursement Model，我推薦
支援：

代墊金額
報帳對象
報帳狀態
提交日期
應收金額
已收／未收
部分核銷
附件／發票
關聯正式交易

自己的真正支出與代墊部分可以拆開，報表不會把公司代墊誤算成個人消費。

C｜完整 Expense Claim Engine
除了 B，再支援：

多筆交易組成一張報帳單
Claim number
提交／審核／退回／核准／付款
不同報帳規則
部分核准
多幣別
匯率差
附件完整性
與 Person / Organization 關聯
未來 Workspace 多人審核流程

我會推薦 C 的底層能力，V1 UI 先做 B。這樣現在只是自用報帳也很好用，未來要擴到工作或多人 Workspace 不需要重做。

你選 A / B / C。

</details>

<a id="q144"></a>
### Q144｜Organization 與 Relationship Graph

**使用者原答：** 好C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-039](#fv-039)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 144 題定案：C｜Organization Entity + Relationship Graph，V1 UI 先維持 B 的簡潔度。

底層會把公司、雇主、學校、政府機構、保險公司、報帳單位等都視為正式 Organization，並允許和 Person、Merchant、Financial Institution、Expense Claim 建立明確關係。這些關係主要服務資料一致性、搜尋與未來自動辨識，不會在 V1 UI 裡變成複雜的關係圖。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q144 原題與選項（來源上下文）</summary>

接著第 144 題，我想定 Organization / 公司／機構要不要做成正式 Entity。因為現在 Merchant、Financial Institution、Person、Expense Claim 都已經存在，再加這一層可以把很多對象關係整理乾淨。

A｜不另外做 Organization
公司名稱就當 Merchant 或文字保存。簡單，但語意容易混在一起。

B｜正式 Organization Entity，我推薦
可以表示：

公司
雇主
學校
政府機構
保險公司
報帳單位
其他非個人的交易對象

可保存：

名稱
別名
統編／識別碼（選填）
備註
聯絡資訊
關聯 Person / Merchant / Financial Institution

C｜B + Relationship Graph
除了 B，再讓不同 entity 之間有明確關係，例如：

Person 任職於 Organization
Merchant 隸屬某 Organization
Financial Institution 屬於某集團
Expense Claim 提交給某 Organization

這樣資料語意最完整，但關係圖不一定需要在 UI 露出。

我會推薦 C 的底層能力，V1 UI 先做 B。

你選 A / B / C。

</details>

<a id="q145"></a>
### Q145｜基本保單與 Insurance Domain 預留

**使用者原答：** B預留C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-045](#fv-045)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 145 題定案：B｜基本 Insurance Policy Model，底層預留 C｜完整 Insurance Domain。

V1 先支援保單名稱、保險公司、保單號碼、保費、繳費週期、生效／到期日、下次繳費日、付款帳戶、附件與有效狀態；之後若真的需要，再擴充被保險人、保障項目、保額、理賠、現金價值、解約金等能力。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q145 原題與選項（來源上下文）</summary>

接著第 145 題，我想定 保險 / Insurance 要不要做成獨立 Domain。因為我們現在已經有 Bill、Recurring、Claim、Organization，但保險其實還有保單、繳費週期、保障期間等自己的語意。

A｜只當一般定期支出
保費就當 Recurring Transaction / Bill，最簡單。

B｜基本 Insurance Policy Model，我推薦
可以保存：

保單名稱
保險公司
保單號碼
保費
繳費週期
生效日 / 到期日
下次繳費日
關聯付款帳戶
保單附件
是否仍有效

但不做複雜的保障分析。

C｜完整 Insurance Domain
除了 B，再支援：

被保險人 / 要保人
不同保障項目
保額
保費歷史
自動續保
理賠紀錄
理賠應收
保單借款
現金價值 / 解約金
與 Claim、Receivable、Calendar、Forecast 串接

我會推薦 B，底層預留 C。因為我們主要目標還是記帳與個人財務，不需要一開始把它做成保險管理 App。

你選 A / B / C。

</details>

<a id="q146"></a>
### Q146｜Income Source 與 Payroll 預留

**使用者原答：** B預留C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-046](#fv-046)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 146 題定案：B｜基本 Income Source，底層預留 C｜完整 Payroll / Income Engine。

V1 先支援固定／浮動收入來源、來源 Organization / Person、頻率、預計金額、發薪日、入帳帳戶，以及和 Recurring / Forecast 的連動；之後如果要做薪資單、底薪／津貼／獎金／扣款／實領薪資，再擴成完整 Payroll Domain。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q146 原題與選項（來源上下文）</summary>

接著第 146 題，我想定 收入來源 / 薪資要不要有獨立模型。因為目前收入只是 Transaction + Category，但薪資其實常包含底薪、獎金、扣款等資訊。

A｜全部當一般收入
薪資、獎金、兼職都只是收入分類。最簡單。

B｜基本 Income Source，我推薦
可以建立：

薪資
兼職
接案
租金
股息之外的其他固定收入來源

並保存：

Organization / 對象
頻率
預計金額
發薪日
關聯帳戶
是否固定／浮動

它可以和 Recurring / Forecast 連動。

C｜完整 Payroll / Income Engine
除了 B，再支援：

底薪
津貼
獎金
加班費
稅
勞健保／其他扣款
實領薪資
薪資單附件
年終／不定期獎金
歷史薪資變動
OCR / PDF 薪資單匯入

我會推薦 B，底層預留 C。因為主要目標還是個人財務，不需要一開始變成人資／薪資系統，但至少固定收入來源應該有正式模型。

你選 A / B / C。

</details>

<a id="q147"></a>
### Q147｜結構化 Tax Component、預留 Tax Engine

**使用者原答：** B預留C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-047](#fv-047)。  
**rc1 契約：** [RC-03](architecture-baseline-v1.0-rc1.md#rc-03)、[RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，第 147 題定案：B｜結構化 Tax Component，底層預留 C｜完整 Tax Engine。

也就是稅不只是一個普通分類，而可以作為正式 component 掛在交易、投資、股息、薪資等事件上，例如交易稅、股息扣繳、海外 withholding tax、薪資扣繳等；但 V1 不負責幫你算稅或報稅。未來如果真的需要年度稅務報表或不同 jurisdiction 的規則，再擴充 Tax Engine。

編號已依原對話後續校正；第 147 題誤改 C 的中間回覆已被取代，詳見來源更正記錄。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q147 原題與選項（來源上下文）</summary>

接著第 147 題，我想定 稅務 Tax 的角色。我們現在已經有投資稅、信用卡費用、薪資預留、報帳、貸款等，最好先確定 Tax 是單純交易欄位，還是正式能力。

A｜只把稅當一般支出／費用
例如所得稅、交易稅直接記在分類裡。

B｜結構化 Tax Component，我推薦
交易或事件可以有獨立的 tax component，例如：

投資交易稅
股息扣繳
海外 withholding tax
消費稅／VAT
薪資扣繳
其他稅費

但 App 不負責報稅，只負責正確記錄與分析。

C｜完整 Tax Engine
除了 B，再做：

tax jurisdiction
tax lot tax treatment
年度稅務報表
deductible / non-deductible
稅務規則版本
不同國家稅制 adapter
報稅資料匯出

這會明顯把產品帶向稅務軟體。

我建議 B，底層預留 C。先把稅當成正式、可分析的財務 component，但不讓 V1 承擔「算稅／報稅」責任。

你選 A / B / C。

</details>

<a id="q148"></a>
### Q148｜統一 Charge／Adjustment Component

**使用者原答：** C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-047](#fv-047)。  
**rc1 契約：** [RC-03](architecture-baseline-v1.0-rc1.md#rc-03)。

原對話後續已更正：第 148 題為 C｜統一 Charge / Adjustment Component Framework。使用者的 C 回答針對 Fee 建模，不是把第 147 題改成完整 Tax Engine。統一 Fee／Tax／Discount／Rebate／Cashback／Interest 的 Charge／Adjustment components；每筆費用可保存類型、金額、幣別、收取方、是否包含於總額與原事件關聯。完整能力按 rc1 分期接入。

編號已依原對話後續校正；第 147 題誤改 C 的中間回覆已被取代，詳見來源更正記錄。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q148 原題與選項（來源上下文）</summary>

接著第 148 題，我想定 手續費 / Fee 的統一模型。我們現在股票、換匯、信用卡、貸款、跨境交易等都會有 fee，如果每個 Domain 自己存一個 fee 欄位，久了會很亂。

第 148 題｜Fee 要怎麼建模？

A｜各 Domain 自己存 Fee
例如投資有 brokerFee、信用卡有 foreignFee、換匯有 exchangeFee。

直覺，但之後報表很難統一分析「我一年到底付了多少手續費」。

B｜統一 Fee Component，我推薦
所有財務事件都可以掛一個或多個 Fee Component，例如：

券商手續費
銀行轉帳費
海外刷卡手續費
換匯費用
貸款開辦費
ATM 費用

每筆 fee 可以保存：

類型
金額
幣別
收取方
是否已包含在總額
關聯原始事件

這樣報表可以直接分析：

今年銀行／券商／信用卡手續費總共花多少。

C｜B + Charge Component Framework
除了 Fee，再把：

Fee / Tax / Discount / Rebate / Cashback / Interest

都抽成統一的 Charge / Adjustment Component Framework。

例如一筆海外刷卡：

純文字
商品      USD 100
海外費用  TWD 49
Cashback -TWD 20

或股票交易：

純文字
成交金額
+ 券商費
+ 稅
- 折讓

底層統一處理，但 UI 還是依 Domain 顯示「手續費、稅、回饋」。

我會推薦 C。這樣我們不需要以後為 Cashback、折扣、利息又各做一套欄位，而且很符合目前的高標準 Ledger。

你選 A / B / C。

</details>

<a id="q149"></a>
### Q149｜Versioned Tax Rule Provider

**使用者原答：** C  
**當期範圍：** EXTENSION-READY（本期契約）／OPTIONAL（後續實作）。  
**願景主題：** [FV-047](#fv-047)。  
**rc1 契約：** [RC-16](architecture-baseline-v1.0-rc1.md#rc-16)。

好，這裡我幫你把編號校正一下，剛剛我有把第 148 題講錯了：

第 147 題：B｜結構化 Tax Component，預留完整 Tax Engine
第 148 題：C｜統一 Charge / Adjustment Component Framework
第 149 題：你現在選 C｜Versioned Tax Rule Provider

所以第 149 題正式定案：稅務規則本身獨立版本化，會有 jurisdiction、effective date、version、source、override 等資訊。未來稅制變動時，新規則只影響對應期間，不會回頭改掉已確認的歷史交易。

編號已依原對話後續校正；第 147 題誤改 C 的中間回覆已被取代，詳見來源更正記錄。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q149 原題與選項（來源上下文）</summary>

接著第 148 題，我想定 Tax Engine 的規則來源：

A｜全部手動設定
使用者自己輸入稅率、稅別、扣繳等。最單純，但容易設定錯。

B｜內建常用規則 + 可手動覆寫
例如依市場／資產類型提供預設，但真正套用前仍能調整。

C｜Versioned Tax Rule Provider，我推薦
稅務規則和 App 核心分離：

規則有 jurisdiction
effective date
version
source
可更新
可回溯歷史年度
使用者可 override
更新規則不會回頭改已經確認的歷史交易

例如 2027 年規則變更，2026 年交易仍使用當時的規則版本。

我建議 C，尤其既然 Tax Engine 已經選完整版本，規則本身就不該硬寫死在程式碼裡。

你選 A / B / C。

</details>

<a id="q150"></a>
### Q150｜折扣、Cashback 與 Reward 簡化

**使用者原答：** A  
**當期範圍：** CORE。  
**願景主題：** [FV-047](#fv-047)。  
**rc1 契約：** [RC-03](architecture-baseline-v1.0-rc1.md#rc-03)。

好，第 150 題定案：A｜折扣與回饋採簡化處理，不建立 Reward Engine。

原則會是：

即時折扣：直接記「實際支付金額」
優惠券／店家折抵：不另外追蹤原價與優惠額
延後入帳的信用卡 cashback：實際入帳時，再當成一筆獨立的回饋／調整交易
不追蹤點數、哩程、回饋上限、點數到期等複雜規則

例如原價 NT$1,000、現場折 NT$100：

Ledger 支出直接記 NT$900

這次我覺得簡化是合理的，因為我們前面很多地方已經做到很完整，Reward 如果也做到 C，產品很容易開始往「信用卡回饋最佳化 App」偏掉。

<details>
<summary>Q150 原題與選項（來源上下文）</summary>

接著第 150 題，我想定 Discount / Cashback / Reward 怎麼處理。既然第 148 題已經有統一的 Charge / Adjustment Framework，這塊就能做得很乾淨。

A｜折扣直接減少消費金額
例如原價 1,000、折扣 100，就只記支出 900。簡單，但之後不知道原價和折扣是多少。

B｜結構化 Adjustment，我推薦
保留：

原始金額
Discount
Cashback
Rebate
Coupon
Store credit

例如：

商品 1,000
折扣 -100
實付 900

這樣報表可以選擇看「實際支出」或「原價＋優惠」。

C｜完整 Reward Engine
除了 B，再支援：

信用卡現金回饋
點數
哩程
商店會員點數
回饋入帳延遲
回饋上限
回饋資格規則
點數折抵
點數有效期
不同 reward program

我會推薦 C 的底層能力，V1 UI 先做 B。這樣 Cashback、折扣、回饋都能正確建模，但一開始不會把介面做得很重。

你選 A / B / C。

</details>

<a id="q151"></a>
### Q151｜純文字備註與獨立 Activity Timeline

**使用者原答：** A+c,順便目前還有多少要回答  
**當期範圍：** CORE。  
**願景主題：** [FV-013](#fv-013)。  
**rc1 契約：** [RC-03](architecture-baseline-v1.0-rc1.md#rc-03)。

好，第 151 題定案：A + C｜備註保持純文字，但交易另有完整 Activity Timeline。

也就是你自己寫的備註保持很單純；系統則另外記錄建立、修改、入帳、刷退、帳單匹配、對帳等歷程，不把技術紀錄混進 Note。

至於還有多少題：目前其實已經完成大約 85～90% 的核心架構決策了。 以我現在整理後的範圍，大概還有 15～20 個真正值得你決定的問題。我不打算為了「架構完整」硬湊到 200 題；剩下主要會集中在：

UI/UX 最後幾個核心行為，例如 onboarding、空狀態、刪除/編輯呈現。
App 設定與預設值。
匯入／資料搬家實際 UX。
GitHub repo / 文件結構 / Codex 開發規範。
Slice 切分、Architecture Freeze、Definition of Done。
最後做一次整體架構 review，抓我們前面 151 題有沒有互相衝突。

所以我們已經快從「產品與架構討論」進到收斂與寫正式規格階段了。

<details>
<summary>Q151 原題與選項（來源上下文）</summary>

第 151 題｜交易「備註」要做到哪種程度？

A｜單純文字備註
一筆交易一個 Note，例如：

和朋友吃晚餐

簡單直接。

B｜文字備註 + Markdown / 結構化內容
可以有：

多行文字
checklist
link
簡單格式
關聯其他交易

功能比較完整，但日常記帳可能有點過頭。

C｜Note + Activity Timeline
交易除了自己的備註，還可以看到系統產生的歷史：

9/26 建立
9/27 信用卡正式入帳
10/03 加入帳單
10/15 完成對帳

使用者 Note 跟系統 Audit Timeline 分開。

我會推薦 C 的 Timeline + A 的備註。

也就是備註本身保持純文字簡單，但交易明細頁另外有完整 Activity Timeline，避免把系統歷史全部塞進備註。

你選 A / B / C，也可以選我推薦的 A+C。

</details>

<a id="q152"></a>
### Q152｜可跳過的引導式 Onboarding

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-088](#fv-088)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 152 題定案：B｜引導式 Onboarding，但全部可跳過。

第一次開啟只做最必要的初始化：基準幣別、主要帳戶、是否有信用卡、預設分類、安全性、是否啟用雲端備份。投資、預算、定期交易等進階功能不會硬塞進第一次啟動，避免一開始就太重。

<details>
<summary>Q152 原題與選項（來源上下文）</summary>

第 152 題｜第一次開啟 App 的 Onboarding

A｜極簡
只問：

基準幣別
建立第一個帳戶

然後直接進首頁。

B｜引導式設定，我推薦
第一次開啟時分幾步：

基準幣別
建立主要帳戶
是否建立信用卡
預設分類
是否開啟 PIN / 生物辨識
是否開啟雲端備份

全部都可以跳過，之後再設定。

C｜完整財務建檔
第一次就要求把銀行、信用卡、投資、預算、收入等全部建完。

我不推薦，第一次使用會太重。

我建議 B，而且 onboarding 控制在很短，不把所有進階設定塞進第一次啟動。

你選 A / B / C。

</details>

<a id="q153"></a>
### Q153｜精簡完整的預設分類

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-011](#fv-011)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)、[RC-05](architecture-baseline-v1.0-rc1.md#rc-05)。

好，第 153 題定案：B｜提供一套精簡但完整的預設分類。

原則會是「開箱可用，但不要塞太多」。收入、支出分開；使用者可以改名、新增子分類、封存，但不會一開始就看到幾十個細分類。

<details>
<summary>Q153 原題與選項（來源上下文）</summary>

接著第 153 題，我想定 預設分類要怎麼提供。

A｜完全空白
使用者自己建立所有收入／支出分類。最乾淨，但第一次使用成本高。

B｜提供一套預設分類，我推薦
例如支出先有：

餐飲
交通
購物
居家
娛樂
醫療
教育
旅遊
保險
稅費
其他

收入先有：

薪資
獎金
兼職
利息
其他收入

使用者可以改名、封存、新增子分類。

C｜依使用情境選模板
Onboarding 可以選：

一般生活
極簡
家庭
投資導向
自訂

再套不同分類組合。

我建議 B。先有一套品質高、不要太多的預設分類，比多模板更簡單，也比較不會讓第一次使用變複雜。

你選 A / B / C。

</details>

<a id="q154"></a>
### Q154｜引導型 Empty State

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-088](#fv-088)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 154 題定案：B｜引導型 Empty State。

空狀態會直接告訴你目前缺什麼，以及下一步能做什麼，例如「新增第一筆交易」或「匯入既有資料」，但不會塞長篇教學或動畫導覽。

<details>
<summary>Q154 原題與選項（來源上下文）</summary>

接著第 154 題，我想定 空狀態 Empty State 的策略。這會直接影響第一次使用時的感受。

A｜只顯示沒有資料
例如：

尚無交易

最簡單，但比較冷。

B｜引導型 Empty State，我推薦
空畫面會直接提供下一步，例如首頁還沒有交易時顯示：

還沒有交易紀錄
新增第一筆支出，或匯入既有資料

並提供 1～2 個明確 action，不塞教學文章。

C｜互動式教學
空狀態帶 walkthrough、動畫、逐步導覽。

我覺得對自用記帳 App 太重。

我建議 B。保持乾淨，但空畫面不只是「什麼都沒有」。

你選 A / B / C。

</details>

<a id="q155"></a>
### Q155｜完整表單狀態與不打擾式驗證

**使用者原答：** C+b  
**當期範圍：** CORE。  
**願景主題：** [FV-088](#fv-088)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 155 題定案：C 的完整表單狀態引擎 + B 的不打擾式 UX。

也就是底層會統一處理 pristine / dirty / validating / valid / invalid / submitting / failed、跨欄位驗證、async validation、草稿恢復；但 UI 不會一開始就滿版紅字，而是等使用者真的開始操作後才給適度提示，送出時再做完整 Domain validation。

<details>
<summary>Q155 原題與選項（來源上下文）</summary>

接著第 155 題，我想定 錯誤訊息與表單驗證的 UX。這點前一版其實很重要，這次要一開始就統一。

A｜送出時才驗證
按儲存後才一次顯示所有錯誤。實作簡單，但使用感比較生硬。

B｜即時但不打擾，我推薦

使用者開始輸入後才驗證
明顯格式錯誤即時提示
尚未填完時不一直跳紅字
送出時再做完整 Domain validation
錯誤直接顯示在對應欄位附近
第一個錯誤自動捲到可見範圍
不只用紅色表示錯誤

例如金額輸入到一半 12. 時，不會急著報錯；真正送出時才確認它是不是合法金額。

C｜完整表單狀態引擎
除了 B，再統一管理 pristine / dirty / validating / valid / invalid / submitting / failed 等狀態，並支援跨欄位 validation、async validation 與草稿恢復。

我建議 C 的底層 + B 的 UX。這樣複雜表單像投資、分期、換匯、報帳也能共用一致驗證邏輯，但使用者看到的仍然很自然。

你選 A / B / C。

</details>

<a id="q156"></a>
### Q156｜儲存後保留來源 Context

**使用者原答：** C  
**當期範圍：** CORE。  
**願景主題：** [FV-088](#fv-088)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 156 題定案：C｜保留來源 Context。

也就是新增／編輯完成後回到原本操作情境，並保持原本的捲動位置、搜尋條件、篩選狀態或 Inbox 處理進度；但重新開啟「新增交易」時預設是乾淨表單，只有你明確選「再記一筆類似交易」才沿用上一筆內容。

<details>
<summary>Q156 原題與選項（來源上下文）</summary>

接著第 156 題，我想定 新增或編輯交易成功後，要回到哪裡。這個會很直接影響每天記帳手感。

A｜儲存後回上一頁
從帳本進新增，就回帳本；從首頁進新增，就回首頁。

B｜儲存後固定回首頁
行為一致，但如果剛剛正在整理某個帳戶或搜尋結果，會被中斷。

C｜保留來源 Context，我推薦
新增／編輯完成後回到原本的情境，而且更新資料：

從首頁新增 → 回首頁
從帳本新增 → 回帳本原本的位置
從某帳戶新增 → 回該帳戶
從 Financial Inbox 確認 → 回 Inbox 並進到下一筆
從搜尋結果編輯 → 回原搜尋結果與篩選條件

另外，新增交易表單下次重新開啟時會重置為乾淨狀態，不會像舊版那樣殘留上一筆選擇；只有明確使用「再記一筆類似交易」時，才主動沿用部分欄位。

我建議 C。

你選 A / B / C。

</details>

<a id="q157"></a>
### Q157｜安全複製交易與模板預留

**使用者原答：** B預留C  
**當期範圍：** CORE（基本子集）＋ EXTENSION-READY／OPTIONAL（進階）。  
**願景主題：** [FV-088](#fv-088)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 157 題定案：B｜安全複製，底層預留 C｜自訂複製模板。

預設只沿用帳戶、分類、商家、Tag、幣別；金額、日期時間、備註、附件、發票與外部交易 ID 不沿用。這樣能提升連續記帳速度，又不容易因為複製過頭造成錯帳。

目前剩下的關鍵決策其實不多了，我估計大約 10 題上下，主要集中在 UI 細節、GitHub/Codex 開發規範與最後的 Architecture Freeze。

**分期說明：** 原目標完整保留；現在只交付上述 rc1 明列的基本子集或接口，延後的 Domain／引擎／UI 不要求提前實作。接入時沿用該節的資料擁有者、API、migration 與驗收規則。

<details>
<summary>Q157 原題與選項（來源上下文）</summary>

接著第 157 題，我想定 「再記一筆類似交易」要沿用哪些欄位。

A｜幾乎整筆複製
沿用帳戶、分類、商家、Tag、金額、備註，只換日期。

速度最快，但很容易忘記改金額或備註。

B｜安全複製，我推薦
預設沿用：

帳戶
分類
商家
Tag
幣別

預設不沿用：

金額
日期／時間
備註
附件
發票／收據
外部交易 ID

這些高風險或唯一性資料重新輸入。

C｜可設定複製模板
讓使用者自己決定哪些欄位要沿用，彈性最高，但設定又會多一層。

我建議 B，底層預留 C。一般使用時安全又快，未來真的有需要再開放自訂。

你選 A / B / C。

</details>

<a id="q158"></a>
### Q158｜日期分組與每日收支摘要

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-089](#fv-089)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 158 題定案：B｜日期分組 + 每日摘要。

交易列表會以日期分組，顯示當日收入／支出摘要，再列出各筆交易；資訊密度控制在適中，不會一開始就加入太多自訂顯示選項。

<details>
<summary>Q158 原題與選項（來源上下文）</summary>

第 158 題｜交易列表要怎麼呈現？

A｜純時間流水帳
按日期排序，每筆只顯示：

商家/備註
分類
金額
帳戶

最乾淨。

B｜日期分組 + 每日摘要，我推薦
例如：

純文字
9/26
支出 1,850｜收入 0

早餐                 -80
全聯               -1,270
計程車               -500

日期分組清楚，又能快速知道每天花多少。

C｜B + 高度可自訂
可以切換：

緊湊模式
詳細模式
顯示/隱藏帳戶
顯示 Tag
顯示狀態
顯示原幣/換算幣別

彈性最高，但設定會變多。

我建議 B，預留 C。先把列表做得清楚、資訊密度適中，不要一開始就塞太多欄位。

你選 A / B / C。

</details>

<a id="q159"></a>
### Q159｜有限 Swipe Action

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-089](#fv-089)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 159 題定案：B｜有限 Swipe Action。

交易列表只提供少數低風險快捷操作，例如編輯、複製／再記一筆；刪除、退款、沖銷、正式 reversal 等仍要進明細或更多選單確認，避免誤觸造成財務影響。

<details>
<summary>Q159 原題與選項（來源上下文）</summary>

接著第 159 題，我想定 交易列表的手勢操作。

A｜點進明細後再操作
編輯、刪除、複製都進明細頁處理。最安全，但操作稍慢。

B｜有限 Swipe Action，我推薦
列表左右滑只提供少數低風險快捷：

編輯
複製／再記一筆
封存或其他安全動作

刪除、退款、沖銷等高風險操作仍進明細或更多選單確認。

C｜完整 Swipe Actions
左右滑可以直接編輯、刪除、分類、Tag、退款等，效率高但比較容易誤觸。

我建議 B。財務 App 不適合讓「滑一下」就觸發不可逆或有財務意義的操作。

你選 A / B / C。

</details>

<a id="q160"></a>
### Q160｜簡潔交易明細與可展開資金流

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-090](#fv-090)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 160 題定案：B｜交易明細預設簡潔，但可展開完整資金流明細。

平常只顯示金額、帳戶、分類、商家、日期、備註等一般資訊；需要時再展開 split、fee/tax、原幣與匯率、refund/reversal、reconciliation、Activity Timeline。真正技術性的 ledger leg、event ID、revision ID 等只放診斷層，不干擾日常使用。

<details>
<summary>Q160 原題與選項（來源上下文）</summary>

接著第 160 題，我想定 交易明細頁要不要顯示完整 Ledger Breakdown。

A｜只顯示一般人看得懂的交易資訊
例如金額、分類、帳戶、商家、日期、備註，不顯示底層 legs。

B｜預設簡潔，但可展開「交易明細」，我推薦
平常看一般資訊；需要時可以展開：

資金從哪個帳戶流出／流入
split categories
fee / tax components
原幣與換算資訊
refund / reversal link
reconciliation status
Activity Timeline

不會出現「Debit / Credit」這種正式會計術語。

C｜完整技術 Ledger View
甚至可以看每個 ledger leg、event ID、revision、audit principal 等。

這對 debug 很方便，但對日常使用太工程化。

我建議 B，另外把 C 放到「診斷／開發者資訊」裡，不進一般 UI。

你選 A / B / C。

</details>

<a id="q161"></a>
### Q161｜Bottom Quick Sheet

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-006](#fv-006)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 161 題定案：B｜底部 Quick Sheet 快速新增。

按中央「＋」時，先出現輕量 Bottom Sheet，只放金額、收入／支出、帳戶、分類、商家等高頻欄位；大部分日常記帳可以直接完成。Tag、附件、拆分、多幣別等則按「更多」進完整表單。轉帳、投資、換匯、退款等特殊交易仍走各自專用流程。

現在真的接近收尾了，剩下大約 6～8 個關鍵決策，之後我就會開始把前面 161 題整理成正式 Architecture Spec，而不是繼續無限問下去。

<details>
<summary>Q161 原題與選項（來源上下文）</summary>

接著第 161 題，我想定 首頁的「快速新增」到底要多快。

A｜一定進完整新增頁
按「＋」後進快速表單，但還是完整頁面。

B｜底部 Quick Sheet，我推薦
按「＋」先從底部叫出快速記帳 Sheet，只放：

金額
支出／收入
帳戶
分類
商家（選填）

可以直接完成大多數日常記帳。

需要 Tag、附件、拆分、多幣別等時，再按「更多」進完整頁面。

C｜極速金額輸入
按「＋」後直接先出數字鍵盤：

輸入金額 → 選分類 → 完成

速度最快，但容易把帳戶、商家等資訊弱化。

我建議 B。它跟我們前面定的「快速輸入＋情境式特殊交易」最一致，也不會犧牲完整度。

你選 A / B / C。

</details>

<a id="q162"></a>
### Q162｜互動圖表與 Drill-down

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-091](#fv-091)。  
**rc1 契約：** [RC-13](architecture-baseline-v1.0-rc1.md#rc-13)。

好，第 162 題定案：B｜互動式圖表 + Drill-down。

也就是圖表不是只有看而已，可以從分類占比、月份趨勢一路點進子分類與原始交易；支援時間範圍切換、資料點明細與 tooltip，但不做成 BI 工作台。

現在剩下大約 5～7 題，快要進 Architecture Freeze 了。

<details>
<summary>Q162 原題與選項（來源上下文）</summary>

第 162 題｜圖表互動要做到哪個程度？

A｜純展示圖表
報表顯示趨勢、分類比例等，但圖表本身不能操作。

B｜可互動 Drill-down，我推薦
例如點「餐飲 28%」：

報表 → 餐飲 → 子分類 → 原始交易

折線圖點某個月份，也可以直接看那個月份的交易。

支援：

點擊資料點
時間範圍切換
分類展開
Drill-down 到交易
Tooltip / 數值明細

C｜完整分析工作台
再加入拖拉維度、任意圖表切換、自由組合指標等，接近 BI 工具。

我不推薦 C，因為會讓手機記帳 App 太重；我們底層 Analytics Engine 已經夠強，不代表 UI 也要像 Power BI。

我建議 B。

你選 A / B / C。

</details>

<a id="q163"></a>
### Q163｜輕量動畫與 Reduce Motion

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-086](#fv-086)、[FV-088](#fv-088)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 163 題定案：B｜輕量動畫。

動畫只用來幫助理解狀態變化，例如金額更新、圖表載入、展開收合與頁面轉場；不做花俏彈跳，也不能拖慢操作。系統開啟 Reduce Motion 時要能自動降低或關閉動畫。

現在剩下大約 4～6 個關鍵決策，之後就可以正式進 Architecture Freeze。

<details>
<summary>Q163 原題與選項（來源上下文）</summary>

第 163 題｜首頁與報表的數字動畫要不要做？

A｜完全不要動畫
數字直接更新，最穩、最簡潔。

B｜輕量動畫，我推薦
例如：

金額變動時短暫 count transition
圖表載入淡入
區塊展開／收合有簡短動畫
頁面切換自然過渡

但遵守：

不拖慢操作
不做花俏彈跳
支援系統 Reduce Motion
數字動畫期間仍要保持可讀

C｜大量動態效果
首頁、圖表、卡片都做豐富動畫。

我不建議，會讓財務 App 顯得太花。

我建議 B。

你選 A / B / C。

</details>

<a id="q164"></a>
### Q164｜自動刷新與下拉重新整理

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-005](#fv-005)、[FV-051](#fv-051)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)、[RC-13](architecture-baseline-v1.0-rc1.md#rc-13)。

好，第 164 題定案：B｜自動更新 + 下拉重新整理。

平常首頁靠 event / projection 自動刷新；下拉重新整理則做 freshness check，必要時觸發行情、匯率、Calendar、Cloud 狀態與背景工作，但不會粗暴地每次都全量重算。

<details>
<summary>Q164 原題與選項（來源上下文）</summary>

第 164 題｜首頁要不要支援下拉重新整理？

A｜全部自動更新
首頁依 event / projection 自動更新，不提供 pull-to-refresh。

B｜自動更新 + 下拉重新整理，我推薦
平常資料會自動更新；但使用者仍可以下拉重新整理，觸發：

Projection freshness check
行情更新
匯率更新
Calendar / cloud 狀態檢查
必要的背景 job kick

但不會每次下拉就暴力重算整個資料庫。

C｜首頁只靠手動刷新
比較可控，但體驗偏舊。

我建議 B。自動更新是正常路徑，下拉重新整理只是「我想確認現在看到的是最新狀態」的手動入口。

你選 A / B / C。

</details>

<a id="q165"></a>
### Q165｜首頁最近五筆交易

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-005](#fv-005)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 165 題定案：B｜首頁最近交易顯示 5 筆，再提供「查看全部」進入帳本。

目前剩下大概 3～5 題，就可以結束討論、整理正式規格並進 Architecture Freeze。

<details>
<summary>Q165 原題與選項（來源上下文）</summary>

第 165 題｜首頁「最近交易」要顯示幾筆？

A｜3 筆
最簡潔。

B｜5 筆，我推薦
資訊量剛好，通常不用捲太久就能看完。

C｜8～10 筆
資訊比較多，但首頁容易開始像交易列表。

我建議 B｜5 筆，再放一個「查看全部」進帳本。

你選 A / B / C。

</details>

<a id="q166"></a>
### Q166｜首頁整體預算與一至兩項提醒

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-005](#fv-005)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 166 題定案：B｜首頁顯示整體預算 + 最需要注意的 1～2 個分類。

首頁只做提醒，不變成完整預算頁。例如顯示「本月已使用 62%」，再挑出餐飲 82%、娛樂 76% 這類最值得注意的項目；完整分類細節仍到預算頁查看。

目前剩下大約 3 題左右，接著就可以停止選項問答，整理成正式規格。

<details>
<summary>Q166 原題與選項（來源上下文）</summary>

第 166 題｜首頁預算狀態要怎麼呈現？

A｜只顯示整體預算
例如：

本月預算已使用 62%

最乾淨，但看不出是哪類快超支。

B｜整體 + 最需要注意的 1～2 個分類，我推薦
例如：

本月預算 62%
餐飲 82%
娛樂 76%

只顯示最值得注意的，不把所有分類塞在首頁。

C｜顯示完整分類預算列表
資訊最完整，但首頁會太重。

我建議 B，完整預算仍然放在預算頁。

你選 A / B / C。

</details>

<a id="q167"></a>
### Q167｜首頁一行投資摘要

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-005](#fv-005)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 167 題定案：B｜首頁只放一行投資摘要。

例如顯示「投資資產 NT$528,000｜今日 +0.8%」，隱私模式則可隱藏金額；詳細持倉、績效與圖表全部留在「資產」分頁，避免首頁又開始變重。

現在剩下大概 2～3 題，問完我就會停止發散，進入正式規格整理與 Architecture Freeze。

<details>
<summary>Q167 原題與選項（來源上下文）</summary>

第 167 題｜首頁投資資訊要顯示多少？

A｜完全不放首頁

投資全部放「資產」分頁，首頁專注日常收支。

B｜一行摘要，我推薦

例如只顯示：

投資資產 NT$528,000　今日 +0.8%

或在隱私模式只顯示：

投資資產　今日上漲

點擊才進投資頁。

C｜小型投資區塊

除了總市值，再顯示：

今日損益
總報酬
前幾大持倉
小型趨勢圖

資訊更完整，但首頁又會逐漸變重。

我建議 B，符合我們前面「首頁介於極簡與完整財務總覽之間」的決定。

你選 A / B / C。

</details>

<a id="q168"></a>
### Q168｜信用卡待繳總額與最近到期卡

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-005](#fv-005)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 168 題定案：B｜首頁顯示信用卡整體待繳摘要 + 最近到期的一張。

例如顯示「信用卡待繳共 NT$31,420」，再提醒最近到期卡片；所有卡片的未出帳、額度、分期等詳細資訊都留在資產／信用卡頁。

現在大概只剩 2 題。

<details>
<summary>Q168 原題與選項（來源上下文）</summary>

第 168 題｜首頁信用卡資訊要顯示多少？

A｜只顯示最近一張待繳卡
例如：

國泰卡｜10/15 到期｜NT$18,520

B｜整體摘要 + 最急迫的一張，我推薦
例如：

信用卡待繳共 NT$31,420
最近：國泰卡 10/15 到期

點擊後再進信用卡頁查看所有卡片。

C｜首頁直接列出所有信用卡
每張卡都顯示待繳、未出帳、額度與日期。

資訊最完整，但首頁會太擠。

我建議 B，跟預算、投資一樣，首頁只回答「現在最需要知道什麼」。

你選 A / B / C。

</details>

<a id="q169"></a>
### Q169｜首頁最近三筆重要事項

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-005](#fv-005)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 169 題定案：B｜首頁只顯示最近 3 筆重要的即將發生事項。

像房租、信用卡繳款、帳單、貸款、已排定交易等，首頁只負責提醒「接下來最需要注意什麼」；完整日程仍放到專門頁面，避免首頁資訊過載。

最後我想再定 1 題，然後就可以正式停止選項討論，進 Architecture Spec 整理。

<details>
<summary>Q169 原題與選項（來源上下文）</summary>

第 169 題｜首頁「即將發生」要不要顯示？

A｜不放首頁
定期交易、帳單、貸款、Goal 等全部去各自頁面看。

B｜只顯示最近 3 筆，我推薦
例如：

10/01 房租 NT$15,000
10/05 手機費待繳
10/15 信用卡繳款

只顯示近期且需要注意的項目，點擊後進完整日程／待辦頁。

C｜完整財務日程區塊
首頁直接顯示未來 30 天所有 Bill、Recurring、Planned Transaction、信用卡、貸款等。

我建議 B，因為首頁現在已經有收支、淨資產、預算、信用卡、投資與最近交易，再多只適合放非常精簡的「接下來要注意什麼」。

你選 A / B / C。

</details>

<a id="q170"></a>
### Q170｜首頁區塊可隱藏、不自由重排

**使用者原答：** B  
**當期範圍：** CORE。  
**願景主題：** [FV-005](#fv-005)。  
**rc1 契約：** [RC-02](architecture-baseline-v1.0-rc1.md#rc-02)。

好，第 170 題定案：B｜首頁區塊可隱藏，但 V1 不提供任意拖曳重排。

首頁核心骨架固定，像收支摘要、淨資產、最近 5 筆交易維持穩定；投資摘要、信用卡摘要、預算提醒、最近 3 筆即將發生事項等，可以由你自行開關。這樣保有彈性，又不會把首頁做成 Dashboard Builder。

<details>
<summary>Q170 原題與選項（來源上下文）</summary>

第 170 題｜首頁各區塊能不能自行隱藏？

A｜完全固定
首頁所有人都一樣，最簡單。

B｜可以隱藏，但不能任意重排，我推薦
例如你可以關掉：

投資摘要
信用卡摘要
預算提醒
即將發生

但核心的收支摘要、淨資產、最近交易仍保留固定位置。

這樣有一定彈性，又不會把首頁變成複雜 Dashboard Builder。

C｜完全自訂
每個區塊都可拖曳、排序、縮放、隱藏。

我建議 B，也符合我們一開始決定「預留可自訂 Dashboard，但 V1 不暴露完整自訂系統」的方向。

你選 A / B / C。

</details>

<a id="review-source"></a>
## 附錄｜最新減重 review 完整原文

以下為 S2 的完整文字，保留 review 的理由與能力清單以便未來核對。這是歷史來源；其中「下一步」等對話用語不代表當前操作指令。可執行的當期範圍以 [rc1](architecture-baseline-v1.0-rc1.md) 為準。

<details>
<summary>展開完整 Architecture Review</summary>

可以。我做完第一輪 Architecture Consistency / Over-engineering Review 後，結論是：

### Review 結論：方向正確，但需要「減重後再 Freeze」

目前的 170 題讓我們把未來可能遇到的問題幾乎都想過一次，這非常有價值；但如果照上一版 Baseline 原封不動交給 Codex，第一版很容易變成「還沒開始好好記帳，就先在做一套小型金融平台」。

所以我建議把 V2 的正式架構原則改成：

> **Core-first, Extension-ready。**
>
> 現在真正會用到的核心功能必須完整、正確、高標準實作。  
> 未來功能先保留乾淨的資料邊界、Interface、Provider contract、migration path；沒有實際需求前，不必先建完整 Domain、資料表與 UI。

這跟你剛補充的意思更接近。

---

### 1. 哪些東西現在一定要做完整

這些我認為不能再簡化，因為它們一旦做錯，未來幾乎一定要重寫。

**Ledger 核心要完整。** 包含 multi-leg transaction、transfer、split、refund/reversal、revision、soft delete、多幣別、Money precision、rounding policy、opening balance，以及「Balance 可以由 Ledger 重建」。這是整套 App 的地基。

**Account / Category / Tag / Merchant 要完整。** 帳戶 lifecycle、雙層分類、Tag、Merchant canonical identity、基本 alias 都值得第一版就做對，因為幾乎所有功能都會依賴它們。

**資料品質基礎要完整。** UUID v7、時間／時區模型、Drift + SQLite、migration versioning、Repository boundary、ACID transaction、audit metadata、encrypted storage，這些不適合之後才補。

**多幣別與 FX 核心也應完整。** 原幣、成交匯率、基準幣別、Decimal calculation、歷史匯率接口都先定好；但非常進階的 FX attribution 可以後做。

**信用卡的基本正式模型要做。** 結帳日、繳款日、pending / posted、本期帳單、繳款、基本分期。至於各發卡行特殊 APR、主附卡共額、極複雜 financing rule，不需要現在全部實作。

**投資核心要做，但收斂範圍。** 第一階段正式支援股票 / ETF，底層 Instrument 可擴展；先完成買、賣、股息、fee/tax、持倉、lot、已實現／未實現損益、多幣別。Options、Crypto、完整 Benchmark Attribution、所有 Corporate Action 不需要第一階段全部完成。

**Backup / Restore 必須高標準。** 因為這是財務資料。版本化、加密、checksum、restore validation、重大 migration 前安全備份都值得保留。

這些是真正的 **V2 Foundation**。

---

### 2. 第一個需要大幅簡化的地方：Event / Job 架構

前面的設計已經有：

Transactional Inbox/Outbox、At-least-once、Idempotency、Durable Job Engine、DAG、Checkpoint、DLQ、Saga。

全部一起做，在手機記帳 App V1 是太重了。

我建議保留概念，但 V1 收斂成：

> **Persistent Job Queue + Idempotency + Retry/Backoff**

備份、行情更新、Calendar 等背景工作走同一套簡單可靠的 persistent queue。

Domain Event 保留。

Outbox 可以在真正有「本機 commit 後一定要可靠送出去」的流程使用。

但暫時**不要先做通用 DAG Workflow Engine、完整 DLQ 管理 UI、全面 Inbox framework**。

未來真的進入多裝置 Sync 時，再把這層升級。

這樣不會影響未來架構。

---

### 3. Analytics 也可以砍掉很多複雜度

上一版同時存在：

Analytics Engine  
→ Analytics Warehouse  
→ Incremental Projection Engine  
→ Consistency Tier  
→ Search Projection  
→ FTS  
→ Benchmark infrastructure

這一套很漂亮，但 V1 太早。

新版我建議：

**Ledger 是 source of truth。**

先建立少量真正需要的 Projection：

`AccountBalanceProjection`

`DailyBalanceSnapshot`

`MonthlyCategorySummary`

必要時：

`InvestmentPositionProjection`

其他報表先由 SQLite query + indexes 完成。

等真實資料量和查詢告訴我們哪裡慢，再新增 projection。

也就是我們仍保留：

```text
Projection interface
Projection version
rebuild()
incremental update capability
```

但**不先做完整 Analytics Warehouse Framework**。

SQLite 處理個人 10～20 年的財務資料，其實有很大的餘裕，只要 schema 和 index 設計正確。

---

### 4. Predicate DSL 保留，但先砍成功能夠用

我仍支持搜尋、Budget、Rule 共用條件模型。

但不要一開始做成：

完整 AST compiler + 任意 Boolean expression + migration framework + natural-language compiler。

第一版先有：

```text
AND

date
account
category
tag
merchant
amount
currency
transaction type
```

資料格式仍 versioned。

未來再加：

`OR / NOT / nested expression`

所以 Interface 不變，但 implementation 不用一步到頂。

---

### 5. Sync：現在只「準備」，不要做

這是我 Review 後最明確的一個調整。

V1 是：

**Local-first + Cloud Backup**

那就不要偷偷做半套 Sync Engine。

現在只需要保證：

```text
UUID
version
updatedAt
deletedAt
deviceId / actor metadata
```

存在。

Repository 與 cloud adapter 不綁 provider。

Backup package 可以保存 revision metadata。

這樣未來 Sync 可以加。

但是：

Conflict resolution UI、field merge、multi-device state machine、sync inbox/outbox、server change log……

全部延後到真的要做 C 的時候。

**Interface 留著，Engine 不做。**

這會省掉非常大量的複雜度。

---

### 6. Multi-workspace / Family Sharing 同樣只預留

我建議保留：

`workspaceId`

甚至 V1 建立唯一：

`defaultWorkspace`

這樣未來多帳本不需要改所有 table。

但是：

`Member`
`Role`
`Invitation`
`Shared permission`
`Approval flow`

全部先不要做。

也不要為它們先建空 table。

真的開始家庭共用時，再從 Workspace Module 擴充。

---

### 7. 這些完整 Domain 全部延後

上一版的以下功能，我會從「第一版需要完整實作」降成「Architecture extension point」。

**Insurance、Payroll、完整 Tax Engine、Shared Expense、Expense Claim、Receivable Lending、Subscription Management、Loan Engine、Forecast、Scenario、Plan Execution、Organization Relationship Graph。**

不是刪掉。

而是現在只確保 Ledger 能表達它們。

例如貸款未來一定需要：

```text
LoanModule
```

但現在不用先做：

浮動利率 schedule engine  
＋提前償還模擬  
＋issuer rules  
＋projection  
＋UI。

只要我們 Ledger 能表達：

本金付款、利息、費用、負債帳戶

就沒有被堵死。

等你真的開始用貸款管理，再新增 `LoanModule`。

這才是真正低成本的可擴充。

---

### 8. Investment 也要避免「專業券商系統化」

Tax Lot 我建議保留，因為資料一旦丟掉很難補。

但 V1 可以只正式驗證：

**Average Cost + FIFO。**

`LIFO / Specific Lot` 先留 Strategy Interface。

同理：

Corporate Action 第一階段先支援最基本的 stock split。

其他：

Rights  
Spin-off  
Merger  
Tender offer  
Complex distribution

先留：

`CorporateActionHandler`

不必全部寫完。

績效第一版做到：

Total Return  
Realized / Unrealized  
Dividend  
XIRR

TWR、Benchmark、Attribution、Volatility、Max Drawdown 可以後續加。

這會合理很多。

---

### 9. Market Data：多 Provider「架構」保留，但不要第一天接五家

仍然設計：

```text
MarketDataProvider
MarketDataRouter
```

但第一階段可以是：

台股 Provider A  
美股 Provider B  
FX Provider C

甚至先只有主要 Provider。

Router 本身支援 fallback 即可。

不需要為了證明 Multi-provider Architecture，一開始就每種資料接兩三個來源。

---

### 10. OCR / Matching / 電子發票也應改成第二階段

核心交易錄入先做到非常穩。

然後再加：

Receipt attachment  
→ Local OCR  
→ QR Invoice  
→ Matching Engine  
→ Cloud OCR fallback。

這些都是非常適合「Capability 啟用」的功能。

而且 OCR model / reference data 確實很適合按需下載。

這比把所有東西塞進 base APK 更符合你剛才講的方向。

---

### 11. Backup 架構保留，但 Canonical Archive 也可以分階段

第一版先實作：

**Versioned Encrypted Backup Package**

並確保真的能 restore。

再提供：

CSV / JSON export。

Canonical Long-term Archive 的 schema 可以**先寫成 specification**，不一定第一階段就完成所有 exporter/importer。

Key Envelope 也是一樣。

普通 App backup 先把 platform-secure encryption 做好。

真正「Recovery Key + QR + rotation + envelope」可以是進階 Backup Capability。

否則我們很可能花很多時間做 key-management UI，而最基本的記帳畫面都還沒完成。

---

### 12. Recovery Center 同樣簡化

V1 先做到：

**Safe Mode**

如果 DB / Ledger health check 失敗：

停止寫入。

允許：

查看資料  
匯出診斷  
重建 projection  
從 backup restore。

不用現在就做一個可以逐筆修復 revision chain 的「金融資料急診室」。

那個可以之後再做。

---

### 13. Performance 也改成務實版本

保留：

10～20 年、100k+ transaction 的產品目標。

保留 property test / fuzz test 給 Ledger。

但是第一階段 CI 不需要每個 PR 都跑巨大 Performance Platform。

先定幾個 benchmark：

Cold start  
新增交易  
載入 1 個月交易  
首頁  
月報  
100k transaction query  
backup/restore。

等 App 成形後，再建立完整 benchmark history/nightly regression。

---

### 14. 最重要的架構規則修改

上一版有一句：

> 「程式可以先寫完整，UI 可以先隱藏。」

我現在會稍微修改。

正式 Architecture Rule 應該是：

> **核心能力先完整實作；未使用的進階能力只需保留正確的 extension point。除非已確定近期會啟用，否則不提前實作完整 Domain。**

因為「先把所有程式寫完但藏起來」仍然會造成：

測試成本  
migration 成本  
dependency 成本  
維護成本  
bug surface。

最理想的是三種狀態：

**Core**  
現在使用，完整實作。

**Extension-ready**  
Interface / boundary / migration path 已準備，但沒有多餘 implementation。

**Optional capability**  
準備正式使用時才實作，可以在 UI 隱藏、Feature Flag 開放，必要資源可另外下載。

這比原本二分的「有／沒有」好很多。

---

### Review 後的實際 V1 Core

如果我現在替 Codex 砍到合理範圍，我會把第一個真正可用版本集中在：

**記帳 + Ledger + Account + Category + Merchant + Tag + Transfer + Split + Refund + 多幣別 + 基本 FX + 信用卡 + 基本分期 + 股票/ETF 投資核心 + Budget + Recurring + Search + Reports + Security + Backup/Restore + Import/Export + Design System。**

再加乾淨的：

Provider interfaces、Module APIs、Capability registry、Migration framework。

這已經是一個非常完整的 V1。

OCR、發票、Google Calendar、Bills、Forecast、Goal、Loan、Insurance、Payroll、Shared Expense、Natural Language Search、Multi-device Sync……都可以變成後續 Slice / Optional Capability。

最重要的是，**把它們接進來時不需要重做 Ledger，也不需要重做 Account、Money、Time、Workspace、Repository 或 Migration。**

---

### Architecture Review Gate 結果

我的判斷是：

**整體架構方向：GO。**

**直接 Freeze 上一版 Baseline：NO-GO。**

原因不是架構錯，而是**Scope 過度前置**。

經過這次減重後，我會建議下一版變成：

> **ExpenseTracker V2 Architecture Baseline v1.0-rc1**
>
> 核心架構 Freeze。  
> 功能 Scope 分成 Core / Extension-ready / Optional。  
> 不再要求所有 170 項能力第一階段都實作。

這樣才適合真正交給 Codex 開工。

下一步就應該是我把上一份 Baseline **正式改寫成這個「減重版 rc1」**，同時把每個 Module 標成 `CORE / EXTENSION-READY / OPTIONAL`，然後我們再做最後一次 Freeze Review。

</details>

## 文件維護

範圍減重時先改 rc1，並在對應 FV 條目記錄新處置；不可刪掉長期功能清單。未來若有新決策，先核對時間順序與取代關係，再同步更新 Q→FV→RC 映射；170 題原始登錄保持可追溯。新提出的設計必須標示提案，不得逆寫成歷史定案。

本文件不代表功能已 implemented／verified／enabled。可下載資源、隱藏 UI 與正式選配交付是不同問題；功能啟用仍須完成 Domain、migration、backup／restore、安全與測試。任何真正取消的願景要有明確決策與取代記錄，不用「延後」掩蓋刪除。
