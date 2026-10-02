# 系統返回共用安全離頁主機證據（2026-10-02）

## 行為範圍

- root `PopScope` 攔截系統返回；內頁與畫面按鈕共用安全離頁命令。
- dialog／bottom sheet 先由 Navigator 關閉，root 不同時退出。
- 草稿在途寫入會先完成；保存失敗時返回被阻擋，資料與解鎖 session 保留。
- 簡易匯入／匯出返回沿用既有 discard；upgrade 返回只鎖定。
- 解鎖首頁退出前完成 Ledger lock barrier；敏感 popup 同步關閉。

## 驗證

- `safe_back_navigation_widget_test.dart`：3/3 通過；草稿保存後返回、保存失敗阻擋、modal 優先與首頁先鎖後退出。
- `draft_widget_test.dart`：2/2 通過；草稿跨鎖恢復、保存進度／失敗重試。
- `lock_routes_test.dart`：6/6 通過；dialog、queued confirmation、account menu、tag menu、date picker 與 queued date 在背景鎖定時皆關閉並保留草稿。
- 上述組合：11/11 通過。
- architecture_checks：22/22 通過。
- `flutter analyze`（expense_preview）：零問題。
- `git diff --check`：通過。

## 未涵蓋

- Android predictive back、實體返回鍵與各 OEM 的平台生命週期。
- process death、候選 APK/AAB 及正式裝置升級／還原；由 R08 gate 統一驗收。
