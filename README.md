# ExpenseTracker V2

Android 優先、Flutter、local-first 的個人財務管理 App。

## 現況

目前處於**功能凍結與架構重建期**，只接受修正，不加新功能。進度與下一步見 [docs/STATUS.md](docs/STATUS.md)，目標架構見 [ADR-0001](docs/adr/0001-target-architecture.md)。

## 結構

- `packages/`：業務套件（金額值物件、帳本、信用卡、投資、預算等），是要沿用的核心。
- `prototypes/expense_preview/`：目前可安裝的 App。
- `prototypes/` 其餘：目前 App 實際使用的儲存、備份、雲端實作，將在重建中搬入正式套件。
- `tooling/`：架構邊界檢查與本機檢查腳本。
- `docs/`：產品需求、資料與備份契約、功能規格。

## 本機檢查

```powershell
./tooling/run-host-checks.ps1 -Package all
```

提交前請先在變更過的套件執行 `dart format .`（Flutter 套件同樣適用）。
