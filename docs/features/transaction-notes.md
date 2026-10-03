# 交易純文字備註與修訂

本批屬於 M1-04，接續 [正式撤銷](financial-reversals.md)。追溯 [Full Vision Q015](../architecture/full-vision-baseline.md#q015)、[Q151](../architecture/full-vision-baseline.md#q151)；金額更正／替代、tombstone 與完整 M1 gate 仍延後。

## 行為與邊界

- 每筆已保存交易（含期初、退款、撤銷）可編輯純文字備註。最多 1,024 個 Unicode scalar，保留空白與換行；拒絕 NUL、孤立 surrogate。沒有 Markdown 或系統日誌混入文字。
- 修改備註不新增金融事件，也不改 legs、餘額、費用、分類或匯率。原本交易與退款／撤銷限制完整保留。
- 無備註歷史為 revision 0；每次有效修改 append 一筆。清空非空文字也是一個修訂；相同內容拒絕。每個命令攜帶預期 revision，落後版本不能靜默覆蓋。
- 所有修訂與 operation receipt、audit 同一個 ACID transaction。相同 operation／相同內容重試只回傳原結果；operation 已使用但內容不同即衝突。
- 使用既有單一加密草稿槽，格式 manual-note-v1。與金融草稿互斥；備份／還原／升級前仍須處理草稿。prepared 先保存再送出，receipt 精確重播證明成功才清除中斷後草稿，不能因來源交易本來存在而誤認已完成備註。
- 版本衝突後可查看活動，明確選擇「讀取最新版本並保留草稿」，再確認儲存；不自動合併或覆寫。
- 交易列表最多顯示兩行備註；完整內容在編輯與活動。隱藏金額模式同時遮蔽列表／活動備註，避免文字中金額外漏。鎖定清空編輯畫面，保留加密草稿。
- 活動沿用交易家族（原始／退款／撤銷），另列備註修訂時間與文字。UTC 微秒正規排序，同時間用唯一活動鍵續頁，金融事件既有相同時間 ID 順序不變。
- 此批保持 bounded session：5,000 筆事件、5,000 次備註修訂，以及既有總列數／16 MiB 可攜備份上限。達上限拒絕新增，已提交 operation 仍能重播；不刪歷史騰空間。

## 保存、還原與升級

schema 12／snapshot 11 新增 event_note_revisions 與 ledger_notes manifest。修訂主鍵為 workspace＋event＋revision；operation 在 workspace 內唯一。最新文字由索引讀取，不另建可漂移 projection。

還原重播每筆 note-v1 receipt，檢查連續 revision、內容上限、非空變更、事件／workspace、receipt result、audit entity/kind 及雙向無遺漏；未知新格式由舊 reader 拒絕。舊 V2 snapshot 升級只補空備註表，不讀舊 App 的資料。

11→12 走既有 staged generation：先保存並以密碼／救援文字各自驗證安全備份，再切換；保留舊 DB／key。失敗與中斷遵循原有 catalog 保護及重試規則。

回查修正原始金融 receipt 的查詢：以精確 ledger.kind 配對，避免 ledger.note 被當成原始入帳。還原的金融 receipt 數量檢查也分離備註，再由完整備註驗證器接管。

## 本批驗證

完整 18 套件／869 案例、11 處真實升級程序退出通過；另完成 4 處草稿程序退出，以及 5,000 事件＋5,000 修訂／9,999 重播、上限拒絕與來源 DB／keys 刪除後密碼及救援各自乾淨還原。固定來源與結果見主機、程序退出、大量資料。雲端 workflows 保持停用；實機與 main 合併仍另行等待，不宣稱所有 CORE 完成。
