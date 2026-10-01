# Google Drive 正式連線設定

App 現已接好 Google Sign-In、`drive.file` 最小權限、Drive REST transport、加密工作佇列、遠端歷史、續傳式上傳、下載驗證及乾淨還原 handoff。OAuth token 由 Google 平台元件管理，不寫入 Ledger、備份內容或工作佇列；工作佇列自己的 SQLCipher key 存在獨立 Android secure-storage namespace。

## 一次性 Google Cloud 設定

1. 在 Google Cloud 建立或選擇專案，啟用 Google Drive API。
2. 設定 OAuth consent screen；測試期間把實際 Google 帳號加入測試使用者。
3. 為 Android App `dev.expensetracker.preview` 建立 Android OAuth client，登記實際簽章的 SHA-1。
4. 建立 Web application OAuth client，取得 `*.apps.googleusercontent.com` client ID。新版 Android Google Identity 流程把它作為 `serverClientId`。
5. 本機建置時加入：

   ```powershell
   flutter build apk --debug --target-platform android-arm64 --dart-define="GOOGLE_SERVER_CLIENT_ID=你的WebClientId"
   ```

6. GitHub 預發版則在 repository 的 Actions secret 建立 `GOOGLE_SERVER_CLIENT_ID`。Workflow 不會輸出此值；若未設定，App 仍可使用本機加密備份，但不顯示假的 Drive 已連線狀態。

第一次建立雲端備份時，畫面會要求明確連結 Google 帳號並授權 `drive.file`。這項權限只允許 App 存取自己建立或由使用者交給 App 的檔案，不要求整個 Drive 的讀寫權限。真實帳號驗收仍需核對登入、撤權、token 到期、離線、限流、上傳後下載，以及在乾淨安裝中用密碼與救援文字各還原一次。

