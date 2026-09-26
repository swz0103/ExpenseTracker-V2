# SQLite 交易邊界驗證原型

這是階段 1 的限定技術驗證，**不是正式 Ledger，也不是可供使用者記帳的功能**。固定兩個同幣別 legs，使用真實 SQLite 檔案、同一 transaction 與持久 operation receipt，驗證回滾、跨程序重試及去重競爭。

目前驗證環境為 Windows；在本目錄執行以下 PowerShell 步驟：

```powershell
dart pub get
dart analyze
dart build cli --target bin/worker.dart --output .dart_tool/worker
dart test --reporter expanded
```

子程序須先編譯，再啟動測試；避免測試執行期間重跑原生資源建置、嘗試覆寫已載入的 SQLite DLL。變更 worker 或其依賴後須重新編譯，缺少執行檔時測試會失敗，不會跳過。

測試在本目錄的 `.dart_tool/probe-tests/` 建立隔離資料；cleanup 先驗證解析後的絕對路徑仍在 fixture root 內。子程序在 commit 前／後直接退出，不依賴正常 close 或 finally，觀察重開後的真實檔案結果。

本原型不包含正式 Account／UUID／Money／FX／refund policy、Drift adapter、加密、Android 執行、備份或 migration。因此通過只能作為 [TX-01／02／03／06](../../docs/foundation-acceptance.md) 中機制層面的證據，不能標示相關業務功能或安全 gate 已完成。正式跨套件 adapter 與加密環境仍須重新驗證。

SQLite binding 依據套件作者的 [sqlite3 文件](https://pub.dev/packages/sqlite3)。相依版本與 lockfile 固定於本原型，尚未定為正式 App 的 dependency 選擇。
