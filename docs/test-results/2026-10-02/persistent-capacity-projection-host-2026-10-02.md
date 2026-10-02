# C3b 持久化容量投影主機驗證（2026-10-02）

## 範圍

- `capacity_projection` 與 Ledger authority 位於同一 SQLCipher database；保存 format/schema version、generation identity、rows、conservative bytes、完整 authority table counts 與 SHA-256 checksum。
- projection 是本機可重建 accelerator，不屬於 portable snapshot；密碼／救援還原只還原 authority，首次 session 會重新建立 projection。
- 每個 Ledger 命令用既有 row delta 在原 SQLite transaction 更新 session 內的精確分表計數；正常關閉 session 時以另一個 transaction 一次保存 projection，避免每筆命令重寫 accelerator。若程序在保存前中止，下一次開啟會用實際 authority counts 拒絕落後 projection 並完整重建。
- Generation recovery 以 cipher integrity、storage binding 與精確 table manifest 驗證取代完整 portable snapshot materialization。Ledger session 在交給 App 前以單次聚合 SQL 核對 projection 與所有實際 table counts；缺表、checksum／schema／count 不一致時走 C3a stable-key 串流 admission，通過後交易式重建。

## 主機結果

- `ledger_generation` 靜態分析：通過。
- C3b 建立／命令失敗回滾／checksum 竄改重建／跨 generation 拒絕／讀取 session 重建／缺表重建／portable snapshot 排除：1/1。
- 代表性 reference session：6/6。
- `storage_generation`：97/97；快速 validate 契約未破壞 install、recovery、process interruption 或 upgrade lifecycle。
- `validated_restore`：148/148。
- authenticated chunked snapshot：4/4。
- 未知 persisted table／column／generated column：3/3 仍 fail closed。
- architecture checks：22/22；repository architecture scan 通過。
- 超過 preview row-byte 上限但結構與語意仍合法的匯入資料，維持可讀、可匯出及可分辨 replay／conflict；新 mutation 才回報 `PreviewCapacity`。針對案例 1/1 與 `ledger_store` 34/34 通過。
- projection 只在 authority row count／encoded byte 使用量實際改變時於 session 關閉階段保存一次；純 replay／conflict 不做無效 upsert。同一 session 亦快取不變的 generation identity。
- checksum 合法但 counts 落後一筆的 projection 會被實際 authority counts 拒絕並重建；投影重建／回滾／落後模擬案例 1/1 通過。
- 5,000 events + 1,024 category changes 的完整升級、雙憑證還原與容量邊界案例 1/1 通過；最終 Windows host 實測 writes 257,239 ms、upgrade 42,475 ms、total 522,547 ms。功能正確但仍慢於 2026-09-27 的 257,902 ms 基準，因此效能回歸尚未關閉。
- GitHub Actions `aff71bd` 的 domain、architecture、flutter-host 通過；storage 唯一失敗即上述超限唯讀相容案例，已由本批本機回歸修復，等待新 exact-head CI 驗證。

既有 validated restore 測試仍輸出 Drift 多實例診斷；Android peak RSS、互動 p50/p95 與 20k／50k／100k profile 尚未執行，不以 Windows host 結果代替。Windows 端其餘 session 開啟、SQLCipher 寫入及完整備份／還原成本仍需分段 profile，不能以目前功能通過宣稱效能完成。

## 發布邊界

現行 5,000 events、50,000 authority rows 與 16 MiB portable payload 上限維持不變。下一步先建立合法 20,000 筆資料集，完成密碼／救援雙憑證乾淨還原、搜尋、報表、備份、還原與 peak RSS profile，再決定是否提高第一級正式上限。
