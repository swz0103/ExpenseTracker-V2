# Accounts／Ledger 共用 Drift 交易原型

2026-09-27 接續：明確 schema 5 可保存[版本化交易分類引用](../../docs/ledger-category-references.md)，含收入／支出分攤、歷史位置、版本競爭及全量回滾。既有預設 schema 的拒絕規則保留；`fixture_allocation.dart` 是供主機測試共用的合成資料入口，不能用作產品初始化資料。以下原型測試數保留原批次歷程，最新驗證見工作進度。

這是階段 1 主機端整合原型：實際引入 Accounts、Ledger、Foundation Values 三個套件，以 Drift 2.35.0 + SQLite 3.6.0 寫入真實檔案。AccountsAdapter 與 LedgerAdapter 共用同一 ProbeDatabase；FinancialWorkflows 開啟並等待唯一 transaction 完成。

支援建立帳戶＋期初、一般收支、同幣轉帳與費用，以及帳戶封存。保存 events／legs、期初唯一性、operation receipt 與 Audit；同一操作重試回傳原結果 ID，不依賴本次臨時生成的 event ID。輸入金額改變時拒絕。每次寫入會重新讀帳戶版本與狀態，並在提交前檢查最終餘額範圍。

```sh
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
dart analyze
dart test --reporter expanded
```

13 項整合測試：五個階段故障回滾、保存重開後 115.00 餘額與收支口徑、receipt 重試與衝突、過期預覽、期初唯一性、轉帳失敗與費用不雙算、餘額溢位、workspace lookup 及同一 Drift executor 同時重試。每組檢查真實資料表、foreign keys 與 integrity。全部使用測試資料。

另有 4 項 migration 測試，合計 17 項。`test/fixtures/v1.sql` 從已提交的 bfc9ec7 原型產生並固定，內含真實舊格式的合成交易與 receipt，不在測試時用新模型重建舊資料。v1 → v2 在同一 transaction 新增來源 context 欄位與帳戶 legs 索引；旧資料標記 legacy-unspecified，不捏造來源。升級後逐列核對全部既有資料、重建 115.00 餘額，並確認舊 receipt 仍能重試。兩個 DDL 中斷點都回滾至 v1，可重新升級；未知版本 99 拒絕開啟且保留資料與版本。

## 限制

- 資料庫未加密，禁止存入真實帳本；不是正式可用 App。
- 限定原型使用 handwritten SQL，沒有生成式 schema／reactive queries；不能當成正式 migration 與備份格式。未知 schema 升級會拒絕。
- Domain 套件已分離；兩個 adapter 同置原型以驗證共享交易，正式 Data packages／ports 與相依邊界檢查仍待整理。
- schema 2／3／4 的 allocation 保存仍明確拒絕；僅 schema 5 開放經 Categories 驗證且帶預期版本的引用。
- Audit 只包含 operation kind／ID／時間；正式 actor/source、完整歷史、關閉與重新啟用保存流程仍待接入。
- 同 executor 並行通過不等於多程序／多連線的全部競爭情境。先前 SQLite 原型的程序退出測試仍保留，不能替代此 Drift adapter 的程序中斷測試。
- Android、SQLCipher／密鑰、乾淨還原與完整 migration gate 均未完成。此次只涵蓋 v1 → v2；裝置斷電、空間不足、重大 migration 前加密安全備份與正式 module manifest 仍待驗證。

來源：[Drift transactions](https://drift.simonbinder.eu/dart_api/transactions/)、[custom queries](https://drift.simonbinder.eu/sql_api/custom_queries/)。驗收對應見[案例](../../docs/foundation-acceptance.md)，進度見[紀錄](../../docs/work-progress.md)。
