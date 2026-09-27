# 持續開發與分支收斂

2026-09-27：依使用者最新指示，恢復地基與 M1／M2／M3 CORE 開發直到使用者回來；目前不做實機、不正式發版。既有試用 APK 與測試結果是階段產物，停止條件已取消。

## 固定工作循環

1. 讀最新進度與實際 Git／CI，再選一個合理業務子集；資料層、備份及升級影響先說清楚。
2. 回查依賴的既有模組，將財務錯誤、資料遺失風險、重複規則、效能瓶頸列為有證據的修正；保留不受影響的程式，不進行無目的拆分。
3. 執行受影響回歸、失敗與重試案例；整合點在本機執行完整主機清單及必要大量資料驗證。Actions 依[額度政策](ci-budget-policy.md)暫停自動觸發；雲端未執行須明列，仍需雲端 gate 的收斂批次暫緩。未通過先修，再往下做。
4. 以小型 PR 交付子集；沒有資料保存與 UI 的 Domain 子集明確標記，不能稱為完整 capability。需要實機或外部帳號的項目保留 gate，完成其他不受阻礙工作。
5. 通過的串接分支逐批收斂到整合分支，避免每個內部工作單永久留下獨立 GitHub 分支。main 保留到驗收，不強推。

## 收斂保護

- 逐一保存原 PR、base、head 及 exact SHA；確認遠端 head 沒有新變動，且都是整合提交的祖先。
- 建立指向完整階段提交的整合分支及 PR，保留所有原始提交，不把合併審查入口當成正式架構 Freeze。
- 整合 CI 通過後，先調整後續 PR 的 base，確認 diff 不變；再關閉已被取代的 PR、移除已涵蓋的舊遠端分支。PR 歷史、提交與本機分支仍可追溯。
- 任何獨有提交、未處理 review、CI 失敗或其他工作中的依賴都先保留，不以清理為由丟棄。

## 第一批：地基 #1～#12

整合分支 `integration/foundation-core`；[PR #32](https://github.com/swz0103/ExpenseTracker-V2/pull/32) 對 main。完整提交 `222edebf6a9b43f93778b5044a169e5745a11e61` 與原 #12 相同；#1～#12 各 head 均已確認是該提交祖先，沒有新增或重寫產品程式。原始對照見[批次紀錄](branch-history/foundation-001.json)。

狀態：整合 CI 八個工作全部通過（126 項主機測試）；原十二個 PR 均無留言或待處理 review。#13 已改依賴此整合分支，改接前後完整 diff 相同。#1～#12 已關閉，對應十二個舊遠端分支已移除；其提交全保存在整合分支。本輪開放 PR 由 31 收斂為 20（之後新增功能 PR 另計），#14～#31 的既有依賴暫時保留。這一批涵蓋架構、值型別、帳戶／Ledger、共用交易與加密還原地基，後續平台及 App 的測試仍以各自 PR 為準。

## 第二批：儲存、平台入口與安全備份 #13～#27

沿用 `integration/foundation-core`／[PR #32](https://github.com/swz0103/ExpenseTracker-V2/pull/32)，以 fast-forward 更新到原 #27 的完整提交 `b1413921165f0c0abe6171e6d1b8671f76e29f81`，沒有重寫提交。原 #13～#27 各 head 均已核對遠端未變動、屬於該整合提交祖先、各自 CI 成功且沒有留言或 review；[第二批紀錄](branch-history/foundation-002.json)保留原 base、head、SHA 與檢查來源。

狀態：整合 CI 的 303 項主機測試／12 個工作全部通過；#28 已改接整合分支，前後完整 patch 相同。#14～#27 已關閉；#13 因 base 向前推進並包含其 head，被 GitHub 自動辨識為已合入 **integration/foundation-core**。這批 15 個遠端功能分支均經再次核對無獨有提交、無開放依賴後移除，本機分支與所有原始提交保留。main 仍為 `d0d39e1de32774aca319b8fed0cc9ee288cbb94a`，沒有合併或改動 main。本批清理時開放 PR 由 24 降至 9；後續紀錄 PR 另計。

## 最新接續方向

從最新已驗證的 `0745253`（#31，331 項主機測試通過）接續 M1-02。先完成獨立 Categories 業務的雙層分類規則，再接入版本化保存、備份與錄入 UI；Tag／Merchant 按其資料主責分批接入。對現有 preview 的整合不僅更換名稱，必須補足產品所需行為與相容路徑後才提升 capability 狀態。

#34 已完成分類 Domain；#36 接入分類持久歷史及 schema 4／snapshot 3 暫存還原。#38 完成獨立升級控制紀錄，#39 調整 Actions 額度政策；其後 `feat/ledger-category-upgrade` 完成[限定 Ledger 3 → 4 的同鎖備份、轉換與發布](ledger-category-upgrade.md)，421 項本機主機清單通過，雲端未執行。接續分類公開操作／讀取接口與容量保護，再完成交易引用與 UI；待雲端 gate 的分支收斂先保留，未完成的金融及平台驗收不變。

`feat/category-session` 依賴 #40（`80a588f`），完成[分類工作階段及備份容量](category-session.md)，164 項受影響本機回歸及混合大量資料驗證通過。沒有新雲端 checks，因此本輪不收斂需要雲端 gate 的批次、不刪除舊分支；下一功能從此分支接交易分類引用，依賴鏈持續保留。

`feat/ledger-category-references` 依賴 #41（`095d81f09638e84d4676d2edaa42381b1c5ed654`），完成[交易分類引用與歷史還原](ledger-category-references.md)的底層保存／暫存驗證。完整 14 套件共 464 項獨有本機案例通過，包含最後重複分攤修正後的快照及加密全量回歸，以及新舊兩條大量資料路徑；雲端未執行，因此依然保留所有後續堆疊分支，不進行需雲端 gate 的收斂。下一分支從此 head 接 schema 4 → 5 安全升級及工作階段接口，不能將低層 schema 開關當成已啟用產品能力。

`feat/ledger-reference-upgrade` 依賴 #42（`4cd097f4e94704ae3a830eff1925ac5c6353f805`），完成[分類引用升級及工作階段](ledger-reference-upgrade.md)。170 項受影響本機案例、新舊大量路徑、11 處程序中止及 4 條單憑證乾淨還原通過，雲端未執行。下一功能從此 head 接 App 升級流程；保留整個依賴鏈與原 PR，未繞過雲端 gate 收斂，也未改動 main。

`feat/app-category-upgrade`／[PR #44](https://github.com/swz0103/ExpenseTracker-V2/pull/44) 依賴 #43（`1424c5863460d2639f2c1e41889eaef6c9d2c1fc`），將原先交付規則草稿延伸為同一批 [App 分類與安全升級](app-categories.md)。14 套件 506 項本機案例、四組獨立大量資料流程及 0.3.0 開發包封裝通過；App／雲端／實機狀態依[驗證清單](test-results/app-category-host-2026-09-27.json)區分。下一功能分支 `feat/category-management` 從此批接分類搬移／合併，保留堆疊依賴；沒有通過雲端 gate 的分支不在本輪關閉或刪除。

`feat/category-management` 依賴 #44（`f0bd94e6137692eee24092732d50204961a0ba19`），完成 App 分類搬移及明確合併，36 項 App 完整回歸、格式／分析／架構掃描與 0.3.1 開發包封裝通過。底層格式與安全程式未變更，沿用前批完整整合及大量資料證據，[本批清單](test-results/category-management-host-2026-09-27.json)清楚分開新執行與既有結果。下一分支從本批接交易 Tag；雲端 gate 尚未通過，不收斂或刪除這些堆疊分支，main 保持原提交。
