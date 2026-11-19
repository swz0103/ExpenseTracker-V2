# 文件導覽

> 要找什麼，看哪一份。怎麼寫文件、何時更新，見 [conventions.md](conventions.md#四文件)。

| 想知道 | 看 |
| --- | --- |
| App 能做什麼 | [product.md](product.md) |
| 程式怎麼分、依賴規則、資料流、資料來源 | [architecture.md](architecture.md) |
| 帳本模組怎麼拆、每個成員的新家、拆分進度 | [ledger.md](ledger.md) |
| 名稱怎麼取、檔名後綴、舊名對照通用詞 | [naming.md](naming.md) |
| 顏色、字級、元件、版面規則 | [design.md](design.md) |
| 改程式、加功能、寫測試、寫文件、發版的規則 | [conventions.md](conventions.md) |
| 本機開發、檢查指令、CI、發版步驟 | [development.md](development.md) |
| Android 端的實作、權限、Google 設定、簽章 | [android.md](android.md) |
| 每版改了什麼 | [CHANGELOG.md](CHANGELOG.md) |
| 要在手機上確認的事 | [acceptance.md](acceptance.md) |
| 還沒做的、限制、刻意不做 | [roadmap.md](roadmap.md) |
| 為什麼這樣決定 | [adr/](adr/)，現況見下表 |

## 決定紀錄的現況

決定紀錄（ADR）寫的是當時的決定，事後不改內容；被後來的決定取代的部分，以這張表為準。`docs_test` 檢查每份 ADR 都在表上。

| ADR | 主題 | 現況 | 現在看 |
| --- | --- | --- | --- |
| [0001](adr/0001-target-architecture.md) | 目標架構 | 套件分層有效；App 內的分層由 0002、0003 取代 | [architecture.md](architecture.md) |
| [0002](adr/0002-feature-folders.md) | 依功能分資料夾 | 有效；第 1 節由 0003 取代，資料夾名稱（`compose/`、`look/`、`ui/`）由 0009 取代 | [architecture.md](architecture.md) |
| [0003](adr/0003-layer-rules.md) | 分層規則 | 有效 | [architecture.md](architecture.md)、`layers_test` |
| [0004](adr/0004-design-system.md) | 設計系統 | 有效；顏色類別改名 `AppColors`（0009） | [design.md](design.md) |
| [0005](adr/0005-backup-choices.md) | 備份取捨 | 有效 | [android.md](android.md) |
| [0006](adr/0006-retire-white-cards.md) | 白卡元件退場 | 已完成；「主卡裡並排淡色小格」由 0007 取代 | [design.md](design.md) |
| [0007](adr/0007-balance-bar.md) | 結餘條 | 有效 | [design.md](design.md) |
| [0008](adr/0008-ledger-aggregates.md) | 帳本聚合 | 有效，分階段進行 | [ledger.md](ledger.md) |
| [0009](adr/0009-folders-and-names.md) | 資料夾與命名 | 已完成；文中的舊路徑是改名前的 | [naming.md](naming.md) |
| [0010](adr/0010-data-that-lasts.md) | 資料十年可讀 | 有效 | [architecture.md](architecture.md) |
| [0011](adr/0011-version-numbers.md) | 版本號 | 有效 | [development.md](development.md) |
| [0012](adr/0012-ledger-stays-in-the-app.md) | 帳本暫不移出 | 有效 | [ledger.md](ledger.md) |

各模組自己的說明在它的 README：`apps/expense_tracker`、`packages/core`、`packages/domain`、`infrastructure/storage`、`infrastructure/vault`、`infrastructure/market`。

`images/` 是根目錄 README 的截圖。
