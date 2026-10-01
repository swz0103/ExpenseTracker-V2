# GitHub Actions 額度與本機驗證

**2026-10-01 整合分支更新**：使用者要求以 GitHub 版本在本機持續製作，並在 GitHub 整合分支執行 CI。現行分支為 `integration/v2`；`V2 integration validation` 在該分支的 `.github/workflows/**`、`packages/**`、`prototypes/**` 或 `tooling/**` 變更時執行，也在提向 `main` 的 PR 執行。同一 ref 採 `cancel-in-progress`，每個 job 仍有 timeout。這取代下文 2026-09-29 的臨時窄路徑政策；未取得 GitHub billing 即時數字，不啟用付費或超額設定。

**2026-09-29 整合驗證例外**：使用者明確要求現在以 Actions 驗證並收斂過多分支。原兩個高成本 workflow 仍停用；新增 `V2 integration validation` 僅在 `integration/v2-core` 的 workflow 或本次發現的跨平台子程序測試檔變更時自動啟動，四個 Ubuntu job 的 timeout 合計最多 68 runner 分鐘，涵蓋本機清單全部 22 個套件。後續一般程式／文件推送不重跑。GitHub 帳單 API 因目前權限不足、瀏覽器未登入，尚無即時剩餘額度；本次採使用者 2026-09-27 回報的約 190 分鐘作上界參考，不能將它視為目前已核實額度，不啟用付費。首輪固定 SHA `0a84b5416d4e3d9f79a8d9ee776eeff6f0b7c8f3` 的架構、業務、Flutter 三組通過；資料保存組只因交易測試寫死 Windows `.exe` 在 Linux 失敗。四個 job 實際時間合計約 23 分鐘；已修正並完成本機重驗，故只針對修正後的固定 SHA 再作一次有上限的完整驗證，不盲目反覆重跑。若 GitHub 拒絕執行或任一 job 失敗，明列為未通過。舊 workflow 不恢復自動觸發，`main` 不合併。

**驗證結果補記**：修正後 SHA `41cb0f415f3fcc2a9052aecc207915f093e595b2` 的[第二輪執行](https://github.com/swz0103/ExpenseTracker-V2/actions/runs/36508480923)四個 job 全部成功。兩輪按 job 啟迄時間相加約 48 分鐘；GitHub 的即時帳單與實際入帳分鐘仍不可讀，不把這個估值當作剩餘額度。分支收斂後不再為文件更新觸發雲端測試；下一次需要雲端驗證時重新核對額度與固定程式提交。

2026-09-27：使用者回報本月剩餘 190、每月 2,000 額度。GitHub Free 官方列的是每月 **2,000 執行分鐘**，不是 2,000 次 workflow；剩餘 190 以使用者回報為準，尚未讀取帳戶帳單核實。多個 job 的執行時間不能只用整個 workflow 的牆鐘時間估算，計費仍須核對實際 runner 與帳單。來源：[方案包含用量](https://docs.github.com/en/billing/reference/product-usage-included)。

## 立即生效

- 已在 GitHub 暫停 `Foundation probe`（367688810）與 `Android foundation host checks`（367981228），確認皆為 `disabled_manually`，且沒有執行中或排隊的工作。這也保護尚未套用新 YAML 的舊分支。
- 後續 YAML 改為只接受 `workflow_dispatch`，移除每次 PR／main push 的自動執行；完整既有測試步驟保留。加入同 workflow／ref 重複工作取消與缺少的 job timeout，限制意外重複及失控執行。
- 平時開發、推送、開 PR、文件修改與分支整理均不啟動 Actions。本月剩餘額度先保留給重要驗收，不因需要綠勾而重跑；不新增付費、runner、外部服務或修改付款／超額設定。
- 既有資料與安全 gate 不降低。PR 明列「本機通過／雲端未執行」；沒有 checks 不代表雲端通過，主機測試不代表實機通過。需要雲端 gate 的整合／分支收斂先保留，不能繞過 branch protection 或自行合併 main。

## 本機工作方式

每次修改跑受影響套件及其依賴回歸；合理整合點才執行完整主機清單，以及有意義的大量資料、失敗、備份還原與升級驗證。已成功且程式未改變的檢查不反覆重跑。既有大量資料工具與 Android 打包仍按其文件另外執行；此腳本不操作手機、不發版。

從 repository 根目錄，以 PowerShell 執行：

```powershell
# 查看清單，不執行測試
./tooling/run-host-checks.ps1 -PlanOnly

# 選取受影響套件；需要時明確加上依賴套件，本腳本不自動猜測影響範圍
./tooling/run-host-checks.ps1 -Package prototypes/storage_generation,prototypes/ledger_generation -Offline

# 整合點完整主機驗證
./tooling/run-host-checks.ps1 -Offline
```

使用鎖定的 Dart 3.13.4／Flutter 3.47.5，可用 `-Dart`、`-Flutter` 指定本機完整執行檔路徑。先確認版本符合兩份 workflow。`-Offline` 只限制 pub 相依解析，不是所有底層建置工具的網路隔離；首次缺相依需正常取得既有鎖定版本，不自動升級套件。

腳本目前列出 20 個主機套件（包含 Tags、Merchants、手動 Entry Drafts、金額輸入、Reports 與 Data Exchange 業務）；兩份停用的 workflow 與本機清單是否完全同步，需在恢復雲端驗證前另行核對。腳本檢查 lockfile、格式、靜態分析、五個原生 worker 建置、測試與架構邊界；循序執行避免 Windows 原生檔案互鎖，任一步失敗即停止且不輸出全數通過。新增套件時必須同步更新 workflow 與本機清單。每次驗證在進度／PR 記錄實際版本、範圍、結果及尚未執行的 gate；測試未提交的修改時不得當成 PR exact SHA 已通過。

## 何時恢復雲端驗證

只在重要整合／驗收需要獨立環境證據時評估：先核對實際剩餘分鐘及計費週期，再用已完成本機驗證的固定提交，選擇必要 workflow、估算消耗並留緩衝。不可將 190 視為可跑 190 次完整檢查；額度不可核實時保留雲端工作，繼續不受阻礙的本機開發。跨月不自動假設額度重置。

目前服務端仍停用 workflow；本 PR 也不會自行合入 main。GitHub 要求手動觸發設定存在 default branch，因此 **PR 中的 `workflow_dispatch` 不等於現在已可手動執行**。恢復前須確認 default branch 的設定與啟用狀態；不能為啟用測試擅自合併 main、變更 default branch，或重新打開舊分支的自動觸發。來源：[手動執行 workflow 的條件](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)。

本政策已同步到持續開發排程；最新使用者授權為啟用、每 20 分鐘接續，詳見工作進度。排程喚醒不代表執行一次 Actions。

## 本次調整驗證

本機解析兩份 YAML，核對只有手動觸發、原有 job／step 內容完整保留、每個 job 有 timeout，並確認本機清單與遠端 14 個套件完全一致。PowerShell 語法及未知套件拒絕檢查通過。以新入口實際跑架構 15 項、原生交易程序 11 項與 Flutter host 17 項，共 43 項通過，包含格式、靜態分析、worker 重建及 repository 邊界掃描。

這是目前工作目錄下三種執行路徑的驗證，並非全部 14 套件重測，也不代表尚在開發的 Ledger 升級已完成。此次未啟動雲端測試；沒有操作手機。

## 本機資源回查

2026-09-27 商家整合時，三組本機套件並行造成一項既有 App 密碼還原超過原有 30 秒限制；固定版本以單一程序重跑 25 秒通過。後續大型資料與加密重負載工作依序安排；輕量讀取與文件整理仍可並行。不以放寬斷言、提高 timeout 或重複雲端執行掩蓋資源競爭，完整失敗與重驗記錄見[本批證據](../test-results/2026-09-27/transaction-merchants-host-2026-09-27.json)。
