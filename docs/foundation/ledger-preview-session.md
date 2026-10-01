# 試用帳本工作階段

2026-09-27 接續：明確 schema 4 模式增加[分類公開接口與統一容量保護](category-session.md)，並修正工作階段快照格式及僅分類 workspace 的發現。舊 App 仍使用 schema 3；以下初版案例數保留為歷史紀錄。

`LedgerStore.withSession` 取得生命週期排他權並核對既有加密世代後，提供帳戶建立、收支、摘要、日期／ID 游標分頁和 snapshot；SQL／DB handle 不對 UI 公開。命令依序執行；callback 返回或失敗後拒絕新命令，等已接受的命令結束，再關閉 DB 並釋放排他權。呼叫端必須 await 寫入結果；關閉不是撤銷已接受的交易。

同一 isolate 的其他世代操作會收到 busy。App 離開前景時必須關閉 session；本接口本身不實作解鎖或閒置計時。初始化使用空 snapshot／stage／驗證／發布路徑，鎖內要求沒有 active generation；同一 operation 可重試，另一 operation 不能清空既有帳本。新手動入帳來源 `preview-manual-v1`，不改寫 fixture。

暫定 32 帳戶／5,000 交易（含期初）的保守試用上限，超限新增拒絕、receipt replay 仍可執行。最終容量須依[大規模測試計畫](../delivery/installable-preview-plan.md)驗證；目前不是效能承諾。備份保留完整驗證與 16 MiB／50,000 列限制。

新增 6 項 host 案例：空初始化不可重設、失效 facade、callback 失敗排空、20 次同時重送只入帳一次、失敗後續命令、跨 workspace 查詢隔離、62 筆資料分頁、排他權與溢位完全回滾。Ledger 共 54、世代 72、還原 29、交易 17，共 172 項本機回歸通過。本輪無裝置驗證。
