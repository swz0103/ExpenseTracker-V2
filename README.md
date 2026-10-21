# 記帳本（ExpenseTracker V2）

Android 優先、Flutter、資料只存在手機（local-first）的個人記帳 App。

## 現況

帳本、信用卡、投資、預算、定期交易、加密儲存與備份都已完成，介面可日常使用；剩下真機驗收與簽章。進度見 [docs/STATUS.md](docs/STATUS.md)，架構見 [ADR-0001](docs/adr/0001-target-architecture.md)。

## 結構

依賴只能往下：App → 執行層 → 規則 → 基礎。

| 位置 | 內容 |
| --- | --- |
| `apps/expense_tracker/` | App（Flutter）：畫面、帳本模型（唯一的一份）、把每筆資料存進加密檔的 `TableJournal`。 |
| `infrastructure/vault/` | 金鑰、打開帳本、加密備份。 |
| `infrastructure/storage/` | SQLCipher 加密檔：每筆資料一列 JSON。 |
| `infrastructure/market/` | 證交所、櫃買中心收盤價與臺灣銀行牌告匯率。 |
| `packages/domain/` | 計算規則：持股成本、配股減資、台股費用、信用卡帳單週期與分期、CSV、電子發票。 |
| `packages/core/` | 金額、日期、匯率等值物件與時鐘。 |
| `tooling/architecture_checks` | CI 的輕量檢查：core／domain 不碰平台、測試寫明預期的失敗、lockfile 版本一致。 |
| `tooling/` | 架構檢查與本機檢查腳本。 |
| `docs/` | 狀態、架構決策、設定說明。 |

## 檢查

```powershell
./tooling/run-host-checks.ps1 -Package all   # 或 -Package packages/domain
```

每個模組會依序執行 `pub get --enforce-lockfile`、`dart format` 檢查、`analyze`、測試。CI 另外建 Android APK、網頁預覽，並在模擬器量測載入與存檔時間。

沒有 Flutter SDK 時，把分支推到 `tools/<名稱>`：`Flutter tools` 工作流程會更新改過的 `pubspec.lock` 並排版，結果放在 `tools/<名稱>-done`，合併回來即可。
