# Google Drive 雲端備份設定

> 現況（2026-10-19）：
> - 已完成並測試：上傳、續傳、保留份數、排程、還原的底層（`infrastructure/vault` 的 `drive_backup`、`backup_service`）。
> - 尚未完成：App 的 Google 登入，所以目前還不能連 Drive。在那之前，換手機靠 Android 自動備份，或手動匯出備份檔（可在系統存檔畫面選 Google 雲端硬碟）。

## 權限

只申請 `drive.file`：App 只能存取自己建立的檔案，看不到使用者 Drive 裡的其他東西。token 由 Google 平台元件管理，App 不儲存 token。

## 一次性 Google Cloud 設定（接 Google 登入時）

1. 在 Google Cloud 建立或選擇專案，啟用 Google Drive API。
2. 設定 OAuth 同意畫面；測試期間把實際使用的 Google 帳號加入測試使用者。
3. 為新 App 的 Android application ID 建立 Android OAuth client，登記正式簽章的 SHA-1。application ID 是 `io.github.swz0103.expensetracker`（見 [Android 建置](android.md)）。
4. 建立 Web application OAuth client，取得 `*.apps.googleusercontent.com` client ID，作為 Android Google Identity 流程的 `serverClientId`。
5. 把 client ID 存成 GitHub Actions secret `GOOGLE_SERVER_CLIENT_ID`，建置時用 `--dart-define` 帶入；workflow 不會輸出這個值。

## 真機驗收（接上後）

登入、撤銷授權、token 過期、離線、限流、大檔續傳、上傳後下載核對，以及在乾淨安裝中用密碼與救援碼各還原一次。
