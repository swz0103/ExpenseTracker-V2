# M2-01：Provider-neutral 雲端備份核心

此功能線只接受已用帳本密碼及救援文字各自驗證成功的加密 envelope；provider 永遠不取得這兩個憑證。上傳前先取得穩定遠端物件 ID，同一 backup ID 重試必須使用同一物件。若 provider 已提交但回覆遺失，協調器會讀回 metadata 並比對 SHA-256、長度、內容類型與建立時間，不會直接重傳成第二份備份。

下載後先核對 byte length 與 SHA-256，再分別以密碼及救援文字解密，兩條路徑必須得到相同 payload。遠端 metadata 不符、內容損壞、登入失效、權限、quota、限流與暫時不可用有不同錯誤語意。

Google Drive adapter 以獨立 REST boundary 接入 `files.generateIds`、預先保存的 file ID、private `appProperties`、建立／查詢與下載。Drive 的 `409` 或結果不明會回到相同 file ID 讀取核對，不另建第二份。Adapter 保留登入、權限、quota、限流與暫時不可用的不同狀態；OAuth token 仍由未來的 Android transport 及 secure storage 持有。

Provider registry 可同時註冊多個來源，不硬編碼唯一 provider。支援 catalog 的 provider 可列出歷史；保留策略先產生固定的保留／刪除預覽，至少保留一份並可保護近期備份。只有明確套用後才刪除，且套用前整批重查、Drive adapter 刪除前再核對完整 metadata。Drive `files.delete` 是永久刪除，因此 App UI 必須有明確確認。

App-facing 手動流程以 provider ID 路由到注入的 upload target，不包含 Google Drive 分支。建立備份時仍要求密碼及救援文字雙驗證；下載時先核對遠端 SHA-256、長度與內容類型，之後允許以密碼或救援文字其中一條路徑解鎖，錯誤憑證不混同為傳輸損壞。解鎖後的 envelope 仍須交給既有乾淨還原流程驗證帳本並建立還原前安全副本。

契約依據：[Drive `files.generateIds`](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/generateIds)、[預產 ID 與 resumable upload](https://developers.google.com/workspace/drive/api/guides/manage-uploads)、[下載 blob](https://developers.google.com/workspace/drive/api/guides/manage-downloads)、[歷史清單](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/list)、[永久刪除](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/delete)。

目前完成 provider-neutral 契約、provider registry、手動 App use case、歷史與保留預覽／套用、Google Drive adapter 契約、SQLCipher 持久工作接線與合成 provider 測試。加密 envelope 會先寫入 immutable 暫存；Drive 物件保留與佇列工作跨重啟保存，暫存後入列前中斷可 reconciliation，遠端提交後回覆遺失會以同一 file ID 重試。

尚未完成：

- Google Drive HTTPS transport、OAuth、`drive.file` 權限與 secure token storage。
- Flutter 手動／自動排程、歷史／保留確認及登入失效 UI。
- App 下載後的乾淨還原、實機與最後整合 gate。

這是 M2-01 的離線安全與續傳子項，不代表真實雲端備份已可使用。
