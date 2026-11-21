# 文件導覽

> 要找什麼，看哪一份。只寫現況；歷史在 git 與 CHANGELOG。怎麼寫文件見 [conventions.md](conventions.md#四文件)。

| 想知道 | 看 |
| --- | --- |
| App 能做什麼 | [product.md](product.md) |
| 模組、分層、帳本、資料流、備份、外部資料、由測試守住的規則 | [architecture.md](architecture.md) |
| 顏色、字級、元件、版面規則 | [design.md](design.md) |
| 怎麼加功能、命名、寫測試、寫文件、發版 | [conventions.md](conventions.md) |
| 本機開發、指令、工具、CI | [development.md](development.md) |
| Android 端、權限、Google 設定、簽章 | [android.md](android.md) |
| 手機上值得留意的事（不是發版門檻） | [acceptance.md](acceptance.md) |
| 現況數字、待辦、已知限制 | [roadmap.md](roadmap.md) |
| 每版改了什麼 | [CHANGELOG.md](CHANGELOG.md) |

各模組自己的說明在它的 README：`apps/expense_tracker`、`packages/core`、`packages/domain`、`infrastructure/storage`、`infrastructure/vault`、`infrastructure/market`。`images/` 是根目錄 README 的截圖。

## 決策紀錄（ADR）

ADR 寫決定與理由。每次大審查都重新檢討一次：過時的部分改寫（狀態行寫日期與改了什麼），整篇被取代、或只是某次改版紀錄的刪掉（細節留在 CHANGELOG 與 git 歷史）。`docs_test` 檢查每份都在這張表上。

| ADR | 決定 | 現況 |
| --- | --- | --- |
| [0001](adr/0001-target-architecture.md) | 目標架構：套件分層、單一模型、單一加密檔 | 有效（2026-11-21 改寫成現行名稱） |
| [0003](adr/0003-layer-rules.md) | App 內的分層規則由測試守住 | 有效（2026-11-21 改寫：大小是提醒不是上限） |
| [0004](adr/0004-design-system.md) | 設計系統：顏色、字級、元件只在一處 | 有效（2026-11-21 改寫：規則讀語法樹） |
| [0005](adr/0005-backup-choices.md) | 備份方式的取捨 | 有效 |
| [0008](adr/0008-ledger-aggregates.md) | 帳本拆成 Repository、Service、Commands | 完成 |
| [0010](adr/0010-data-that-lasts.md) | 資料十年可讀：每個次版號留帳本與備份比對 | 有效（2026-11-21 改成每個次版號一份） |
| [0011](adr/0011-version-numbers.md) | 版號只在發布時升，三碼各在什麼時候變 | 有效（2026-11-21 改寫：PR 可不升版） |
| [0012](adr/0012-ledger-stays-in-the-app.md) | 帳本暫不移出成純 Dart 套件 | 有效 |
| [0013](adr/0013-models-take-what-they-use.md) | 頁面拿帳本，模型只拿用到的部分 | 完成（2026-11-21：只量功能層） |
