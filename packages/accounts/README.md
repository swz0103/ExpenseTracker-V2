# accounts

帳戶的 Domain 規則，只依賴 `foundation_values`。

- 種類：現金、銀行、信用卡。沒有餘額欄位，餘額由分錄算出。
- 操作：開立、改名、變更淨資產納入、封存、結清（餘額須為零、不能有未結事項）、重新啟用。
- `version` 每次變更都加 1；`rulesVersion` 只有封存、結清、重新啟用才加，記帳只檢查它，所以改名不會讓準備好的記帳失效（健檢 G1-09）。
- `Account.restore` 會重新檢查所有規則，用於從儲存還原。

```sh
dart pub get --enforce-lockfile
dart analyze
dart test --reporter expanded
```
