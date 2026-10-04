# ExpenseTracker V2

Android 優先、Flutter、local-first 的個人財務管理 App。

## 現況

底層（帳本、信用卡、投資、預算、定期交易、加密儲存、備份與 Drive 上傳）已重建完成；介面正在重做。進度與待辦見 [docs/STATUS.md](docs/STATUS.md)，架構見 [ADR-0001](docs/adr/0001-target-architecture.md)。

## 結構

- `packages/`：業務套件（金額值物件、帳本、信用卡、投資、預算等），是要沿用的核心。
- `infrastructure/`：加密資料庫、帳本投影、金鑰、備份格式、Google Drive 上傳等執行層。
- `apps/expense_tracker/`：新 App（Flutter），介面重建中。舊 App 已移除，要查請看 git 歷史。
- `tooling/`：架構邊界檢查與本機檢查腳本。
- `docs/`：狀態、架構決策、產品需求。

## 本機檢查

```powershell
./tooling/run-host-checks.ps1 -Package all
```

提交前請先在變更過的套件執行 `dart format .`（Flutter 套件同樣適用）。
