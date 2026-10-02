# 自動備份 application runner 主機證據（2026-10-02）

## 行為範圍

- 冷啟動且帳本鎖定：只續傳已經雙憑證驗證、加密並持久化的 artifact。
- 成功解鎖：檢查到期 schedule，建立新快照，再執行 bounded upload pump。
- 不要求使用者進入雲端備份頁；冷啟動與解鎖維護序列化。
- provider 失敗彼此隔離；失敗狀態持久化並在備份頁呈現。

## 時間與持久格式

- `scheduledFor`：原定排程時間，決定穩定自動 backup ID。
- `capturedAt`：實際建立快照時間，不再冒充原定時間。
- `updatedAt`：工作最後狀態變更；uploaded 記錄用於最後成功上傳時間。
- `nextDueAt`：排程庫的下次到期；畫面可判斷逾期。
- work store schema 3；schema 1 會先補失敗欄位，再補 scheduled time，不遺失 staged work。

## 驗證

- cloud_backup 完整套件：41/41 通過。
- App runner、備份畫面、首頁冷啟動／解鎖接線、engine 備份整合：12/12 通過。
- architecture_checks：22/22 通過。
- cloud_backup 與 expense_preview 靜態分析：零問題。
- `git diff --check`：通過。

SQLCipher 測試中的錯誤 key HMAC 訊息來自刻意驗證錯誤金鑰會被拒絕；對應測試通過。

## 未涵蓋

- Android OS 在 App 關閉時喚醒並建立新快照。
- 真實 Google 帳號、OAuth client、帳號切換 principal 與實機網路／省電策略。
- 正式候選 APK/AAB 的 process death、重開續傳與雙裝置演練。
