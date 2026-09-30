# M2-01：Provider-neutral 雲端備份核心

此功能線只接受已用帳本密碼及救援文字各自驗證成功的加密 envelope；provider 永遠不取得這兩個憑證。上傳前先取得穩定遠端物件 ID，同一 backup ID 重試必須使用同一物件。若 provider 已提交但回覆遺失，協調器會讀回 metadata 並比對 SHA-256、長度、內容類型與建立時間，不會直接重傳成第二份備份。

下載後先核對 byte length 與 SHA-256，再分別以密碼及救援文字解密，兩條路徑必須得到相同 payload。遠端 metadata 不符、內容損壞、登入失效、權限、quota、限流與暫時不可用有不同錯誤語意。

目前完成 provider-neutral 契約與合成 provider 測試；尚未完成：

- 加密持久工作佇列與 immutable envelope 暫存的接線。
- Google Drive `drive.file` adapter、OAuth 與 secure token storage。
- 歷史清單、保留策略、手動／自動排程及登入失效 UI。
- App 下載後的乾淨還原、實機與最後整合 gate。

這是 M2-01 的第一個垂直子項，不代表真實雲端備份已可使用。

