# M2-01：Provider-neutral 雲端備份核心

此功能線只接受已用帳本密碼及救援文字各自驗證成功的加密 envelope；provider 永遠不取得這兩個憑證。上傳前先取得穩定遠端物件 ID，同一 backup ID 重試必須使用同一物件。若 provider 已提交但回覆遺失，協調器會讀回 metadata 並比對 SHA-256、長度、內容類型與建立時間，不會直接重傳成第二份備份。

下載後先核對 byte length 與 SHA-256，再分別以密碼及救援文字解密，兩條路徑必須得到相同 payload。遠端 metadata 不符、內容損壞、登入失效、權限、quota、限流與暫時不可用有不同錯誤語意。

Google Drive adapter 以獨立 REST boundary 接入 `files.generateIds`、預先保存的 file ID、private `appProperties`、建立／查詢與下載。Drive 的 `409` 或結果不明會回到相同 file ID 讀取核對，不另建第二份。Adapter 保留登入、權限、quota、限流與暫時不可用的不同狀態；OAuth token 仍由未來的 Android transport 及 secure storage 持有。

契約依據：[Drive `files.generateIds`](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/generateIds)、[預產 ID 與 resumable upload](https://developers.google.com/workspace/drive/api/guides/manage-uploads)、[下載 blob](https://developers.google.com/workspace/drive/api/guides/manage-downloads)。

目前完成 provider-neutral 契約、Google Drive adapter 契約、SQLCipher 持久工作接線與合成 provider 測試。加密 envelope 會先寫入 immutable 暫存；Drive 物件保留與佇列工作跨重啟保存，暫存後入列前中斷可 reconciliation，遠端提交後回覆遺失會以同一 file ID 重試。

尚未完成：

- Google Drive HTTPS transport、OAuth、`drive.file` 權限與 secure token storage。
- 歷史清單、保留策略、手動／自動排程及登入失效 UI。
- App 下載後的乾淨還原、實機與最後整合 gate。

這是 M2-01 的離線安全與續傳子項，不代表真實雲端備份已可使用。
