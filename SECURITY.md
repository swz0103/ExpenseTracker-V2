# 安全政策

「記帳本」處理的是個人財務資料，發現安全問題請私下回報，不要開公開的 issue。

## 怎麼回報

到本儲存庫的 Security 分頁，按「Report a vulnerability」（GitHub 私人弱點回報）。請寫：

- 哪個版本（「設定 › 關於」顯示的版本與建置編號）
- 怎麼重現、會造成什麼後果（例如帳本內容外洩、備份被讀出、更新檔被替換）
- 手邊有的紀錄或截圖（請先把真實的金額與名稱遮掉）

維護者是 `@swz0103`，一個人維護，盡量在一週內回覆；確認後修好、發新版，再公開說明並致謝（不想具名請先說）。

## 範圍

- 在範圍內：App 本身（帳本加密、解鎖、備份與還原、更新檔的下載與安裝）、發行流程（簽章金鑰、GitHub Releases 上的檔案）。
- 不在範圍內：已被取得 root 的手機；使用者自己選擇存放備份的地方的安全。

## 支援的版本

只有 GitHub Releases 上最新的版本會收到修正；App 內「設定 › 關於」會通知並更新。

## 驗證下載的 APK

GitHub Releases 上的每個 APK 都附有建置來源證明（GitHub attestation），可用 `gh attestation verify ExpenseTracker.apk --repo swz0103/ExpenseTracker-V2` 確認它是由本儲存庫的發行流程建置與簽章。
