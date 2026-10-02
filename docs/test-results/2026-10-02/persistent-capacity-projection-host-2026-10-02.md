# C3b 持久化容量投影主機驗證（2026-10-02）

## 範圍

- `capacity_projection` 與 Ledger authority 位於同一 SQLCipher database；保存 format/schema version、generation identity、rows、conservative bytes、完整 authority table counts 與 SHA-256 checksum。
- projection 是本機可重建 accelerator，不屬於 portable snapshot；密碼／救援還原只還原 authority，首次 session 會重新建立 projection。
- 每個 Ledger 命令用既有 row delta 更新記憶體分表計數，並在同一 SQLite transaction upsert projection；命令、projection 或 commit 任一失敗會一起回滾。
- Generation recovery 以 cipher integrity、storage binding 與精確 table manifest 驗證取代完整 portable snapshot materialization。Ledger session 在交給 App 前核對 projection 與實際 SQL counts；缺表、checksum／schema／count 不一致時走 C3a stable-key 串流 admission，通過後交易式重建。

## 主機結果

- `ledger_generation` 靜態分析：通過。
- C3b 建立／命令失敗回滾／checksum 竄改重建／跨 generation 拒絕／讀取 session 重建／缺表重建／portable snapshot 排除：1/1。
- 代表性 reference session：6/6。
- `storage_generation`：97/97；快速 validate 契約未破壞 install、recovery、process interruption 或 upgrade lifecycle。
- `validated_restore`：148/148。
- authenticated chunked snapshot：4/4。
- 未知 persisted table／column／generated column：3/3 仍 fail closed。
- architecture checks：22/22；repository architecture scan 通過。

既有 validated restore 測試仍輸出 Drift 多實例診斷；本次無新增功能失敗。Android peak RSS、互動 p50/p95 與 20k／50k／100k profile 尚未執行，不以 Windows host 結果代替。

## 發布邊界

現行 5,000 events、50,000 authority rows 與 16 MiB portable payload 上限維持不變。下一步先建立合法 20,000 筆資料集，完成密碼／救援雙憑證乾淨還原、搜尋、報表、備份、還原與 peak RSS profile，再決定是否提高第一級正式上限。
