# 2026-09-30 上市審查與分支整合

審查對象是當時最新的 `work/m2-cloud-backup`（`ad39c29`，2026-10-01 03:05 +0800）。另一支非 `main` 分支 `integration/v2-core`（`9ecffbc`）是它的祖先。這份紀錄用可出貨產品的標準看這條線，不把主機測試、文件或原型畫面當成正式發版。

## 分支整合

| 分支 | 提交 | 相對關係 |
| --- | --- | --- |
| `main` | `d0d39e1` | 未納入這次整合，仍是初始提交 |
| `integration/v2-core` | `9ecffbc` | 被 `work/m2-cloud-backup` 完整包含 |
| `work/m2-cloud-backup` | `ad39c29` | 比 v2-core 多 31 個提交，沒有需要反向撿回的提交 |

`git merge-base origin/work/m2-cloud-backup origin/integration/v2-core` 等於 `9ecffbc`。`origin/work/m2-cloud-backup..origin/integration/v2-core` 的提交數是 0。整合不需要解衝突；後續以這條包含兩邊的線為準。開放中的 Draft PR #67 仍指向較舊的 `integration/v2-core`，不能再把它當成最新程式。

這 31 個提交補上雲端備份核心與畫面、信用卡停用／帳單修訂／結帳後退款／分期退款說明、投資跨幣摘要、多來源行情路由，以及台股／美股分鐘線與安全存放的 API key。

## 上市結論

**現在不能當正式上架版本。** 日常記帳、信用卡與投資的本機垂直切片在主機測試裡沒有發現錯帳級缺陷，但發版 gate 仍缺：Android 實機、真實雲端帳號、單帳本 100k、以及雲端備份的實際上傳 runtime。有上限的 `V2 integration validation` 已在留下的分支通過；Foundation probe 與 Android foundation 仍是手動觸發，沒有重新打開。預設安裝的「雲端備份」只說明尚未連結帳號，不會上傳。

若有人注入 `cloudBackupGatewayFactory` 卻沒有另外跑上傳 worker，使用者會看到已排入上傳或已開啟自動備份，實際沒有上傳。這是出貨阻擋，不是文件裡已經寫明的 OAuth 缺口而已。

## 已核對、未列為缺陷的行為

- 停用信用卡後，既有 pending 仍可入帳，新授權會被擋住。帳務查的是條款歷史，不是只看目前啟用狀態。
- 已分配的帳單不能再修訂；畫面會隱藏修訂。
- 跨幣投資摘要缺匯率時不顯示合計，也不用 1:1 補上。
- 行情 fallback 會列出嘗試過的來源。成交與換匯仍以使用者確認的金額為準。
- 雲端上傳前用帳本密碼與救援文字各自驗證；provider 拿不到這兩個憑證。同一 backup ID 重試沿用同一個遠端物件。
- Fugle／Twelve Data 的 key 走系統安全儲存，不寫進帳本、匯出或雲端備份。目前 vault 是 Android 實作。

## 出貨前必須處理

1. **上傳 runtime 沒有接進 App。** `FlowCloudBackupScreenGateway.createBackup` 只呼叫 `scheduleVerifiedBackup`。全專案的 `runNext` 只出現在 `prototypes/cloud_backup` 的函式庫與測試。沒有背景迴圈時，成功文案與遠端歷史會長期不一致。
2. **自動備份只寫排程。** `configureSchedule` 更新 `CloudBackupScheduleStore`。App 沒有呼叫 `CloudBackupAutomaticScheduler.tick`。
3. **重新連結不恢復已終止的上傳。** `CloudBackupJobRunner.retryAfterUserAction` 有測試，畫面的 `_reconnect` 只重跑注入的帳號 callback 並重載歷史。登入失效、權限或 quota 造成 `failTerminal` 之後，使用者重新連結也不會用同一個 backup ID 再上傳。
4. **失敗狀態沒有畫面。** `lastFailure` 已寫入工作儲存，`CloudBackupScreen` 不讀它。
5. **Widget 測試的登入失效是同步丟出。** 正式 `createBackup` 不會在當下因 Drive 授權失敗而失敗，授權發生在之後的 `runNext`。這組測試不能拿來證明第 3 點已接上。

## 2026-10-01 阻擋修正狀態

上述第 1–5 點已在 `integration/v2` 修正：正式 gateway 在排入工作後執行有上限的 worker pump；畫面載入時會執行 scheduler tick、reconciliation 與既有工作；重新連結會重排需要使用者處理的終止工作並沿用相同 backup ID；畫面會顯示 pending 數量與持久 `lastFailure`。Widget 測試改以真正 runtime gateway 覆蓋建立、補跑、登入失效與重新連結，不再用同步丟出冒充 worker 授權失敗。

這些修正關閉 App runtime 阻擋，但不等於 Google Drive 已可用：OAuth client、正式 token transport、OS 背景喚醒、真實帳號與實機仍是外部 gate。市場資料也已改為免帳號日終／參考匯率來源；Fugle／Twelve Data 不再是正式預設。

## 契約與文件落差

- 自動路由目前依 registry 順序與 `preferredProviderIds`。功能矩陣原先寫依新鮮度、額度與使用者設定選擇；程式沒有這樣做，偏好也不會保存到下次啟動。矩陣已改成與 `packages/market_data/lib/src/routing.dart` 一致。
- 功能矩陣標的基線曾停在 `9ecffbc`，但停用後 pending 結算、帳單修訂與 schema 24 預設都在後面的 31 個提交。基線已改到 `ad39c29`。
- `prototypes/cloud_backup/README.md` 仍寫導航與 engine handoff 尚未接入；`main.dart` 與 `EngineCloudBackupBridge` 已經有這兩段。README 已改成目前邊界：導航與 handoff 在，上傳 runtime 不在。
- 註冊的參考匯率是 ECB 的歐元直連幣對與 CBC 的 USD／TWD。沒有合成 EUR→TWD。跨幣摘要缺匯率時留空是既有設計，不能解讀成所有幣別都已有真實匯率。
- `main.dart` 已超過 3,000 行，畫面狀態仍集中在同一個物件。這是維護風險，不是這次測到的錯帳。

## 主機測試

版本對齊 workflow：Flutter 3.47.5、Dart 3.13.4，Linux。執行方式對應 `tooling/run-host-checks.ps1`：`pub get --enforce-lockfile`、`dart format --set-exit-if-changed`、`analyze`、五個 worker 的 `dart build cli`、`test`，以及架構邊界檢查。Flutter 套件使用 `--concurrency=1`。沒有啟動 GitHub Actions，沒有接 Android 實機，沒有跑 100k 容量。

第一輪 26 個套件通過，共 1,104 項。`prototypes/expense_preview` 297 項通過、1 項失敗：`asset summary stays per-currency after transfer, masks and locks`。失敗點是首頁 `ListView` 在第一個幣別列排版後才修正 `maxScrollExtent`，`scrollUntilVisible` 以 100px 一步往下拖，下一列 `asset-total-USD` 沒有在檢查當下建好，拖過之後就找不到。畫面上的數字仍是 TWD 78.00、USD 101.00，排除帳戶也有計入。修正是在找到 TWD 合計後多 `pump` 一個 frame，再找 USD。這次沒有改餘額計算。

`expense_preview` 修正後重新執行 format、analyze 與全部測試，298 項通過。連同第一輪已通過的 1,104 項，主機清單合計 1,402 項。詳細套件數見[測試清單](../test-results/2026-09-30/shipping-review-host-2026-09-30.json)。

## 2026-09-30 後續：刪除舊分支、大數據與 Actions

使用者要求刪除另一支分支，並補大數據與 GitHub Actions。

刪除前 `integration/v2-core` 沒有 `work/m2-cloud-backup` 之外的提交。審查內容改以快轉放上既有的 `work/m2-cloud-backup`，不把暫時分支留成第二條線。遠端非 `main` 只留 `work/m2-cloud-backup`。`main` 沒有合併。

大數據使用既有 `prototypes/expense_preview/tool/large_scale.dart`。它透過 `engineAt` 固定 schema 5，不是目前 App 預設 schema 24。10 組各 5,000 筆新增交易、每筆立刻重送，密碼與救援文字各還原五組。Linux、Flutter 3.47.5／Dart 3.13.4，總時間 332,843 ms（5 分 33 秒），狀態 `passed`：50,000 筆不同交易、50,010 次重送。還原約 3.1–3.3 秒，重新開啟約 0.73–0.79 秒。原始紀錄是[本機大數據](../test-results/2026-09-30/preview-scale-linux-2026-09-30.json)。這仍是單帳本 5,000 筆上限的重複驗證，不是 100k 單帳本。

GitHub Actions 只使用既有的 `V2 integration validation`（四個 Ubuntu job：architecture、domain、storage、flutter-host，timeout 合計上限 68 分鐘）。觸發分支改為留下的 `work/m2-cloud-backup`，不再指向已刪除的分支。舊的 Foundation probe 與 Android foundation workflow 沒有重新打開。

兩次有上限的整合檢查都通過。第一次在已刪除的暫時分支、提交 `b0594ea`：[run 36793180545](https://github.com/swz0103/ExpenseTracker-V2/actions/runs/36793180545)。快轉到 `work/m2-cloud-backup` 的 `58bc5e7` 後，同一 workflow 再跑一次，四個 job 於 2026-10-01 00:25 UTC 全部成功：[run 36794592878](https://github.com/swz0103/ExpenseTracker-V2/actions/runs/36794592878)。這是 Linux 主機整合，不是 Android 實機，也不是停用中的另外兩條 workflow。

## 尚未執行

- Android 實機、OAuth、真實 Fugle／Twelve Data／Google Drive 帳號。
- 單帳本 100k。這次大數據是 10 個各自 5,000 筆的帳本。
- schema 24 的滿容量加密還原。上面的大數據工具仍是 schema 5。
- 通知權限、背景備份與還原的實機流程。
