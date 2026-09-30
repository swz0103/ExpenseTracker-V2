# M2-01：Provider-neutral 雲端備份核心

此功能線只接受已用帳本密碼及救援文字各自驗證成功的加密 envelope；provider 永遠不取得這兩個憑證。上傳前先取得穩定遠端物件 ID，同一 backup ID 重試必須使用同一物件。若 provider 已提交但回覆遺失，協調器會讀回 metadata 並比對 SHA-256、長度、內容類型與建立時間，不會直接重傳成第二份備份。

下載後先核對 byte length 與 SHA-256，再分別以密碼及救援文字解密，兩條路徑必須得到相同 payload。遠端 metadata 不符、內容損壞、登入失效、權限、quota、限流與暫時不可用有不同錯誤語意。

Google Drive adapter 以獨立 REST boundary 接入 `files.generateIds`、預先保存的 file ID、private `appProperties`、建立／查詢與下載。Drive 的 `409` 或結果不明會回到相同 file ID 讀取核對，不另建第二份。Adapter 保留登入、權限、quota、限流與暫時不可用的不同狀態；OAuth token 仍由未來的 Android transport 及 secure storage 持有。

Google Drive REST transport 已實作 bearer token 注入、resumable upload、分頁 `files.list`、metadata、下載及刪除。Upload session URL 只接受 HTTPS Google APIs 主機；不跟隨重新導向，token 換行注入、過大回應、重複 page token 與超過 10,000 筆的異常清單均拒絕。上傳 bytes 後遺失回覆或收到可能已提交的 308／408／5xx 會回報結果不明，交由既有同 file ID inspect 流程收斂。

持久工作 schema 2 只保存可公開分類的最後失敗原因。登入、權限、quota 與完整性錯誤不自動重試；使用者處理後可用同一 backup ID 手動續跑。限流、暫時不可用、結果不明與暫時本機錯誤使用原有退避。schema 1 工作可無損升級，token 與 provider 回應內容不寫入資料庫。

自動排程設定保存在獨立 SQLCipher store，預設關閉。到期 occurrence 的 backup ID 由 provider 與到期時間穩定導出；暫存／入列後中斷不會重新加密成衝突內容。離線錯過多期只合併一份，未解決的 staged 工作會阻擋同 provider 繼續堆疊。獨立 Flutter 畫面提供每日、每週與每 30 天選項，啟用後從下一週期開始。

Provider registry 可同時註冊多個來源，不硬編碼唯一 provider。支援 catalog 的 provider 可列出歷史；保留策略先產生固定的保留／刪除預覽，至少保留一份並可保護近期備份。只有明確套用後才刪除，且套用前整批重查、Drive adapter 刪除前再核對完整 metadata。Drive `files.delete` 是永久刪除，因此 App UI 必須有明確確認。

App-facing 手動流程以 provider ID 路由到注入的 upload target，不包含 Google Drive 分支。建立備份時仍要求密碼及救援文字雙驗證；下載時先核對遠端 SHA-256、長度與內容類型，之後允許以密碼或救援文字其中一條路徑解鎖，錯誤憑證不混同為傳輸損壞。解鎖後的 envelope 仍須交給既有乾淨還原流程驗證帳本並建立還原前安全副本。

`expense_preview` 的主導航已有雲端備份入口。未注入 gateway 時只說明尚未連結雲端帳號，本機加密備份仍可用。注入 gateway 後，畫面涵蓋 provider 選擇、立即備份、歷史、下載還原、保留策略二次確認、自動備份週期與重新連結。Engine handoff 可由 `EngineCloudBackupBridge` 建立已雙重驗證的 artifact，並把解封結果交給既有乾淨還原。預設 `main()` 沒有注入 gateway。

契約依據：[Drive `files.generateIds`](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/generateIds)、[預產 ID 與 resumable upload](https://developers.google.com/workspace/drive/api/guides/manage-uploads)、[下載 blob](https://developers.google.com/workspace/drive/api/guides/manage-downloads)、[歷史清單](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/list)、[永久刪除](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/delete)。

目前完成 provider-neutral 契約、provider registry、手動 App use case、歷史與保留預覽／套用、Google Drive adapter 與 HTTPS 契約、SQLCipher 持久工作接線與合成 provider 測試。加密 envelope 會先寫入 immutable 暫存；Drive 物件保留與佇列工作跨重啟保存，暫存後入列前中斷可 reconciliation，遠端提交後回覆遺失會以同一 file ID 重試。

尚未完成：

- Google OAuth client、`drive.file` 帳號授權、撤權與 secure token storage。
- App 生命週期呼叫 `CloudBackupJobRunner.runNext` 與 `CloudBackupAutomaticScheduler.tick`。目前「立即備份」只會暫存並入列，「自動加密備份」只寫入排程；兩者都不會自己上傳。
- 重新連結只執行注入的帳號 callback，並未呼叫 `retryAfterUserAction`。登入、權限或 quota 造成的終止上傳不會因重新連結而恢復。
- 上傳失敗、待處理與重試耗盡沒有畫面狀態。
- 實機與最後整合 gate。

這是 M2-01 的離線安全與續傳子項，不代表真實雲端備份已可使用。
