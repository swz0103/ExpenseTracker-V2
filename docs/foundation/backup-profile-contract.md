# 救援憑證沿用與 BackupProfile 契約

> 這是舊版 App（`prototypes/`，已於 2026-10-03 移除）時期的規格，留作行為對照。新架構以 [ADR-0001](../adr/0001-target-architecture.md) 與 [STATUS.md](../STATUS.md) 為準。

對應[資料演進契約](data-evolution-contract.md#5-升級前安全備份)、[RC-14](../architecture/architecture-baseline-v1.0-rc1.md#rc-14)、[RC-15](../architecture/architecture-baseline-v1.0-rc1.md#rc-15)與使用者選定的密碼／文字救援 2A。這次只完成明確沿用救援憑證的封裝與 Ledger 入口；正式設定檔保存、啟用流程、背景備份與完整輪替仍未實作。

## 已實作的最小能力

`EnvelopeCodec.create`、`LedgerStore.backup` 及 `createSafetyBackup` 新增可選的 `recoveryKey`。不提供時維持原行為，每次生成新救援 key；提供時嚴格驗證原有前綴、長度、canonical encoding 與 checksum，然後沿用指定 key。錯誤憑證拒絕，不生成替代值，也不默默回到每份新 key。

每份備份仍生成新的 256-bit 資料金鑰、Argon2id salt 與三個 AES-GCM nonce。救援 key 只用來包裝本份新資料 key，不能直接當 DB key 或共用資料 key。沿用既有 envelope version 1／ETV2-R1 格式與 AAD 契約；讀取端仍只需要該備份及任一正確解鎖憑證，不需要本機 profile。

沿用的 key 不寫進 envelope 或診斷。Checksum 只辨識格式與誤輸入，不證明這是正確帳本的救援憑證；上層必須明確選用已確認的設定，不從舊檔案、最近輸入或全域可變值猜測。

密碼參數仍必填。使用新密碼建立後續備份不會重寫舊備份；舊檔仍使用其原密碼，沿用的救援 key 可解鎖兩者。指定新救援 key 也不會撤銷已存在備份的舊 key；完整輪替與重新包裝屬另一期實作，不能把設定改字串當成歷史憑證失效。

## 正式 BackupProfile 的接入邊界

1. Backup 擁有不含秘密的 profile 身份、版本與備份範圍，Security 擁有不透明 credential slot。當期範圍先以完整帳務資料庫為單位，不先建立未使用的任意多 profile 管理。
2. 首次設定使用隨機產生的救援憑證，不提供使用者自訂低熵 key 的入口。呈現救援文字、確認保存與解鎖驗證後才能把 profile 標記可用；介面隱藏不能取代已完成設定。
3. 重新帶入已保存憑證時，須核對目標 profile／備份範圍，並以已知備份或正式驗證材料確認；僅通過 checksum 不夠。Profile 格式與驗證材料應另有明確版本，不向現有 envelope 加入未經 reader 支援的欄位。
4. 持久化 slot 前後失敗要保留既有可用設定；只有新值讀回、必要驗證及 profile 參照一起形成確定結果後才能啟用。不能覆寫唯一舊憑證後再做驗證。這個設定切換協定仍待實作，不與 DB generation 發布視為共同原子提交。
5. 已有 profile 卻缺失／損壞 slot 時，停止需要該憑證的備份或升級，保留來源帳務及舊備份。不得自動生成新 key 讓使用者保存的文字失效；一般讀帳可否繼續依 DB 狀態另行判斷，不回報零餘額。
6. Profile 中不保存明文密碼、救援文字或來源 DB key。秘密只經 Security adapter 的必要範圍傳遞；診斷不得序列化整個回傳物件。Dart managed memory 不保證所有敏感副本可安全抹除。

目前格式在建立每份 password slot 時仍需要密碼。這次能力不提供無互動的自動備份，也不以把明文密碼放進設定檔來補齊。首個接入流程先要求使用者解鎖後執行備份／升級；背景備份若需新的 profile wrapping 機制，必須另做格式、還原與 key 生命週期驗證，未通過前維持未開放。

## 驗證與剩餘項目

新增七項 envelope 案例：輸入在非同步驗證前固定、舊救援文字解鎖新舊備份、密碼變更的範圍、實際解開 wrapped key 後核對新資料 key／salt／nonce、無效已保存憑證拒絕、同 key 跨備份移植 recoveryBox 被 AAD 擋下，以及新程序各以單一憑證還原。

Ledger 新增兩項整合案例，驗證一般與持久安全備份入口沿用指定 key，及錯誤憑證不生成檔案、不改來源。Envelope 原有九項測試與 Ledger 原有四十六項回歸保留。此項為 host 證據；先前 Android 乾淨還原使用原有預設模式，不冒充已驗證穩定 profile 的平台保存。

後續須補 profile 設定中止、slot 缺失／損壞、跨備份範圍誤配、使用者保存確認、舊版本相容與乾淨 Android 還原。尚未建立的 profile port 不標為 implemented；已完成的只有這裡明列的底層憑證沿用能力。
