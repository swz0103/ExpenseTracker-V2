# Categories 業務規則

M1-02 的 Domain 子集，來源：[RC-05](../../docs/architecture/architecture-baseline-v1.0-rc1.md#rc-05)、[FV-011](../../docs/architecture/full-vision-baseline.md#fv-011)。此套件不依賴 Flutter、SQLite 或 Ledger，公開入口只有 `categories.dart`，沿用 foundation_values 的 UUID v7 與 workspace。

## 已實作的行為

- 固定根分類 → 子分類；收入／支出 kind 建立後不改。禁止第三層、缺少父項、循環、跨 workspace 與跨 kind。
- 分類身份穩定、名稱可改、版本遞增；舊版本不得修改。名稱經 trim 後 1～100 個 UTF-16 code units，拒絕內嵌控制字元；同名不代表同一實體。有效根分類或子分類均可供交易選用。
- 封存保留原 ID 與父項。先封存所有使用中子分類才能封存父項，反向啟用則先父後子；讀取歷史不受封存影響。
- 子分類可換到同 kind 的有效根分類或提升為根；有任何歷史子項的根不能降為子分類。移動／重新分類對報表的產品口徑仍須在資料層及 UI 接入時明示，不改寫交易金額。
- 明確合併保留來源列與 replacement ID，不重寫交易引用。來源可為封存或使用中葉節點；目標必須有效且同 kind，需同時檢查來源與目標版本。來源有任何子項時拒絕整棵暗中合併，需先明確處理子項。
- 合併後的來源不可再啟用或修改；歷史查詢可同時取得原分類與 canonical 分類。後續目標再合併可形成歷史鏈；目標後來封存仍可讀取，但不供新交易選用。

## 回查與效能選擇

回看帳戶 Domain 與先前 snapshot 大量驗證：保留 immutable 狀態、workspace／expectedVersion 及去敏錯誤模式，沒有抽取一個混合 Account／Category 的通用 Entity。分類的跨列結構由完整 `CategoryCatalog` 一次驗證，避免僅檢查單筆父 ID 而留下第三層或孤兒。

還原時以迭代方式一次解析替代鏈並建立可丟棄的 canonical 索引，O(n) 時間／空間，不遞迴、不為每筆重掃整條鏈；之後歷史 resolve 為 O(1)。一萬筆合成連鎖分類案例驗證結果與原 ID 保留。每次 metadata 變動建立新 catalog 並重新驗證，成本 O(n)；這不是大量持續寫入或任意容量的效能保證。

版本耗盡時仍可讀取及檢查選用，metadata 修改拒絕加一溢位。沒有僅為新套件而更動既有 Account 財務規則。

## 尚未交付

這不是完整分類 capability。保存與可攜格式已接入共用 UoW 的版本比較、operation receipt／Audit、分類歷史、schema 4／snapshot 3 與加密暫存雙路還原。完整升級協調器、schema 4 世代發布／session、交易引用、統一容量預檢與簡潔 UI 尚待接入，因此沒有在 App 開放分類按鈕。現有 Ledger 的 allocation category ID 仍是先前原型接口，持久流程仍拒絕未驗證的分類引用。

Application 必須在同一寫入 UoW 取得有效 catalog、檢查受影響列版本與引用，再保存結果；這個純值物件不提供併發鎖、DB CAS 或持久操作去重，這些由上述資料 adapter 與共用交易承接。根分類合併時的子項批次搬移、報表依原分類／目前分類的口徑與產品完整流程仍由後續功能驗收，不能以本套件測試冒充完成。

## 驗證

```powershell
dart pub get --enforce-lockfile
dart analyze
dart test --reporter expanded
```

正常新增／修改、workspace 隔離、重複 ID、雙層結構、選用與版本、封存／啟用順序、移動、合併來源／目標版本、歷史鏈、損壞還原及版本邊界均有案例。CI 另執行實際 repository 邊界檢查與既有財務／加密／UI 回歸。
