# Flutter CI 快取回查

2026-09-27，依每個步驟回查既有實作的要求，檢查 [#33 Flutter run 36294624583](https://github.com/swz0103/ExpenseTracker-V2/actions/runs/36294624583)。兩個 App 的 matrix 工作使用相同 Flutter SDK 與 pub cache key，同時冷啟動並嘗試保存。

- expense_preview：pub cache 於 04:37:08 UTC 保存，SDK 於 04:38:58 保存。
- android_foundation：pub cache 於 04:37:30、SDK 於 04:40:10 回報 `Unable to reserve cache`，因另一工作已在建立相同快取。

測試並未因此失敗，但第二份壓縮／保存是重複工作；不能把這段時間當成財務或 UI 測試變慢。

## 最小修正

保留兩個獨立 App 工作與所有格式／分析／測試步驟，只由 expense_preview 啟用 action 的 SDK／pub cache。已讀取目前鎖定 `subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2` 的 action.yaml，確認 `cache` 同時控制 SDK 及預設 pub cache。

代價是 android_foundation 工作每次自行建立 Flutter 環境，不讀取既有 action cache；冷啟動的原始兩工作本來都要建立環境。這是避免重複保存的保守改動，不新增跨 PR 權限、共用可寫工作目錄或不安全的快取跨範圍捷徑。未改 Flutter／Dart 版本、lockfile 或測試內容，也不以略過測試節省時間。

## 驗證

由本修正 PR 的完整 CI 驗證兩個 App 均執行原有測試，且只剩一個工作保存相同快取。冷熱快取與 runner 負載不同，不承諾每次固定縮短幾分鐘；沒有穩定多次量測前不宣稱效能提升比例。
