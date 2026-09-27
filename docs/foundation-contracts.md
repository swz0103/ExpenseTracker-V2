# Foundation Contracts — 第一版工程規格

狀態：階段 0 工程規格草稿；不是實作完成或 Architecture Freeze。  
依據：[rc1](architecture-baseline-v1.0-rc1.md)、[A＋與業務套件](architecture-baseline-v1.0-rc1.md#a-plus-coordination)、[實作安排](implementation-plan.md)。

本規格將已選方向細化為可實作、可測試的契約。部分值型別與 Accounts Domain 已實作，狀態見[逐項進度](work-progress.md)；其餘資料實體仍是設計名稱，不能視為已建立的 SQLite schema。若實測需要改變既定財務規則，必須保留 ADR 差異，不能把原型行為默認為新規則。

## 1. 套件與依賴

當期業務邊界為 Accounts、Ledger、Categories、Tags、Merchants；信用卡、投資、Budget／Recurring、Search／Reporting、Import／Export、Backup／Security 依各批交付。業務內 Domain、Application、Data、Presentation 先有明確責任，有隔離需要即可拆子套件。

- `foundation_values`：Money／Currency、Public ID、Workspace ID、Date／Instant 及必要共用錯誤。不含業務流程或資料庫。
- `accounts`：帳戶身份、幣別、類型與 lifecycle。對外提供 workspace-scoped 的帳戶參與驗證契約。
- `ledger`：transaction／legs、資金語意、revision／refund／reversal、charge 及寫入不變條件；依賴 foundation values，不依賴信用卡或投資的內部實作。
- `categories`、`tags`、`merchants`：各自擁有身份、結構與 lifecycle。外部只持有 public ID，資料庫 row ID 不外流。
- `persistence`：SQLite connection、transaction-scoped session 與 migration 協調。業務擁有其資料規格，Data adapter 參與同一 session。
- `app_composition`：注入 adapters、操作入口與必要跨模組 Use Case；Domain 不反向引用 App。
- `jobs`／platform adapters／design system：按實際需求建立，不能承載 Ledger 或 Investment 的公式。

依賴方向為 App → 業務公開 Application 契約 → Domain；Data adapter 實作 Domain／Application 所需 port，並依賴 persistence。跨業務參與接口由消費方需要的契約與 adapter 接合，不要求 Accounts Domain 同時引用 Ledger Domain。

例如帳戶摘要畫面由 Application 組合 Accounts identity 與 Ledger balance；帳戶的封存／關閉流程可透過 injected balance-read port 驗證餘額。帳戶 Domain 本身沒有可任意修改的 currentBalance。

每個套件列出允許的直接依賴與公開入口；CI 檢查 internal 存取、循環與 Domain 對平台／儲存的依賴。拆成套件本身不是邊界已受保護的證據。

現有三個業務套件已接[架構邊界 gate](architecture-boundary-checks.md)，包含原型使用端的私有入口引用檢查。未來 App／adapter／UI 的責任仍須隨功能明列，不能把此項當成所有模組都已完成的證據。

## 2. 值型別與序列化

### Money 與 Decimal

- `Money` 由 currency code、minor-unit scale 與有正負號的整數 amount 組成。幣別及 scale 不同不得直接加減。符號描述經濟餘額變化，不由文字「收入／支出」猜測。
- Domain 中間運算須精確並在保存前檢查 SQLite signed 64-bit 整數範圍；溢位回傳錯誤，不截斷或轉成 double。
- 公開 JSON／備份中的整數金額用十進位字串與明確 currency／scale 表達，避免經過不同 runtime 時失去精度。
- 匯率、股數、單價與成本使用明確精度的 Decimal；原始輸入以十進位文字解析，不先經 binary floating-point。具體函式庫待工具鏈驗證。
- 輸入超過該欄位允許精度時明示錯誤；不默默替使用者改已輸入的交易額。計算造成的精度收斂由 operation policy 決定。
- FX 最終入帳量化的初版工程提案採 half-away-from-zero；分攤先算前 n−1 項，最後一項吸收尾差，保證總額完全相等。實際成交的兩邊金額優先於參考匯率推算，差異需記錄 context，不偷偷改原額。
- 投資成本與 FX 中間計算不反覆量化；每個最後入帳邊界保存 policy version。反轉直接對原已量化值取負，不重新用今日規則計算。

FX 計算地基已以[精確比率值型別](exact-fx-values.md)細化：十進位輸入保留精確值，反向／交叉運算不做中間量化；source／asOf／retrievedAt 分開保存。這不改成交金額優先、最終 half-away-from-zero 或反轉原已入帳額的規則。完整交易 context、股數／成本 Decimal 與資料層仍待實作。

### ID、Workspace 與時間

- Public ID 使用 UUID v7；operation ID 是一次使用者意圖的穩定身份，不以時間／金額當去重鍵。匯入來源身份是另外的契約。
- 所有帳本資料、命令、query 與關聯都須帶 workspace 範圍；reference data 的全域例外明列，不能因忘記篩選而跨帳本。
- 瞬間時間以 UTC instant 保存；業務日期是獨立的年月日值。需要的 IANA zone／當時 offset 保存為 context，不能將日期型資料靠 UTC 午夜猜回。
- occurred／authorized／posted／settled／value date 不互相冒充；未知值保持未知。Audit 的記錄時間與交易日期分開。

## 3. 權威實體與欄位責任

### FinancialTransaction

保存 public ID、workspace、kind、來源模組與來源業務 ID、業務日期／必要時間 context、有效狀態、version、Audit、operation reference，以及 refund／reversal／replacement 對象。source reference 不能取代正式金額與財務語意。

### LedgerLeg

保存 transaction ID、account ID、currency／scale、signed minor amount、role、必要的 charge／conversion reference。Account 幣別與 leg 幣別必須相容；同一 operation 引用的 Account 與 transaction 屬同一 workspace。

帳戶經濟餘額由有效 legs 加總：資產增加為正、減少為負；負債增加為負、清償為正。信用卡「應付」畫面由明確的負債呈現規則轉換，不能一律取絕對值而把溢繳誤顯成欠款。M1 尚未開放的帳戶能力不得透過通用入口假裝完整支援。

### Allocation 與 Charge

分類拆分是消費／收入的分析分配，不是另一組資金 movement；不得把 split 金額再加一次到帳戶。Charge 保存類型、金額／幣別、payee、是否包含於總額及來源 reference，並能對應到實際資金 leg。

若 transfer principal 為 100 USD、另收 1 USD 費用，資金紀錄可表示 source principal −100 USD、source fee −1 USD、destination 對應原幣金額；Fee component 引用該 fee leg，不再額外扣第二次。使用其他 leg 表示方式時也必須通過同一資金與費用對照驗證。

### OperationReceipt

保存 workspace、operation ID、operation kind、穩定化輸入指紋、結果 transaction IDs、完成時間與結果版本。與業務／Ledger 紀錄同一 transaction 寫入；唯一鍵守住競爭。

同 ID／同輸入回傳既有結果；同 ID／不同輸入拒絕。失敗回滾不留下「已成功」receipt。新的一筆同額交易使用新 ID。Receipt 與必要去重紀錄納入備份；清理政策在對外承諾前驗證，不能先加任意短期 TTL。

### 可重建資料

AccountBalance、MonthlyCategorySummary 等是 projection，保存處理至哪個 revision／change version；正式投資 lot 等非資金資料仍由 Investment 保存。不能假設單靠 Ledger 金額就能重建所有投資資訊。

## 4. 寫入接口與交易邊界

初版公開操作按財務語意定義：建立一般收入／支出、期初餘額、轉帳／換匯、退款、反轉、更正及 metadata revision。Card／Investment 的特定業務操作在自己的 Application 層，透過相容的財務契約接入；Ledger 不按每個來源模組新增一套私有寫入路徑。

每次命令攜帶 workspace、operation ID、必要 expected version、明確業務參數與 actor/source context。成功結果包含正式 ID、version、提交狀態；必要後續工作另列 pending，不把報表失敗混成財務提交失敗。

完整流程：

1. 做純輸入格式檢查；需要遠端參考資料時在 DB transaction 外取得，保存使用者確認的來源／時點。
2. 頂層 Use Case 開啟一個 Unit of Work；用同一 session 查重、讀有效版本及參與帳戶／原交易。
3. 各模組驗證自身規則；Application 核對跨模組金額、幣別、關聯及狀態相容。
4. 寫入所有權威紀錄、必要 projection、Audit、operation receipt 與可靠後續工作的 job／outbox。
5. 同一 transaction commit 後回傳正式結果。提交前任一步失敗全部回滾；提交後回覆遺失以 receipt 查回。

參與模組不得自行 commit／開第二條寫入連線。Domain 不接觸 connection handle；transaction-aware adapters 由同一 composition factory 建立。並行修改依 expected version 與 DB 一致性檢查處理，不以預覽快取作最終判斷。

## 5. 財務規則與狀態轉移

- **期初餘額**：影響餘額，不列一般收入；更改須保留審計及明確更正路徑。
- **一般收支**：由明確 kind 決定分類／報表語意；Account legs 表達資金，不能只靠正負數判斷全部事件。
- **同幣轉帳**：本金流出流入相等；費用另可追溯。本金不列消費。source 與 destination 相同且沒有合法業務語意時拒絕。
- **跨幣轉帳**：保存兩邊實際本金、轉換關係、成交 context 及費用；不把不同幣別數字直接求和。不存在可靠匯率且已知道兩邊實際金額時，可保存該事實並區分推算比率，不冒充外部報價。
- **退款**：同 workspace、可退款的原消費及 component／allocation 範圍；累計有效退款不得超過該原額。跨幣退款需保存實際收回資金及原消費計價下的退款額，原額上限不以今日匯率重估。超出範圍的補償須使用正確的其他事件，不放寬 Refund 上限。
- **更正／反轉**：已正式入帳的財務改動使用可追溯的反轉與替代事件，同一提交完成；metadata 編輯保留 revision。已有退款／對帳／投資後續依賴時須通過對應更正規則，不做通用級聯刪除。
- **刪除與反轉分開**：允許 soft delete 的一般紀錄，tombstone 會讓原事件退出有效集合；若已用反轉事件抵銷原額，原事件必須仍被計入，不能再因 UI 隱藏排除原額造成雙重抵銷。具體可刪除狀態須在 operation policy 與 UI 同步明列。
- **分期與信用卡**：1A 保留原購買總消費與負債，各期為應繳／付款安排；繳款移動資金與清償負債，不再列原消費。pending／posted 與實際帳單差異由 Card 規則更正，不能雙記。
- **Draft／Staging／候選定期交易**：不影響正式餘額；確認並完成 posting 後才具財務效果。

## 6. 讀取與可辨識錯誤

餘額／寫入所需資料在同一 transaction 更新，或直接從權威資料讀取。跨模組即時摘要使用同一讀取快照或相容版本；常用報表與重型分析可依 Q124 延後，需有持久待更新狀態及可重建途徑。

錯誤至少區分：invalid input、precision／overflow、currency mismatch、workspace mismatch、account unavailable、version conflict、operation ID conflict、refund limit、dependent records、unsupported capability、provider unavailable、storage failure。UI 顯示可理解原因，Audit 保存必要診斷；不得把 error 包成空集合、零匯率或成功。

## 7. Migration 與備份契約

模組擁有 schema 定義與 migration 步驟，App manifest 協調全庫順序與相容性。涉及兩個模組的變更先核對共同前置版本，不各自升級到不相容狀態。

備份保存全部已有權威資料、歷史、Audit、必要 receipt／去重資訊、附件引用與 module versions。關閉 UI 不排除資料；不了解必要模組版本時拒絕正式還原，不能略過後宣稱成功。

2A 的最小 envelope 支援密碼與文字救援金鑰兩條獨立解鎖路徑，實際密碼學套件及 KDF 參數必須經技術 ADR 與測試決定，不在此自製演算法。還原在暫存區解密、驗證、migration、重建與核對，再可恢復地切換。失敗保留原庫；兩條路徑都要在沒有原裝置密鑰的乾淨環境驗證。

DB 與平台金鑰的正式配對、發布及中止復原另見[生命週期契約](storage-lifecycle-contract.md)。目前原型呼叫者持有 key 的方式不能直接當成正式切換協定；新增契約仍需 host 故障注入與 Android 驗收。

## 8. 本版尚未宣告完成

資料版本、模組主責、升級前備份與暫存升級的具體邊界另見[資料演進契約](data-evolution-contract.md)。目前原型的自動 migration 入口尚未具備完整升級前安全備份協調，不能直接作為正式啟動流程。

對應的具體數值與故障情境見[驗收案例](foundation-acceptance.md)。值型別與部分業務規則已有測試，正式 schema／資料庫適配器仍待完成；ADR-01／02／03 尚需完整資料路徑驗證，ADR-04 的加密／異機還原、ADR-06 的 provider 與 ADR-08 的執行 gate 尚未結案。套件配置、文件和工具安裝不能取代這些結果。
