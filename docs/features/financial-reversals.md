# 正式撤銷交易

範圍：M1-04、[FV-008](../architecture/full-vision-baseline.md#fv-008)、[RC-03](../architecture/architecture-baseline-v1.0-rc1.md#rc-03) 與 [Foundation 契約](../foundation/foundation-contracts.md)。本批提供收入、支出、同幣／跨幣轉帳的完整反向入帳；一般欄位編輯、原子更正與替代、tombstone、信用卡跨期沖回仍依 [實作安排](../delivery/implementation-plan.md) 接續，未宣稱整個 M1-04 完成。

## 財務語意

- 原交易與全部原 legs 保留；新增唯一的 reversal 事件及來源關聯。各 leg、報表收入／支出逐一精確取負，轉帳來源手續費一起退回。
- 餘額重建同時包含原交易及反向事件；不再把原交易排除一次。分類 Allocation 保留正數原金額，分析時依 reversal 語意沖回。
- 跨幣保留原兩幣實際本金與換算 context，反向事件逐幣抵銷，沒有新匯率或重新捨入。
- 完整沿用原分類、Tag、Merchant 的 ID、版本及歷史 sequence；即使現在封存或合併，也不改寫原歸屬。參與帳戶仍須通過當前 lifecycle、日期、版本與 Money 範圍驗證。
- 只允許 income、expense、transfer；日期不可早於原交易，原因可空白，正規化後最多 256 個 Unicode 字元。期初、退款、撤銷事件本身不開放撤銷。
- 同一原交易最多一筆完整撤銷。已有退款的支出拒絕撤銷，已撤銷支出拒絕新增退款；此批不推測後續依賴的級聯處理規則。
- 所有來源／依賴檢查、反向事件、歸屬、操作收據與 audit 都在同一 ACID transaction 中。相同 operation 先比對收據再重播，已成功的重試不被後來的來源狀態阻擋。

## 邊界、保存與還原

Ledger 提供不可變的 Posting.reversal；Persistence 重新比對既存來源的完整財務事實與歸屬，不能用偽造的 original 物件入帳。Session 只公開受控來源查詢與既有 post 邊界。

schema 11／snapshot 10 新增 event_reversals（workspace、event_id、original_id、reason），以複合外鍵和每個來源唯一限制保存關聯。新增 ledger_reversals reader 能力，舊 reader 不能靜默讀寫新格式。receipt 的 reversal-posting-v1 綁定來源、原因、反向本金／歸屬、FX context。

還原除了原有帳戶、Money、分類、Tag、Merchant 與收據檢查，另外逐項比對原／反向金流、報表、各歸屬與原 FX；拒絕遺失、重複或錯誤來源、依賴退款、篡改原因和收據。檢查沿用有界整批讀取，避免對每一筆反向事件重新掃描整段歷史。

10 → 11 使用既有安全升級流程：先寫入並以密碼、救援文字驗證安全備份，再發布新 generation；保留原資料庫及其 key。這是 V2 格式升級，沒有匯入舊 App 資料。

## 使用流程

從收入、支出或轉帳的「撤銷交易」入口開始，畫面列出各帳戶反向金額及原手續費，只能填日期與原因；送出前明確確認。原交易顯示已撤銷，新紀錄列出反向金額、原因；[活動查閱](transaction-activity.md)將兩者組成同一家族。

manual-reversal-v1 加密保存未完成的日期／原因；凍結時保存原財務命令、原歸屬及帳戶版本。送出中斷可核對既有收據恢復；需要修正前先證明尚未入帳，再回到編輯。沿用密碼／救援備份的草稿阻擋與背景鎖定機制，鎖定後關閉確認視窗並清除畫面內容。

## 驗證狀態

[完整 18 套件／846 個主機案例](../test-results/2026-09-28/reversals-host-2026-09-28.json)通過，新增 31 個案例；針對測試不重複計數。涵蓋所有寫入階段回滾、三個轉帳 legs、FX context、Max Money、封存歸屬、競爭請求、篡改還原、草稿凍結與重試、確認途中鎖定，以及 11 個升級真實程序退出點。

[5,000 混合事件](../test-results/2026-09-28/reversals-scale-2026-09-28.json)包含既有部分退款、2,498 組原交易／撤銷、1,249 組跨幣轉帳與費用、4,996 次重送。獨立核對兩幣餘額、報表、有符號分類淨額、容量拒絕與全部分頁；刪除來源 DB／keys 後，密碼及救援文字各自乾淨還原且完整 bytes 一致。另有[4 個草稿真實程序退出點](../test-results/2026-09-28/reversals-process-2026-09-28.json)。

畫面測試曾誤等忙碌動畫結束，及未推進模擬時鐘的加密工作；修正測試等待方式，保留財務與隱私斷言。完整驗證分兩段固定來源：先完成 14 個未受影響套件；回查修正撤銷收據容量後，重新驗證 4 個上層套件。兩版各 282 個程式／相依檔案雜湊、兩檔差異及未計入的中斷測試明列證據。0.15.0+19 本機 ARM64 debug 封裝核對通過。雲端 workflow 停用，實機未執行，沒有合入 main 或正式發版。
