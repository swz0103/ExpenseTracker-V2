# 雲端備份穩定帳號綁定主機證據（2026-10-02）

## 行為範圍

- 工作 schema 4 保存 provider 與穩定 principal；Google Drive principal 來自 Google Sign-In account ID，OAuth token 不落地。
- 建立、續傳與人工重試都核對目前 principal；同帳號重新授權可續跑。
- 不同帳號在 artifact 讀取與任何 provider 上傳前終止，留下原工作及可見 authentication-required 狀態。
- schema 1–3 舊工作升級後 principal 為未綁定，不會由下一個登入帳號自動接管。

## 驗證

- cloud_backup 完整套件：43/43 通過。
- 新增案例：不同 principal 零次 provider create、不能重試；切回原 principal 後沿用同工作上傳一次。
- 新增案例：schema 3 staged work 升級後仍未綁定，重新協調只會安全終止，零次 provider create。
- expense_preview 雲端 application runner、畫面與正式入口：11/11 通過。
- cloud_backup 與 expense_preview 靜態分析：零問題。
- architecture_checks：22/22；repository architecture scan 通過。
- `git diff --check`：通過。

SQLCipher 以錯誤 key 開啟時輸出的 HMAC 訊息是測試刻意驗證拒絕錯誤金鑰；43 項 assertion 全數通過。

## 未涵蓋

- 真實 Google OAuth client、撤權、同帳號重授權及 A→B→A 帳號切換實機測試。
- 跨帳號搬移不是自動行為；尚未提供明確確認、清除舊 reservation 與重建目的地的 UI。
- Android process death、背景工作與正式候選 APK/AAB 仍列 R08 gate。
