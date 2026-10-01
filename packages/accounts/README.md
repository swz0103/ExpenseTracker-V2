# Accounts — 日常帳戶 Domain

依據 [RC-05](../../docs/architecture/architecture-baseline-v1.0-rc1.md#rc-05) 與 [Q054](../../docs/architecture/full-vision-baseline.md#q054)。目前僅 cash／bank；信用卡與投資專用能力另批完成，不先放通用入口。

此套件只依賴 foundation_values，擁有帳戶身份、幣別、開戶日期、名稱、淨資產納入設定、生命週期與版本。沒有 currentBalance 欄位，餘額由 Ledger 提供。

已完成的 Domain 操作：開立、改名、變更淨資產納入、封存、關閉與重新啟用。封存保留歷史且停止一般入帳，須重新啟用才能繼續。關閉要求同帳戶同幣別的零餘額、無未結事項與合法日期；successor 必須為同帳本且有效的其他帳戶。successor 關聯本身不移轉資金，剩餘餘額必須先經真正 Ledger 轉帳清理。

Application 必須在同一 write transaction 讀取 Account、餘額與未結資訊，再呼叫規則、保存新版本及 Audit。傳入舊快照不等於並行安全；此套件測試僅證明規則，不替代真實 adapter 的競爭測試。重新啟用保留最近關閉資訊，每次歷史狀態仍由 Audit 保存；沒有實作刪除歷史的操作。

```sh
dart pub get --enforce-lockfile
dart analyze
dart test --reporter expanded
```

目前 9 項 Domain 測試通過；資料庫保存／重建、Audit、期初 Ledger event、UI、加密與備份尚待接入，因此不能標記完整 Account capability verified 或 enabled。
