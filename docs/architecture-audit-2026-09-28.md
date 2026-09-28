# ExpenseTracker V2 架構核對：第一輪證據與處置

狀態：持續審查，非 Architecture Freeze、main merge 核准或 CORE 完成聲明。依[實作安排](implementation-plan.md)與[分支收斂規則](branch-consolidation.md)執行；貼入的 reviewer 清單視為待驗證假說，採用以實際 source、測試及 PR 為準。

## 基準與可重現證據

- 本輪以已通過主機驗證的 `feat/transaction-notes` 完整 SHA `d6714eecd525cbd31277e179bee455da2fc0c85e` 作為架構修正起點；它是 [PR #61](https://github.com/swz0103/ExpenseTracker-V2/pull/61) 的 head，基於撤銷 PR #60。當前更正分支 `feat/transaction-corrections` 已到 `6255a1fd364222e7a06bd0762f21bdf863a93072`，只有契約與 Ledger 提案，不是完成的更正能力。
- 2026-09-28 查核私人 `swz0103/ExpenseTracker-V2` 有 34 個 open PR；#28～#31 與 #33～#61 主要依功能堆疊，#32 是指向 main 的地基整合 PR，須作為獨立節點核對。這些較早分支目前在備註 head 的祖先範圍內，但不代表其雲端 gate 已通過。遠端 `main` 仍為 `d0d39e1de32774aca319b8fed0cc9ee288cbb94a`。兩個雲端 workflow 均為 `disabled_manually`；沒有新雲端 gate，也沒有實機完成證據。因此不得把 stacked PR 數量當作已合併交付，不能把空 checks 當成通過。
- 備註基準的[固定來源證據](test-results/notes-host-2026-09-28.json)包含 18 套件／869 主機案例、程序中斷、[大量資料](test-results/notes-scale-2026-09-28.json)及本機 Android 建置。重構分支仍須跑它所影響的回歸；不能沿用父提交結果替代新 SHA 驗證。

## 已確認與未確認的架構風險

1. **畫面直接依賴 schema 版號：確認。** `main.dart` 的入口、明細、表單與清單原本多處比較 `schemaVersion >= N`；`preview_drafts.dart`、`preview_copy.dart` 和 App 建立 `LedgerStore` 的位置也重複門檻。這把 migration 編號當作畫面契約，新能力加入時容易漏改一處。本批採一個有型別的 `PreviewCapabilities`，由 V2 schema 對照產生；畫面與應用操作只問能力，儲存與還原仍保留版本資訊。保留歷史 reader 各版本測試，不建立空的 service/use-case 包裝層。
2. **首頁狀態過度集中：確認維護風險，尚未證明行為錯誤。** `PreviewHomeState` 位於約 1,715 行的 `main.dart`，持有鎖定、路由、草稿、帳戶與交易表單狀態；部分業務畫面已用 part 檔拆出。現有鎖定浮層、草稿中斷、privacy 與 engine epoch 測試不能被當作「無競爭風險」證明，但也不支持現在一次重寫 UI。下一步針對可重現的 stale view／鎖定次序做 deterministic 測試，只拆有明確狀態所有權與錯誤案例的區塊。
3. **prototypes 目錄的正式依賴：確認命名／邊界不清。** `expense_preview` 是目前可建置的 Android App；`ledger_generation_probe`、`storage_generation_probe`、`encrypted_storage_probe`、`validated_restore_probe`、`backup_envelope_probe`、`modular_persistence_probe` 和 `android_foundation` 都在其 runtime 依賴鏈，不能視為可刪試驗。它們目前保有大量加密／升級 fixture，單純移動路徑或改名沒有正確性收益。先標示各模組資料主責及對外入口，等有確定的發版邊界再遷移，並維持舊資料升級測試。
4. **架構檢查涵蓋不足：確認。** `architecture/boundaries.json` 記錄八個正式 Domain package 的公開入口與依賴；以上 runtime prototype 尚未列入。既有檢查能保護 Domain 不依賴 UI，但不能單憑其通過宣稱整個 App 依賴圖已受控。後續需加可驗證的 runtime 依賴規則，先從禁止 UI 被底層反向依賴、禁止跨模組私有表捷徑開始；不以大量假接口掩蓋邊界。
5. **全面改寫錯誤模型：目前沒有證據。** `main.dart` 的 `_error` 以 `NoteException`、`LedgerException`、`PreviewLocked` 等型別及錯誤碼分派，沒有解析 exception 字串決定業務行為；未知例外使用不洩露內容的保守提示。保留此模式，只在具體錯誤被誤分類時補回歸。
6. **storage boolean 開關爆炸：有維護成本，尚未證明不一致。** 資料庫、snapshot 與 generation 目前都保留舊版 fixture 的能力組合；貿然一次換成新 registry 會改變 migration／restore 的測試面。本批先收斂 App 對 schema 的解讀。若後續新 schema 讓三層 mapping 出現實際差異，再用一份版本能力契約連同舊 reader fixture 一起改。
7. **效能與 lifecycle：保持測量門檻。** 既有 5,000 事件／備註案例證明該限定資料集可還原，不等於 100k+ 長期使用性能。草稿與 lock 已有真實程序退出及 Flutter lifecycle 測試；新增 interleaving 須以可控制延遲的測試證明問題，避免猜測式更動安全次序。

## 本輪調整的順序

先完成小範圍能力邊界修正與 App 全量本機回歸；接著對 UI 異步次序和 runtime package 依賴做可重現的檢查。確認的缺陷各自以小 PR 修復，不同時重寫 Ledger、Money、加密與大量產品功能。財務更正分支保留獨立提交，架構批次驗證後以無強推方式接回；再繼續 M1-04、M1-05 至 M3。分支收斂以真正通過適用 gate 的 SHA 為準，先更新後續 PR 依賴，再關閉已取代的 PR；`main` 合併、正式發版與實機驗收都不由這份初步核對推定完成。

## 能力邊界修正的本機證據

- `prototypes/expense_preview`：`flutter analyze --no-pub` 通過；`flutter test --no-pub --concurrency=1 --reporter expanded` 共 161 個案例通過。覆蓋舊 V2 版本升級、各交易入口、加密草稿、背景鎖定、隱私與大字體。這是修正後 App 的完整測試清單，不等於全部 18 套件或實機驗證。
- `tooling/architecture_checks`：15 個單元案例通過，對儲存庫執行的 `bin/check.dart ../..` 亦通過。該工具目前只保護已登記的 Domain 邊界；通過不代表前述 runtime prototype 依賴已被檢查。
- 此批未修改金融計算、資料格式或加密實作；歷史能力門檻保持 schema 3～12 的既有對應。雲端 workflow 停用，未執行新的 GitHub Actions；未進行實機驗證或合併 `main`。
