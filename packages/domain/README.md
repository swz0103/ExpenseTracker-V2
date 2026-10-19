# domain

記帳規則：帳戶、分類、標籤、商家、分錄、月報、預算、信用卡、投資、定期交易與 CSV 交換。只用 Dart 核心函式庫，不碰檔案、網路或資料庫。

每一節對應一個公開入口（`package:domain/<入口>.dart`），原本是獨立的套件。

## accounts

帳戶的 Domain 規則，只依賴 `foundation_values`。

- 種類：現金、銀行、信用卡、電子支付、貸款、應收（代墊：幫人付是轉入、對方還錢是轉出，收不回的以支出沖掉）、手動估值（如基金，用 `AdjustBalance` 更新價值）。沒有餘額欄位，餘額由分錄算出。
- 操作：開立、改名、變更淨資產納入、封存、結清（餘額須為零、不能有未結事項）、重新啟用。
- `version` 每次變更都加 1；`rulesVersion` 只有封存、結清、重新啟用才加，記帳只檢查它，所以改名不會讓準備好的記帳失效（健檢 G1-09）。
- `Account.restore` 會重新檢查所有規則，用於從儲存還原。

```sh
dart pub get --enforce-lockfile
dart analyze
dart test --reporter expanded
```

## bookkeeping

應用層（ADR-0001 階段 3）：帳戶與收支指令，跑在 `app_core` 的 `CommandRunner` 上。

- 指令：開戶（可含期初餘額）、改名、封存／重新啟用、收入／支出、轉帳（可跨幣別、可含手續費）、沖銷、餘額校正（`AdjustBalance`：在寫入交易內算出差額，記成收入或支出）。
- 每個指令的事件、投影表與操作紀錄在同一交易提交；重試回傳同一結果，同一 key 換輸入則是 `operation.input-mismatch`。
- 帳戶規則（版本、幣別、狀態、開戶日）在寫入交易內檢查；違規轉成 `AppFailure`，代碼如 `account.versionConflict`、`ledger.sameAccount`。
- 沖銷只新增反向分錄，原分錄保留；同一筆不能沖兩次；已結清帳戶不能被沖銷改動餘額。
- `AccountCodec`／`PostingCodec`：版本化 JSON，解碼一律重新走 domain 工廠驗證。
- 儲存介面 `BookkeepingTransaction`，SQLCipher 實作在 `infrastructure/ledger_sqlcipher`。
- 也包含：分類／標籤／商家、退款、結清、期初替換、備註、更正、刪除（`Bookkeeping`）；信用卡（`CardBook`）；投資（`InvestmentBook`）；預算與定期交易（`PlanningBook`）。
- `reportFact` 是分錄轉成月報／預算事實的唯一定義。
- `package:bookkeeping/memory.dart`：記憶體版實作，供預覽與測試。
- 原始碼依指令分組：`bookkeeping.dart`（對外指令與共用寫入）、`account_handlers.dart`、`entry_handlers.dart`、`correction_handlers.dart`、`catalog_handlers.dart`（以私有 extension 實作），卡片、投資、計畫各自一個檔。

## budgets

每月支出預算的規則，只依賴 `foundation_values`、`categories`、`reports`。

- `BudgetPlan`：工作空間、月份、上限（正數）、警示百分比（1–100），可選分類、帳戶、標籤；`repeats` 為每月沿用（`forMonth`）。
  - 帳戶、標籤各自多選時是「任一符合」，和分類之間是「全部符合」；選父分類包含子分類。
  - 只能選支出分類。
- `evaluateBudget`：用月報事實算已用、剩餘、是否到警示。不同幣別不換算，回報略過的筆數。
- `BudgetPlanCodec`：版本化 JSON，未知欄位、重複選項、過大資料一律拒絕。

保存、版本衝突與「合併過的分類算進目標分類」在 `bookkeeping` 的 `PlanningBook` 與 `ledger_sqlcipher`。

## categories

分類的規則，只依賴 `foundation_values`。

- 兩層：根分類與子分類；收入／支出種類建立後不能改。
- 同一層、同種類不能重名（比對統一全形半形與大小寫）。名稱算字數，擋控制字元。
- 封存保留 ID；要先封存子分類才能封存父分類，啟用則相反。
- 合併：來源保留並記下去向，舊交易不改寫；報表歸到合併後的分類。合併鏈用 `resolveRedirects` 一次解開（不遞迴、偵測循環）。
- `CategoryCatalog` 一次驗證整個工作空間的分類；每次變更產生新的 catalog。

保存與指令在 `bookkeeping`（`changeCatalog`）。

## credit_cards

信用卡帳單的規則，只依賴 `foundation_values`。

- `CreditCardTerms`：結帳日、繳款日、額度，有版本。
  - `reschedule`：結帳日變更只影響之後的帳單，過去的帳單日期不變。
  - `overrideCycle`：發卡行移動某一期的實際結帳日或繳款日。
  - `cycleFor(date)`：某天的消費落在哪一期；繳款日是結帳後第一個繳款日，遇假日順延（`BankingCalendar`）。
- `CardCharge`：授權（pending）→ 入帳（posted），入帳以實際金額為準；種類有消費、發卡行費用、回饋。可記原幣金額與國外交易手續費；外幣退刷以原幣為上限。
- 帳單：前期結轉、本期消費、費用、退款、繳款、分期當期金額、應繳與最低應繳。
- `CardInstallmentSchedule`：分期，尾差全部併入第一期（例如 10,001 分 3 期為 3,335／3,333／3,333）；分期計畫自存結帳日。

指令、保存與帳單查詢在 `bookkeeping` 的 `CardBook` 與 `ledger_sqlcipher`。

## data_exchange

檔案匯入匯出，只依賴 `foundation_values`。

- `parseEInvoices`：讀財政部電子發票平台下載的「消費明細」CSV。欄位依表頭找，不依順序；同一張發票的品項加總、品名去重；作廢的發票略過。任何一列讀不懂就整份停下，並指出第幾行。發票號碼可以用來跳過已記過的發票。
- `readCsv`／`writeCsv`：CSV 讀寫。寫出時帶 BOM、使用 CRLF，Excel 打開不會亂碼；逗號、引號、換行都會正確加上引號。

App 要匯出明細時，自己組好欄位（日期、類型、帳戶、分類、金額、備註），再交給 `writeCsv`。

## investments

股票與 ETF 的規則，只依賴 `foundation_values`。所有預覽都不寫入帳本；保存在 `bookkeeping` 的 `InvestmentBook`。

- 身分：`BrokerIdentity`、`InvestmentAccount`（連結交割的現金或銀行帳戶）、`InvestmentInstrument`（市場＋代號，穩定 ID）。
- 數量與價格是十進位文字，不經過 `double`；台股股數只收整數（零股也是整數股）。
- `InvestmentBuyPreview`／`InvestmentSellPreview`：成交價金與數量×價格比對，容許券商捨入差 1 個最小單位；賣出用 FIFO 或平均成本，同一持股只能用一種。淨額可以是 0 或負數。
- `InvestmentDividendPreview`：含預扣稅、手續費、二代健保補充保費。
- `StockSplitPreview`、`CorporateActionPreview`：分割、反向分割、配股、減資（畸零股與退還股款以現金處理，先沖減成本）。
- `TaiwanTradeCharges`、`taiwanSettlementDate`、`supplementaryPremium`：台股手續費（折扣、最低 20 元）、證交稅、T+2、補充保費試算。

## ledger

分錄的 Domain 規則，只依賴 `foundation_values`。

- `Posting`：期初、收入、支出、轉帳（同幣或跨幣、可含手續費）、退款（可入帳到其他幣別）、沖銷、投資買進／賣出／股利。建立物件本身沒有財務效果，由 `bookkeeping` 在交易中保存。
- 沖銷產生反向分錄、原分錄保留；投資分錄只有作廢交易時能沖銷。
- `RefundBudget`：退款額度由先前的退款重播得出。
- `rebuildBalance`：從有效分錄重算餘額，拒絕重複的分錄 ID 與 OperationKey。
- 備註（`NoteChange`）、分類分攤、標籤與商家選擇。

```sh
dart pub get --enforce-lockfile
dart analyze
dart test --reporter expanded
```

## merchants

商家與別名的規則，只依賴 `foundation_values`。

- 商家可以同名（例如不同分店），用 ID 區分；每個商家最多 16 個別名。
- 比對只去掉首尾空白並轉小寫；有歧義時回傳所有候選，不自動選。
- 封存、合併與分類相同：保留來源與去向，舊交易不改寫，合併鏈用 `resolveRedirects`。

保存與指令在 `bookkeeping`（`changeCatalog`）。

## recurring_transactions

定期交易的規則，只依賴 `foundation_values`。

- `RecurringTemplate`：帳戶、金額（負數為支出）、起始日、每 N 日／週／月／年、結束日，可帶分類、標籤、商家。
- `dueCandidates`：找出區間內到期的項目（`after` 不含、`through` 含），離線多天後可一次補齊。月底與閏日以起始日為準，短月取當月最後一天。
- 每個到期項目的身分是「範本＋到期日」，修改範本不會讓同一天多出一筆。
- `RecurringTemplateCodec`：版本化、有大小上限的 JSON。

確認入帳（可改實際金額與日期、每期只能確認一次）在 `bookkeeping` 的 `PlanningBook`。

## reports

報表用的共用型別，依賴 `foundation_values` 與 `ledger`：

- `ReportMonth`：不受時區影響的日曆月份。
- `MonthlyFact`、`CategoryAllocation`：一筆分錄對報表的影響，由 `bookkeeping` 的 `reportFact` 產生；預算與 `ledger_sqlcipher` 的月報、分類合計都用它。

報表數字由 `ledger_sqlcipher` 的投影表直接查詢，不另外在記憶體裡重算。

## tags

標籤的規則，只依賴 `foundation_values`。標籤不擁有金額或交易。

- 名稱不重複（統一全形半形與大小寫比對），可改名、封存、合併。
- 合併保留來源與去向，舊交易不改寫；新交易不能選已封存或已合併的標籤。合併鏈用 `resolveRedirects`。
- 一筆交易最多 16 個標籤。

保存與指令在 `bookkeeping`（`changeCatalog`）。
