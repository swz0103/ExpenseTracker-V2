# 資料庫與金鑰生命週期契約

狀態：階段 0 的工程契約草稿；尚未實作，不構成 Architecture Freeze 或安全 gate 通過。

追溯：[工程規格第 7 節](foundation-contracts.md#7-migration-與備份契約)、[RC-14](architecture-baseline-v1.0-rc1.md#rc-14)、[Full Vision Q118](full-vision-baseline.md#q118)、[Q119](full-vision-baseline.md#q119)、[Q120](full-vision-baseline.md#q120)。沿用使用者選定 2A 的密碼與文字救援路徑；QR、完整輪替管理與定期健康檢查仍延後。

## 1. 要解決的具體問題

目前加密原型由呼叫者提供 key，RestoreStore 只切換 DB 檔案；Android 入口只有一個固定 secure storage slot。若正式還原將新 key 覆寫到原 slot，但 DB 尚未切換，程序中止後就可能留下「舊 DB／新 key」。若先換 DB 再存 key，則可能留下「新 DB／舊 key」。兩者均不能只靠 SQLite transaction 解決。

正式接入前，必須把 DB 身份與 key slot 身份一起切換，並保留原組合供復原。這不要求通用 Saga 或工作流引擎，只針對本機儲存生命週期。

## 2. 最小責任邊界

- Security 擁有 `KeySlotStore`：以不透明 slot ID 建立、讀取金鑰；建立後讀回驗證。既有 slot 不覆寫、不因讀取失敗自動清空。金鑰不得離開安全儲存與加密 adapter 的必要邊界。
- Persistence 擁有 `GenerationStore`：保存 DB 世代、非秘密 manifest、切換記錄及目前世代參照；限制路徑於 App 自有目錄，拒絕不認識的必要格式或符號連結。
- App composition 擁有 `StorageCoordinator`：管理唯一可用 DB session，協調排他切換及啟動復原。業務模組只取得 session-bound repository，不選路徑或金鑰。
- Backup 負責可攜 snapshot／envelope 的解鎖與驗證，透過 coordinator 安裝新世代；不直接改目前 DB 或安全儲存。

以上是待實作的 port 名稱，未建立空套件或宣稱 implemented。業務 Domain 不依賴 Flutter secure storage、SQLCipher 或本機檔案 API。

## 3. 身份、內容與不可變條件

每次首次建立或還原產生新的 generation ID 與新的 key slot ID；DB 檔案路徑由 generation ID 導出，不接收備份提供的任意路徑。key slot 內容不放入 JSON manifest、日誌或備份。可攜備份內既有權威資料的 workspace／operation ID 保持原值，本機世代 ID 不是財務身份。

世代 manifest 至少包含格式版本、generation ID、key slot ID、module/schema manifest 及建立來源操作 ID。加密 DB 內亦保存可核對的 generation ID 與格式版本；開檔必須同時核對外部參照、slot 與 DB 內身份。不能只因某個 key 可解密就猜測它是目前帳本。

新增 DB 內本機世代 metadata 時，必須同步版本化 schema 與 snapshot 規格，明確區分本機識別與可攜權威資料；不能直接新增欄位後讓現有 schema 2 驗證器忽略未知內容。

世代切換後，先前世代不再接受業務寫入；新 session 只能綁定目前世代。暫存還原亦不可被報表、搜尋或背景工作當作正式資料。

一個 secure storage 操作與一次檔案操作不視為共同原子提交。API 回傳寫入成功、檔案 flush 或 rename 也不能自行推論已通過裝置斷電耐久性。

## 4. 首次建立與啟動

1. 在 coordinator 排他鎖內確認沒有目前世代、未結切換記錄或其他需恢復的 DB。遇到已有資料卻缺少參照或 key，停止並保留，不建立空帳本遮蔽問題。
2. 建立新 slot，讀回核對後才建立加密 DB。DB 初始化、schema／完整性驗證完成後，才可發布該世代。
3. 首次發布失敗時保留可辨識的未提交世代與 slot；重啟先復原，不將其當成已建立的空白產品帳本。清理策略未驗證前不得自動刪 key。
4. 正常啟動先處理切換記錄，再解析目前參照、讀取指定 key、開檔並核對世代與 schema；全部成功後才對業務公開 session。

未知 metadata、遺失 slot、錯誤 key、損壞 DB、無法取得排他權應分開形成可辨識錯誤；UI 可顯示可理解訊息，診斷不得包含 key、密碼、救援文字或帳務內容。不得降級為明文或將錯誤回報為零餘額。

## 5. 還原切換協定

採「保留原世代、建立新世代、切換單一目前參照」作為下一個限定原型的方案；具體原子替換 adapter 與耐久性仍須實測。

1. 取得儲存生命週期排他權，停止新業務操作與背景 DB 工作，等待既有 session 釋放。超時則中止切換；不能只在 UI 停用按鈕。
2. 正式開啟還原前先處理先前未完成操作。驗證備份、以密碼或救援金鑰解鎖，建立全新的 slot 及加密目標世代。兩種解鎖方式均不需要來源裝置 key。
3. 將權威資料載入新世代，執行相容 migration、財務／完整性／operation receipt 驗證。關閉新 DB，重新讀該 slot 並開檔再核對；保留舊世代與其 slot。
4. 關閉所有相關連線，確認 WAL／journal 等旁檔由 SQLite 正確處理；不能以刪除旁檔代替 checkpoint 或 recovery。
5. 保存版本化切換意圖：restore operation ID、舊／新世代與對應 slot 參照。記錄不含秘密。透過已驗證 adapter 替換唯一目前參照，讓 DB 身份與 key 身份一起改變。首次還原的舊世代允許為空，必須顯式記錄。
6. 目前參照替換為新世代是邏輯 commit point；切換記錄用於判定中止位置，不能把「刪除 journal」另當第二個 commit point。對外成功前，重新讀目前參照與 slot 並開啟新 DB、核對身份。若發布後此檢查失敗，回報需要復原／結果未定並保留兩組，不自動將舊資料恢復為可寫而悄悄丟失後續寫入。
7. 成功後只公開新 session；原世代與 slot 進入保留狀態。清除切換記錄必須可重試，不能因清除失敗再次執行財務匯入。

還原 operation ID 用於識別同一次安裝，不取代備份內的財務 operation receipts。若 commit 後回覆遺失，下次依已發布世代的來源操作 ID 回報結果；同 ID 不同備份指紋拒絕。指紋只用於去重，不替代 envelope 的驗證。

## 6. 中止後如何判斷

- 目前參照仍為舊世代，且與切換記錄一致：新世代尚未發布；驗證舊組合後可恢復舊 session。保留未提交世代與 slot，不誤報還原完成。
- 目前參照已為新世代，且與切換記錄一致：核對新 DB／slot／來源操作；成功後延續已提交結果，清除記錄可重試，不回滾到舊資料。
- 首次建立／還原的參照仍不存在：沒有正式世代；保留待處理資料，不自動將隨機暫存檔提升為正式帳本。
- 目前參照、切換記錄、世代 manifest、DB 內身份相互衝突或無法解析：停止業務寫入並保留全部檔案與 slot；不以修改時間或最大 UUID 猜測正式版本。
- 遺失或無法解鎖任一必要 key：不得覆寫 slot；舊可用世代只能依已確定的未提交狀態恢復。已提交但新組合損壞時需明確復原流程，不能默默倒退帳務。

單一參照的原子替換與排他機制必須在目標平台驗證。對惡意替換整套舊備份／舊 metadata 的防回滾能力尚未成立；不能將內部身份核對誤稱為具備外部可信計數器的防回滾保證。

## 7. 保留、清理與範圍

第一個生命週期原型不刪除舊 slot／世代。正式清理需同時證明：它不被目前參照或未結記錄引用、沒有開啟 session、至少新世代重開驗證成功、且符合已定保留政策。清理失敗只留下待清理狀態，不影響已提交帳務；磁碟不足不能藉自動刪除最後可恢復組合解決。

尚需後續確定保留數量／大小與 UI 入口，未定前不宣稱可供長期日常使用。完整輪替、定期健康檢查、跨裝置同步 key、QR 與通用多租戶 key 管理仍不在這次實作範圍。

## 8. 必須執行的驗收

以下編號補充 [BACKUP-01～04 與 DATA-01](foundation-acceptance.md#資料演進與保護)，全部仍待實作與執行。

- **KEY-01 初始化**：slot 寫入前／後、讀回失敗、DB 初始化中止；不得發布無 key 的 DB，重試不覆寫既有 slot。
- **KEY-02 缺失與損壞**：已有 DB 卻遺失 key、slot 格式未知、key 不符、metadata 被截斷；均拒絕正常業務寫入且保留證據。
- **KEY-03 切換中止**：每個持久化邊界使用獨立程序中止；重啟後要麼可用完整舊組合，要麼可用已提交新組合。從不混配 key／DB，且結果由 commit point 決定。
- **KEY-04 回覆遺失**：發布後退出，再以相同還原 operation ID 重試；只回報一次安裝結果，財務 receipt 保持可重放。
- **KEY-05 並行與關閉**：一般寫入／背景工作／第二次還原競爭；切換期間不產生對已退役世代的寫入，未釋放 handle 時拒絕切換。
- **KEY-06 容量與平台錯誤**：key 寫入、DB staging、意圖保存及參照替換分別失敗；保留可恢復組合，發布結果未定時不回報明確成功或可安全重做。
- **KEY-07 乾淨 Android 還原**：不同乾淨目標僅持有備份及其中一種解鎖憑證，使用新平台 slot；關閉 App／重啟後核對全部權威資料、餘額與 receipts。
- **KEY-08 保留與誤清理**：目前、未結、仍開啟及唯一可恢復組合都不可清除；清理中止不能讓已提交世代失去 key。

host 故障注入、Android 程序中止與實際儲存／斷電情境分別記錄，不能互相冒充。原型及最終 adapter 各自提供證據後，才可將對應 capability 標為 verified。
