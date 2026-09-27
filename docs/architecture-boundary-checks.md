# 業務套件邊界檢查

對應[工程規格第 1 節](foundation-contracts.md#1-套件與依賴)及使用者已選的[按業務拆分](architecture-proposal.md)。目前正式業務套件只有 `foundation_values`、`accounts`、`ledger`；本 gate 保護其公開入口與依賴方向，未宣稱所有未來模組已建好。

## 實際允許的方向

Accounts → Foundation Values；Ledger → Foundation Values；Foundation Values → 已固定版本的 UUID。Accounts 與 Ledger 不互相引用，資料保存與跨模組流程仍由原型 adapters 接合。

[boundaries.json](../architecture/boundaries.json) 列出每個現有業務套件的目錄、公開 Dart 入口與允許的直接 runtime dependency。新增 `packages/` 業務套件必須同時登錄，新私有檔案不會自動成為公開 API。

## CI 會拒絕的變更

- 在現有 Domain 的 pubspec 加入未允許的 runtime dependency，例如 Flutter、SQLite、平台儲存或另一個未允許業務；即使暫時未 import 也拒絕。
- Domain import 未宣告／僅 dev dependency 的 package，或 `dart:io`、`dart:ui`、`dart:ffi` 等未允許 SDK library；條件式 import／export 的每個分支都檢查。
- 其他套件直接 import／export 已登錄業務的 `src/` 或未公開入口；原型的 lib、bin、test、integration_test 也遵守此規則。
- 相對 import／part／part-of 跨套件、Domain lib 引用 test、package URI 的 `..`／編碼逃逸，以及透過未掃描 source tree 的相對引用。
- 真正的業務依賴循環、錯誤 local path、未登錄新業務、重複套件名稱、缺失公開入口、業務 dependency override、無法解析的 Dart 或未知 policy version。

檢查使用固定版本的 Dart analyzer AST 與 YAML parser；註解或一般字串內的 `import` 不算依賴。第一輪負向測試發現 URI parser 會先正規化 `..`，已改成先核對原始 URI，並加入百分比編碼案例，不以 URI 正規化後看似合法為由放行。

## 本機與驗證

在 `tooling/architecture_checks` 執行：

```powershell
dart pub get --enforce-lockfile
dart analyze
dart test --reporter expanded
dart run bin/check.dart ../..
```

15 項負向／正常案例與實際 repository 掃描、靜態分析均通過。CI 新增獨立 `architecture-boundaries` 工作，出錯會列出相對檔名、行號與可辨識規則；它不改寫來源檔案。

## 限制與後續擴充

此項檢查直接依賴與公開 Dart 入口，不驗證跨模組 SQL 的資料主責、transaction 共用、動態載入、runtime 行為或所有第三方 transitive dependency。原型之間的依賴尚未當作正式業務 graph；新 App／adapter／UI 套件進入正式目錄時，應先定責任與政策，再擴充檢查，不能把平台相依一概放進 Domain。

掃描範圍為 `packages/` 與 `prototypes/` 下各 pubspec 套件的 lib、test、bin、integration_test；生成快取與 build 不納入。這不是防惡意修改 policy 的安全沙箱；policy 與 checker 的變更仍須透過 PR 審查。套件內部拆分依實際需求進行，不為通過此 gate 提前建立尚未使用的 Domain。
