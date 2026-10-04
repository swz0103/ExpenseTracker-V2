# Google Drive 雲端備份設定

> 現況（2026-10-04）：
> - 已完成並測試：上傳、續傳、保留份數、排程、還原的底層（`infrastructure/drive_backup`、`backup_service`）。
> - 尚未完成：Google 登入，要等 Android 平台接線（STATUS 4b-2）才接上，所以目前的 App 還不能連 Drive。

## 權限

只申請 `drive.file`：App 只能存取自己建立的檔案，看不到使用者 Drive 裡的其他東西。token 由 Google 平台元件管理，App 不儲存 token。

## 一次性 Google Cloud 設定（4b-2 時進行）

1. 在 Google Cloud 建立或選擇專案，啟用 Google Drive API。
2. 設定 OAuth 同意畫面；測試期間把實際使用的 Google 帳號加入測試使用者。
3. 為新 App 的 Android application ID 建立 Android OAuth client，登記正式簽章的 SHA-1。application ID 在 4b-2 定案後補在這裡。
4. 建立 Web application OAuth client，取得 `*.apps.googleusercontent.com` client ID，作為 Android Google Identity 流程的 `serverClientId`。
5. 把 client ID 存成 GitHub Actions secret `GOOGLE_SERVER_CLIENT_ID`，建置時用 `--dart-define` 帶入；workflow 不會輸出這個值。

## 真機驗收（接上後）

登入、撤銷授權、token 過期、離線、限流、大檔續傳、上傳後下載核對，以及在乾淨安裝中用密碼與救援碼各還原一次。
