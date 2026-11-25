# 參與開發

這是個人專案，歡迎回報問題與提出修改。開始前請先讀 [docs/development.md](docs/development.md)（環境與指令）與 [docs/conventions.md](docs/conventions.md)（寫法規範）。

## 流程

1. 先開 issue 說明要改什麼（小修正可以直接開 PR）。
2. 一個 PR 做一件事：一個工作包或一個主題，不夾帶無關的整理。
3. 在 `apps/expense_tracker` 跑 `flutter analyze` 與 `flutter test`；改到 `packages/`、`infrastructure/` 的，在那個資料夾跑 `dart analyze` 與 `dart test`。
4. 在根目錄跑規則檢查器：`dart run tooling/rules/bin/check.dart`。

## 規則檢查器與基線

- `tooling/rules` 檢查架構規則，現有的違規記在 `baseline.json`，只准變少：新增違規會失敗，改善了也要用 `--update` 更新基線。不要用 `--allow-growth`。
- 每件事只能有一個來源（登記在 `tooling/rules/owners.yaml`）：新增一個來源就登記進去，不要留下重複的實作或轉接的殼。
- 純計算放 `packages/`（不碰 Flutter、不讀時鐘、不做 I/O），App 只負責組合。

## 受保護的測試

- `apps/expense_tracker/test/baseline/` 記錄「現在是對的」行為，不能改。若某個測試失敗是因為舊行為本來就是錯的，PR 要說明，並在 commit 訊息加一行 `Baseline-Change: <原因>`，等維護者同意。
- `apps/expense_tracker/test/known_defects/` 是已知錯誤的測試，修好一個就取消它的略過，並把它從 `STATUS.md` 的表移到「fixed in」。

## 提交

- 訊息用英文，說明做了什麼與為什麼；程式與註解用英文，畫面上的文字用繁體中文。
- 要發布的 PR 要升版號、加 `docs/CHANGELOG.md` 與 `whats_new.txt`（見 [ADR-0011](docs/adr/0011-version-numbers.md)）。
- GitHub Actions 一律用完整的 commit SHA 固定版本，不加第三方的 action。
- 不要提交金鑰與密碼：簽章金鑰只放在 GitHub Environment `release-signing`，本機的 `android/key.properties` 不進版控。

## 安全問題

請不要公開回報，見 [SECURITY.md](SECURITY.md)。
